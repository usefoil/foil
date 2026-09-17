#!/usr/bin/env bash
set -euo pipefail

: "${FOIL_CI_SHARD:?FOIL_CI_SHARD is required}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
: "${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${RUNNER_WORKSPACE:?RUNNER_WORKSPACE is required}"
case "$FOIL_CI_SHARD" in a|b|c) ;; *) echo 'invalid shard' >&2; exit 2 ;; esac
[[ "$GITHUB_RUN_ID" =~ ^[0-9]+$ && "$GITHUB_RUN_ATTEMPT" =~ ^[0-9]+$ ]] || exit 2
timeout_seconds="${FOIL_CI_SHARD_TIMEOUT_SECONDS:-840}"
[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || exit 2
enumeration_timeout_seconds="${FOIL_CI_ENUMERATION_TIMEOUT_SECONDS:-90}"
[[ "$enumeration_timeout_seconds" =~ ^[1-9][0-9]*$ ]] || exit 2
export RUN_LIVE_GROQ_TESTS=0 RUN_LIVE_MICROPHONE_TESTS=0

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$repo_root"
workspace_root="$(cd "$RUNNER_WORKSPACE" && pwd -P)"
run_root="$workspace_root/foil-ci-runs/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${FOIL_CI_SHARD}"
artifact_root="$repo_root/artifacts/shard-${FOIL_CI_SHARD}"
final_receipt="$repo_root/artifacts/receipt-${FOIL_CI_SHARD}.json"
# Never overwrite evidence from a previous invocation with the same workflow attempt.
if [ -e "$artifact_root" ] || [ -e "$final_receipt" ] || [ -e "$run_root" ]; then
  echo 'refusing to overwrite existing shard state or artifacts' >&2
  exit 2
fi
mkdir -p "$artifact_root" "$run_root"
SECONDS=0
local_attempt=1
child_pid=""
watchdog_pid=""
child_timer_pid=""
interrupted=false
cleanup_failed=false
run_cleaned=false
phase="initializing"
build_exit=null
test_exit=null
fixture_exit=null
infrastructure_kind=""
sha=""
attempt_dir="$artifact_root/attempt-1"
mkdir -p "$attempt_dir"
preflight="$attempt_dir/preflight.json"
selector_file="$attempt_dir/selectors.txt"

cancel_child_timer() {
  if [ -n "$child_timer_pid" ]; then
    kill -KILL "$child_timer_pid" 2>/dev/null || true
    wait "$child_timer_pid" 2>/dev/null || true
    child_timer_pid=""
  fi
}

arm_child_timer() {
  # The timer stays alive until explicitly reaped, avoiding a stale timer PID.
  # Only the executor's still-owned direct child can receive TERM/KILL.
  node -e 'const {execFileSync}=require("child_process"),fs=require("fs");
    const [pid,parent,seconds,marker]=process.argv.slice(1);
    const owned=()=>{try{return execFileSync("ps",["-o","ppid=","-p",pid],
      {encoding:"utf8",timeout:500,stdio:["ignore","pipe","ignore"]}).trim()===parent}catch{return false}};
    setInterval(()=>{},60000);
    setTimeout(()=>{if(owned()){
      if(marker)fs.writeFileSync(marker,"command timed out\n");
      try{process.kill(Number(pid),"SIGTERM")}catch{}
      setTimeout(()=>{if(owned()){try{process.kill(Number(pid),"SIGKILL")}catch{}}},1000)
    }},Number(seconds)*1000)' "$child_pid" "$$" "$1" "$2" &
  child_timer_pid=$!
}

stop_child() {
  cancel_child_timer
  if [ -n "$child_pid" ]; then
    arm_child_timer 0 ""
    wait "$child_pid" 2>/dev/null || true
    child_pid=""
    cancel_child_timer
  fi
}

run_command() {
  "$@" &
  child_pid=$!
  local status=0
  local timeout_marker="$attempt_dir/timeout-$child_pid"
  if [ "${command_timeout:-0}" -gt 0 ]; then arm_child_timer "$command_timeout" "$timeout_marker"; fi
  wait "$child_pid" || status=$?
  child_pid=""
  cancel_child_timer
  [ ! -e "$timeout_marker" ] || status=124
  return "$status"
}

write_receipt() {
  command_timeout=3 run_command node "$repo_root/scripts/ci/shard-receipt.mjs" \
    --shard "$FOIL_CI_SHARD" --run-id "$GITHUB_RUN_ID" --workflow-attempt "$GITHUB_RUN_ATTEMPT" \
    --sha "$sha" --expected-sha "$GITHUB_SHA" --local-attempt "$local_attempt" \
    --seconds-remaining "$(( timeout_seconds - SECONDS ))" \
    --build-exit "$build_exit" --test-exit "$test_exit" --fixture-exit "$fixture_exit" \
    --interrupted "$interrupted" --infrastructure-kind "$infrastructure_kind" \
    --cleanup-failed "$cleanup_failed" --preflight "$preflight" --selectors "$selector_file" \
    --artifact-dir "$attempt_dir" --output "$attempt_dir/receipt.json" || return 1
  command_timeout=3 run_command cp "$attempt_dir/receipt.json" "$final_receipt"
}

collect_report() {
  local kind="$1"
  command_timeout=10 run_command xcrun xcresulttool get test-results summary --path "$attempt_dir/$kind.xcresult" \
    >"$attempt_dir/$kind-summary.json" 2>"$attempt_dir/$kind-summary.log" || infrastructure_kind=result_collection_failed
  command_timeout=10 run_command xcrun xcresulttool get test-results tests --path "$attempt_dir/$kind.xcresult" \
    >"$attempt_dir/$kind-tests.json" 2>"$attempt_dir/$kind-tests.log" || infrastructure_kind=result_collection_failed
}

cleanup_run() {
  [ "$run_cleaned" = false ] || return 0
  # before terminates scoped processes; after refuses deletion until they are gone.
  command_timeout=8 run_command bash "$repo_root/scripts/ci/runner-cleanup.sh" --workspace-root "$workspace_root" \
    --run-root "$run_root" --mode before >>"$attempt_dir/cleanup-stop.log" 2>&1 || cleanup_failed=true
  if command_timeout=8 run_command bash "$repo_root/scripts/ci/runner-cleanup.sh" --workspace-root "$workspace_root" \
    --run-root "$run_root" --mode after >>"$attempt_dir/cleanup-after.log" 2>&1; then
    run_cleaned=true
  else
    cleanup_failed=true
  fi
}

finish() {
  local status=$?
  trap - EXIT
  trap '' INT TERM HUP
  if [ -n "$watchdog_pid" ]; then kill -KILL "$watchdog_pid" 2>/dev/null || true; wait "$watchdog_pid" 2>/dev/null || true; fi
  # Finalization uses independently bounded commands inside the reserved minute.
  # Do not start new xcresult extraction after interruption; use saved evidence.
  stop_child
  if [ "$phase" = "ordinary" ]; then test_exit=143; fi
  if [ "$phase" = "fixture" ]; then fixture_exit=143; fi
  if [ "$status" -ne 0 ] && [ -z "$infrastructure_kind" ]; then infrastructure_kind=executor_failed; fi
  write_receipt || status=1
  cleanup_run
  write_receipt || status=1
  if ! command_timeout=3 run_command node -e 'const fs=require("fs");process.exit(JSON.parse(fs.readFileSync(process.argv[1])).classification==="passed"?0:1)' "$final_receipt"; then status=1; fi
  exit "$status"
}
trap finish EXIT
trap 'interrupted=true; exit 143' INT TERM HUP
# Bound the entire executor while leaving one minute inside the workflow's 15-minute ceiling.
node -e 'setInterval(()=>{},60000);setTimeout(()=>{try{process.kill(Number(process.argv[1]),"SIGTERM")}catch{}},Number(process.argv[2])*1000)' "$$" "$timeout_seconds" &
watchdog_pid=$!

attempt() {
  build_exit=null; test_exit=null; fixture_exit=null; infrastructure_kind=""; phase=preflight
  sha="$(git rev-parse HEAD)"
  node "$repo_root/scripts/ci/ui-test-inventory.mjs" selectors --shard "$FOIL_CI_SHARD" \
    --manifest "$repo_root/scripts/ci/ui-test-shards.json" >"$selector_file"
  if ! run_command node "$repo_root/scripts/ci/runner-preflight.mjs" \
    --baseline "$repo_root/scripts/ci/runner-baseline.json" --output "$preflight" >"$attempt_dir/preflight.log" 2>&1; then
    infrastructure_kind=preflight_failed; return
  fi
  if ! node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1]));process.exit(r.schemaVersion===1&&r.status==="healthy"&&Array.isArray(r.errors)&&r.errors.length===0?0:1)' \
    "$preflight" >>"$attempt_dir/preflight.log" 2>&1; then
    infrastructure_kind=preflight_failed; return
  fi
  if [ "$sha" != "$GITHUB_SHA" ]; then infrastructure_kind=wrong_sha; return; fi
  if ! run_command bash "$repo_root/scripts/ci/runner-cleanup.sh" --workspace-root "$workspace_root" \
    --run-root "$run_root" --mode before >"$attempt_dir/cleanup-before.log" 2>&1; then
    infrastructure_kind=before_cleanup_failed; return
  fi
  local derived_data="$run_root/DerivedData"
  phase=build
  build_exit=0
  run_command xcodebuild build-for-testing -scheme Foil -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
    -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO \
    -derivedDataPath "$derived_data" -resultBundlePath "$attempt_dir/build.xcresult" \
    >"$attempt_dir/build.log" 2>&1 || build_exit=$?
  if [ "$build_exit" -ne 0 ]; then infrastructure_kind=build_failed; return; fi
  local xctestruns=()
  local candidate
  for candidate in "$derived_data"/Build/Products/*.xctestrun; do
    [ ! -f "$candidate" ] || xctestruns+=("$candidate")
  done
  if [ "${#xctestruns[@]}" -ne 1 ]; then infrastructure_kind=ambiguous_xctestrun; return; fi
  local xctestrun_path="${xctestruns[0]}"
  local enumeration_json="$attempt_dir/enumeration.json"
  local enumeration_log="$attempt_dir/enumeration.log"
  phase=enumeration
  if ! command_timeout="$enumeration_timeout_seconds" run_command xcodebuild test-without-building -xctestrun "$xctestrun_path" \
    -destination 'platform=macOS,arch=arm64' -enumerate-tests -test-enumeration-style flat \
    -test-enumeration-format json -test-enumeration-output-path "$enumeration_json" \
    >"$enumeration_log" 2>&1; then infrastructure_kind=enumeration_command_failed; return; fi
  if grep -Fq 'Timed out while enabling automation mode.' "$enumeration_log"; then
    infrastructure_kind=enumeration_command_failed; return
  fi
  if ! node "$repo_root/scripts/ci/ui-test-inventory.mjs" check-built --enumeration "$enumeration_json" \
    --manifest "$repo_root/scripts/ci/ui-test-shards.json" >"$attempt_dir/inventory.log" 2>&1; then
    infrastructure_kind=built_inventory_failed; return
  fi
  local selectors=()
  while IFS= read -r candidate; do [ -z "$candidate" ] || selectors+=("$candidate"); done <"$selector_file"
  if [ "${#selectors[@]}" -eq 0 ]; then infrastructure_kind=empty_selectors; return; fi
  phase=ordinary
  test_exit=0
  run_command xcodebuild test-without-building -xctestrun "$xctestrun_path" \
    -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
    -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO \
    "${selectors[@]}" -resultBundlePath "$attempt_dir/ordinary.xcresult" \
    >"$attempt_dir/ordinary.log" 2>&1 || test_exit=$?
  phase=ordinary_report
  collect_report ordinary
  if [ "$FOIL_CI_SHARD" = "c" ] && [ "$test_exit" -eq 0 ]; then
    phase=fixture
    fixture_exit=0
    run_command env SKIP_BUILD_FOR_TESTING=1 XCTESTRUN_PATH="$xctestrun_path" \
      XCTEST_RESULT_BUNDLE_PATH="$attempt_dir/fixture.xcresult" DERIVED_DATA_PATH="$derived_data" \
      XCTEST_ARTIFACT_DIR="$attempt_dir/fixture-artifacts" \
      DESTINATION='platform=macOS,arch=arm64' E2E_RESULT_PATH="$attempt_dir/fixture-transcript.txt" \
      bash "$repo_root/scripts/run-fixture-transcription-e2e-xcuitest.sh" >"$attempt_dir/fixture.log" 2>&1 || fixture_exit=$?
    phase=fixture_report
    collect_report fixture
  fi
  phase=complete
}

attempt
write_receipt
if node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1]));process.exit(r.classification==="infra_failed"&&r.retryAllowed===true?0:1)' "$final_receipt"; then
  cleanup_run
  if [ "$cleanup_failed" = false ] && [ "$(( timeout_seconds - SECONDS ))" -ge 180 ]; then
    local_attempt=2
    mkdir -p "$run_root"
    run_cleaned=false
    attempt_dir="$artifact_root/attempt-2"
    mkdir -p "$attempt_dir"
    preflight="$attempt_dir/preflight.json"
    selector_file="$attempt_dir/selectors.txt"
    attempt
  elif [ "$cleanup_failed" = false ]; then
    infrastructure_kind=retry_budget_exhausted
  fi
fi

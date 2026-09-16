#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd -P)"
bootstrap="$repo_root/scripts/ci/bootstrap-foil-runner.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/foil-bootstrap-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
export BOOTSTRAP_TEST_LOG="$test_root/calls"
export RUNNER_REGISTRATION_TOKEN='secret-token-MUST-NOT-APPEAR'
fake_token="$RUNNER_REGISTRATION_TOKEN"
unset BOOTSTRAP_TEST_FAIL
passed=0

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { passed=$((passed + 1)); echo "PASS: $*"; }
[ -f "$bootstrap" ] || fail 'bootstrap script is missing'

# Stub only runner commands: they would register externally and load LaunchAgents.
new_runner() {
  runner_dir="$(mktemp -d "$test_root/runner.XXXXXX")"
  : > "$BOOTSTRAP_TEST_LOG"
  cat > "$runner_dir/config.sh" <<'STUB'
#!/usr/bin/env bash
set -eu
echo config >> "$BOOTSTRAP_TEST_LOG"
echo "$RUNNER_REGISTRATION_TOKEN"
echo "$RUNNER_REGISTRATION_TOKEN" >&2
[ "${BOOTSTRAP_TEST_FAIL:-}" != config ] || exit 17
[ ! -e .runner ] || exit 18
repo='' name='' labels='' token='' work='' unattended=false replace=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) repo="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --labels) labels="$2"; shift 2 ;;
    --token) token="$2"; shift 2 ;;
    --work) work="$2"; shift 2 ;;
    --unattended) unattended=true; shift ;;
    --replace) replace=true; shift ;;
    *) exit 19 ;;
  esac
done
[ "$repo" = https://github.com/usefoil/foil ]
[ "$name" = foil-mm1 ] || [ "$name" = foil-mm2 ] || [ "$name" = foil-mm3 ]
[ "$labels" = foil-deterministic ]
[ "$token" = "$RUNNER_REGISTRATION_TOKEN" ]
[ "$work" = _work ]
[ "$unattended" = true ] && [ "$replace" = true ]
[ "${BOOTSTRAP_TEST_FAIL:-}" != config-result ] || repo=https://github.com/foreign/repo
node -e 'require("fs").writeFileSync(".runner","\uFEFF"+JSON.stringify({agentId:42,agentName:process.argv[1],poolId:1,poolName:"Default",gitHubUrl:process.argv[2],workFolder:"_work"}))' "$name" "$repo"
STUB
  cat > "$runner_dir/svc.sh" <<'STUB'
#!/usr/bin/env bash
set -eu
echo "$1" >> "$BOOTSTRAP_TEST_LOG"
echo "${RUNNER_REGISTRATION_TOKEN:-}"
echo "${RUNNER_REGISTRATION_TOKEN:-}" >&2
[ "${BOOTSTRAP_TEST_FAIL:-}" != "$1" ] || exit 23
case "$1" in
  install) [ ! -e .service ]; touch .service ;;
  start) [ -e .service ]; touch .started ;;
  status)
    if [ ! -e .service ]; then echo 'not installed'
    elif [ ! -e .started ]; then echo Stopped
    else
      echo Started:
      name="$(node -p 'JSON.parse(require("fs").readFileSync(".runner","utf8").replace(/^\uFEFF/,"")).agentName')"
      [ "${BOOTSTRAP_TEST_FAIL:-}" != wrong-service ] || name=foil-mm9
      pid=12345
      [ "${BOOTSTRAP_TEST_FAIL:-}" != missing-pid ] || pid=-
      printf '%s 0 actions.runner.usefoil-foil.%s\n' "$pid" "$name"
    fi
    ;;
  *) exit 24 ;;
esac
STUB
  chmod +x "$runner_dir/config.sh" "$runner_dir/svc.sh"
}

run_bootstrap() {
  result=0
  bash "$bootstrap" --runner-dir "$runner_dir" "$@" > "$test_root/output" 2>&1 || result=$?
  if grep -Fq -- "$fake_token" "$test_root/output"; then fail 'token leaked'; fi
}
expect_failure() { [ "$result" -ne 0 ] || fail "$1 accepted"; }
expect_success() { [ "$result" -eq 0 ] || { cat "$test_root/output"; fail "$1 rejected"; }; }
expect_no_calls() { [ ! -s "$BOOTSTRAP_TEST_LOG" ] || fail 'unexpected runner command'; }
write_registration() {
  node -e 'require("fs").writeFileSync(process.argv[1],JSON.stringify({agentId:42,agentName:process.argv[2],gitHubUrl:process.argv[3],workFolder:"_work"}))' "$runner_dir/.runner" "$1" "$2"
}

new_runner
run_bootstrap --runner-name other --dry-run
expect_failure 'unknown runner name'; expect_no_calls; pass 'unknown name rejected'
run_bootstrap --runner-name foil-mm1 --repo-url https://github.com/foreign/repo --dry-run
expect_failure 'wrong repository URL'; expect_no_calls; pass 'wrong repo rejected'
unset RUNNER_REGISTRATION_TOKEN
run_bootstrap --runner-name foil-mm1
expect_failure 'missing token'; expect_no_calls; pass 'missing token rejected'
for name in foil-mm1 foil-mm2 foil-mm3; do
  run_bootstrap --runner-name "$name" --dry-run
  expect_success 'dry run without token'; expect_no_calls
  grep -Fq -- '--labels foil-deterministic' "$test_root/output" || fail 'dry-run label missing'
done
pass 'all allowed names dry-run without commands or token'
export RUNNER_REGISTRATION_TOKEN="$fake_token"
run_bootstrap --runner-name foil-mm1 --dry-run
expect_success 'dry run with token'; expect_no_calls; pass 'dry-run token redacted'

write_registration foil-mm1 https://github.com/foreign/repo
registration_before="$(cksum "$runner_dir/.runner")"
run_bootstrap --runner-name foil-mm1
expect_failure 'foreign registration'; expect_no_calls
[ "$(cksum "$runner_dir/.runner")" = "$registration_before" ] || fail 'foreign registration changed'
run_bootstrap --runner-name foil-mm1 --dry-run
expect_failure 'foreign registration dry-run'; expect_no_calls; pass 'foreign registration preserved'
write_registration foil-mm2 https://github.com/usefoil/foil
run_bootstrap --runner-name foil-mm1
expect_failure 'foreign runner name'; expect_no_calls; pass 'foreign name preserved'
printf '{invalid' > "$runner_dir/.runner"
run_bootstrap --runner-name foil-mm1
expect_failure 'malformed registration'; expect_no_calls; pass 'malformed registration rejected'

new_runner
run_bootstrap --runner-name foil-mm1
expect_success 'fresh bootstrap'
[ "$(cat "$BOOTSTRAP_TEST_LOG")" = $'config\ninstall\nstart\nstatus' ] || fail 'incorrect configure/install/start/status sequence'
[ -f "$runner_dir/.foil-runner-bootstrap.json" ] || fail 'marker missing'
grep -Fq -- "$fake_token" "$runner_dir/.foil-runner-bootstrap.json" && fail 'marker stores token'
pass 'fresh bootstrap verifies config and starts per-user service without leaking token'
: > "$BOOTSTRAP_TEST_LOG"
unset RUNNER_REGISTRATION_TOKEN
run_bootstrap --runner-name foil-mm1
expect_success 'correct existing runner without token'
[ "$(cat "$BOOTSTRAP_TEST_LOG")" = status ] || fail 'existing runner was mutated'
pass 'marker-backed idempotency needs no token or mutations'

for failure in wrong-service missing-pid; do
  export BOOTSTRAP_TEST_FAIL="$failure"
  run_bootstrap --runner-name foil-mm1
  expect_failure "$failure service status"
  pass "$failure is not accepted as a running Foil service"
done
unset BOOTSTRAP_TEST_FAIL

mv "$runner_dir/.started" "$runner_dir/stopped-state"
: > "$BOOTSTRAP_TEST_LOG"
run_bootstrap --runner-name foil-mm1
expect_failure 'stopped service'; pass 'svc status exit zero does not imply running'
mv "$runner_dir/stopped-state" "$runner_dir/.started"
mv "$runner_dir/.foil-runner-bootstrap.json" "$runner_dir/saved-marker"
: > "$BOOTSTRAP_TEST_LOG"
run_bootstrap --runner-name foil-mm1
expect_failure 'unmarked registration'; expect_no_calls
export RUNNER_REGISTRATION_TOKEN="$fake_token"
run_bootstrap --runner-name foil-mm1
expect_failure 'unmarked registration with token'; expect_no_calls
run_bootstrap --runner-name foil-mm1 --dry-run
expect_success 'unmarked dry-run'; expect_no_calls
grep -qi 'repair' "$test_root/output" || fail 'repair guidance missing'
pass 'unmarked registration requires explicit maintenance repair'
printf '{"schemaVersion":1,"repoUrl":"https://github.com/usefoil/foil","runnerName":"foil-mm1","labels":["other"]}' > "$runner_dir/.foil-runner-bootstrap.json"
run_bootstrap --runner-name foil-mm1
expect_failure 'marker with wrong labels'; expect_no_calls; pass 'mismatched marker fails closed'

for failure in config install start status; do
  new_runner
  export BOOTSTRAP_TEST_FAIL="$failure"
  run_bootstrap --runner-name foil-mm1
  expect_failure "$failure command failure"
  case "$failure" in
    config) [ "$(cat "$BOOTSTRAP_TEST_LOG")" = config ] || fail 'continued after config failure' ;;
    install) [ "$(cat "$BOOTSTRAP_TEST_LOG")" = $'config\ninstall' ] || fail 'continued after install failure' ;;
    start) [ "$(cat "$BOOTSTRAP_TEST_LOG")" = $'config\ninstall\nstart' ] || fail 'continued after start failure' ;;
  esac
  pass "$failure failure is propagated with token redacted"
done
unset BOOTSTRAP_TEST_FAIL
new_runner
export BOOTSTRAP_TEST_FAIL=config-result
run_bootstrap --runner-name foil-mm1
expect_failure 'configuration wrote foreign metadata'
[ "$(cat "$BOOTSTRAP_TEST_LOG")" = config ] || fail 'service started despite wrong registration result'
[ ! -e "$runner_dir/.foil-runner-bootstrap.json" ] || fail 'marker endorses wrong registration result'
pass 'post-config metadata mismatch prevents marker and service mutation'
unset BOOTSTRAP_TEST_FAIL
new_runner
touch "$runner_dir/.credentials"
run_bootstrap --runner-name foil-mm1
expect_failure 'orphan credentials'; expect_no_calls; pass 'partial credentials preserved without registration'
new_runner
result=0
bash -x "$bootstrap" --runner-dir "$runner_dir" --runner-name foil-mm1 > "$test_root/output" 2>&1 || result=$?
expect_success 'bootstrap under inherited xtrace'
grep -Fq -- "$fake_token" "$test_root/output" && fail 'xtrace leaked token'
pass 'inherited xtrace cannot expose token'
echo "$passed bootstrap tests passed"

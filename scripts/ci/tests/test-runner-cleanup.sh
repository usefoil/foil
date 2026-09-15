#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd -P)"
cleanup_script="$repo_root/scripts/ci/runner-cleanup.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

fake_bin="$fixture_root/bin"
ps_output="$fixture_root/ps-output"
ps_recheck_output="$fixture_root/ps-recheck-output"
signal_file="$fixture_root/signal-sent"
mkdir -p "$fake_bin"
: >"$ps_output"
: >"$ps_recheck_output"
cat >"$fake_bin/ps" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-p" ]; then
  cat "$FOIL_TEST_PS_RECHECK_OUTPUT"
  if [ "${FOIL_TEST_CLEAR_ON_RECHECK:-0}" = "1" ]; then
    : >"$FOIL_TEST_PS_OUTPUT"
  fi
  exit 0
fi
if [ -n "${FOIL_TEST_SWAP_SOURCE:-}" ] && [ ! -e "$FOIL_TEST_SWAP_SENTINEL" ]; then
  touch "$FOIL_TEST_SWAP_SENTINEL"
  mv "$FOIL_TEST_SWAP_SOURCE" "$FOIL_TEST_SWAP_MOVED"
  ln -s "$FOIL_TEST_SWAP_TARGET" "$FOIL_TEST_SWAP_SOURCE"
fi
cat "$FOIL_TEST_PS_OUTPUT"
EOF
cat >"$fake_bin/kill" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$FOIL_TEST_SIGNAL_FILE"
: >"$FOIL_TEST_PS_OUTPUT"
EOF
chmod +x "$fake_bin/ps"
chmod +x "$fake_bin/kill"

run_cleanup() {
  FOIL_TEST_PS_OUTPUT="$ps_output" \
    FOIL_TEST_PS_RECHECK_OUTPUT="$ps_recheck_output" \
    FOIL_TEST_SIGNAL_FILE="$signal_file" \
    PATH="$fake_bin:$PATH" \
    "$cleanup_script" "$@"
}

expect_failure() {
  description="$1"
  shift
  if "$@" >"$fixture_root/unexpected-stdout" 2>"$fixture_root/expected-stderr"; then
    echo "$description unexpectedly succeeded" >&2
    exit 1
  fi
}

assert_exists() {
  if [ ! -e "$1" ]; then
    echo "expected fixture to remain: $1" >&2
    exit 1
  fi
}

workspace="$fixture_root/work"
run_root="$workspace/123-1-a"
mkdir -p "$run_root"
touch "$run_root/keep"

# A validated dry-run and before cleanup must never delete the run root.
FOIL_CI_DRY_RUN=1 run_cleanup \
  --workspace-root "$workspace" --run-root "$run_root" --mode before \
  >"$fixture_root/before-dry-run.log"
assert_exists "$run_root/keep"

run_cleanup --workspace-root "$workspace" --run-root "$run_root" --mode before
assert_exists "$run_root/keep"

# Every unsafe path must fail closed without deleting its marker.
touch "$fixture_root/parent-marker"
expect_failure "unsafe parent cleanup" env FOIL_CI_DRY_RUN=1 \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "$fixture_root" --mode before
assert_exists "$fixture_root/parent-marker"

touch "$workspace/workspace-marker"
expect_failure "workspace-root cleanup" env FOIL_CI_DRY_RUN=1 \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "$workspace" --mode after
assert_exists "$workspace/workspace-marker"

outside_root="$fixture_root/outside/456-2-b"
mkdir -p "$outside_root"
touch "$outside_root/symlink-escape-marker"
ln -s "$outside_root" "$workspace/456-2-b"
expect_failure "symlink escape cleanup" env FOIL_CI_DRY_RUN=1 \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "$workspace/456-2-b" --mode after
assert_exists "$outside_root/symlink-escape-marker"

invalid_root="$workspace/not-a-run"
mkdir -p "$invalid_root"
touch "$invalid_root/invalid-name-marker"
expect_failure "invalid basename cleanup" env FOIL_CI_DRY_RUN=1 \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "$invalid_root" --mode after
assert_exists "$invalid_root/invalid-name-marker"

home_root="$workspace/789-3-c"
mkdir -p "$home_root"
touch "$home_root/home-marker"
expect_failure "home cleanup" env HOME="$home_root" FOIL_CI_DRY_RUN=1 \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "$home_root" --mode after
assert_exists "$home_root/home-marker"

expect_failure "empty run root" env FOIL_CI_DRY_RUN=1 \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "" --mode before
expect_failure "empty workspace root" env FOIL_CI_DRY_RUN=1 \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "" --run-root "$run_root" --mode before
expect_failure "filesystem root" env FOIL_CI_DRY_RUN=1 \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "/" --run-root "/" --mode after
expect_failure "missing run root" env FOIL_CI_DRY_RUN=1 \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "$workspace/999-9-a" --mode after
expect_failure "invalid mode" env FOIL_CI_DRY_RUN=1 \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "$run_root" --mode during
expect_failure "unknown argument" env FOIL_CI_DRY_RUN=1 \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "$run_root" --mode before --all

# Process matching is exact for app names and doubly scoped for test tools.
workspace_canonical="$(cd "$workspace" && pwd -P)"
cat >"$ps_output" <<EOF
  101 Foil /Applications/Foil.app/Contents/MacOS/Foil
  102 FoilE2E $workspace_canonical/FoilE2E
  103 FoilHelper $workspace_canonical/FoilHelper
  104 xcodebuild /usr/bin/xcodebuild test -project $workspace_canonical/Foil.xcodeproj
  105 xctest $workspace_canonical/Build/FoilUITests.xctest/FoilUITests
  106 xcodebuild /usr/bin/xcodebuild test -project $workspace_canonical/Other.xcodeproj
  107 xctest /tmp/FoilTests.xctest/FoilTests
  108 unrelated $workspace_canonical/Foil
  109 xcodebuild /usr/bin/xcodebuild test -project ${workspace_canonical}-other/Foil.xcodeproj
EOF
FOIL_CI_DRY_RUN=1 run_cleanup \
  --workspace-root "$workspace" --run-root "$run_root" --mode before \
  >"$fixture_root/process-dry-run.log"
for pid in 101 102 104 105; do
  if ! grep -F "pid $pid " "$fixture_root/process-dry-run.log" >/dev/null; then
    echo "expected pid $pid was not selected; actual log:" >&2
    sed 's/^/  /' "$fixture_root/process-dry-run.log" >&2
    exit 1
  fi
done
for pid in 103 106 107 108 109; do
  if grep -F "pid $pid " "$fixture_root/process-dry-run.log" >/dev/null; then
    echo "unrelated pid $pid was selected" >&2
    exit 1
  fi
done

# A PID whose identity changes after discovery must never be signaled.
cat >"$ps_output" <<EOF
  201 Foil $workspace_canonical/Foil
EOF
cat >"$ps_recheck_output" <<EOF
  201 unrelated $workspace_canonical/unrelated
EOF
expect_failure "changed process identity" env \
  FOIL_TEST_PS_OUTPUT="$ps_output" \
  FOIL_TEST_PS_RECHECK_OUTPUT="$ps_recheck_output" \
  FOIL_TEST_SIGNAL_FILE="$signal_file" \
  PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "$run_root" --mode before
if [ -e "$signal_file" ]; then
  echo "changed process identity was signaled" >&2
  exit 1
fi

# A process that exits between discovery and revalidation is already clean.
cat >"$ps_output" <<EOF
  203 Foil $workspace_canonical/Foil
EOF
: >"$ps_recheck_output"
rm -f -- "$signal_file"
FOIL_TEST_PS_OUTPUT="$ps_output" \
  FOIL_TEST_PS_RECHECK_OUTPUT="$ps_recheck_output" \
  FOIL_TEST_SIGNAL_FILE="$signal_file" \
  FOIL_TEST_CLEAR_ON_RECHECK=1 \
  PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "$run_root" --mode before \
  >"$fixture_root/vanished-process.log"
if [ -e "$signal_file" ]; then
  echo "vanished process was signaled" >&2
  exit 1
fi

# A still-matching exact process is terminated with TERM, then absence is verified.
cat >"$ps_output" <<EOF
  202 Foil $workspace_canonical/Foil
EOF
cat >"$ps_recheck_output" <<EOF
  202 Foil $workspace_canonical/Foil
EOF
run_cleanup --workspace-root "$workspace" --run-root "$run_root" --mode before \
  >"$fixture_root/process-cleanup.log"
grep -Fx -- "-TERM 202" "$signal_file" >/dev/null
assert_exists "$run_root/keep"

# After mode refuses deletion while a known process remains.
cat >"$ps_output" <<EOF
  101 Foil /Applications/Foil.app/Contents/MacOS/Foil
EOF
blocked_root="$workspace/222-2-b"
mkdir -p "$blocked_root"
touch "$blocked_root/process-marker"
expect_failure "after cleanup with live Foil process" env \
  FOIL_TEST_PS_OUTPUT="$ps_output" PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$workspace" --run-root "$blocked_root" --mode after
assert_exists "$blocked_root/process-marker"

# Dry-run reports deletion without doing it; real after mode removes only its run root.
: >"$ps_output"
dry_after_root="$workspace/333-3-c"
mkdir -p "$dry_after_root"
touch "$dry_after_root/dry-marker"
dry_after_canonical="$(cd "$dry_after_root" && pwd -P)"
FOIL_CI_DRY_RUN=1 run_cleanup \
  --workspace-root "$workspace" --run-root "$dry_after_root" --mode after \
  >"$fixture_root/after-dry-run.log"
grep -F "dry-run: remove $dry_after_canonical" "$fixture_root/after-dry-run.log" >/dev/null
assert_exists "$dry_after_root/dry-marker"

# An ancestor swap after validation cannot redirect deletion through a symlink.
race_base="$fixture_root/race"
race_workspace="$race_base/work"
race_moved="$race_base/work-moved"
race_outside="$race_base/outside"
race_run="$race_workspace/666-6-c"
mkdir -p "$race_run" "$race_outside/666-6-c"
touch "$race_run/original-marker" "$race_outside/666-6-c/outside-marker"
: >"$ps_output"
race_status=0
FOIL_TEST_PS_OUTPUT="$ps_output" \
  FOIL_TEST_SWAP_SOURCE="$race_workspace" \
  FOIL_TEST_SWAP_MOVED="$race_moved" \
  FOIL_TEST_SWAP_TARGET="$race_outside" \
  FOIL_TEST_SWAP_SENTINEL="$fixture_root/race-swapped" \
  PATH="$fake_bin:$PATH" "$cleanup_script" \
  --workspace-root "$race_workspace" --run-root "$race_run" --mode after \
  >"$fixture_root/race-cleanup.log" 2>"$fixture_root/race-cleanup.err" || \
  race_status="$?"
if [ "$race_status" -eq 0 ]; then
  echo "ancestor swap cleanup unexpectedly succeeded" >&2
  exit 1
fi
assert_exists "$race_moved/666-6-c/original-marker"
assert_exists "$race_outside/666-6-c/outside-marker"

remove_root="$workspace/444-4-a"
sibling_root="$workspace/555-5-b"
mkdir -p "$remove_root" "$sibling_root"
touch "$remove_root/remove-marker" "$sibling_root/sibling-marker"
run_cleanup --workspace-root "$workspace" --run-root "$remove_root" --mode after
if [ -e "$remove_root" ]; then
  echo "validated after cleanup did not remove its run root" >&2
  exit 1
fi
assert_exists "$sibling_root/sibling-marker"

echo "runner cleanup tests: PASS"

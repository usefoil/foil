#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/fresh-user-tcc-qa.sh"
TMP_ROOT="$(mktemp -d)"

trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq "$expected" "$file"; then
    echo "---- output: $file ----" >&2
    cat "$file" >&2
    echo "------------------------" >&2
    fail "expected output to contain: $expected"
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq "$unexpected" "$file"; then
    echo "---- output: $file ----" >&2
    cat "$file" >&2
    echo "------------------------" >&2
    fail "expected output not to contain: $unexpected"
  fi
}

make_ssh_shim() {
  local shim_path="$1"
  local log_path="$2"
  cat >"$shim_path" <<SH
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >>"$log_path"
cmd="\${@: -1}"
case "\$cmd" in
  *"hostname="*)
    cat <<'OUT'
hostname=Jeremys-Mac-mini-2.local
local_hostname=Jeremys-Mac-mini-2
computer_name=Jeremy's Mac mini (2)
sw_vers.ProductName=macOS
sw_vers.ProductVersion=26.2
sw_vers.BuildVersion=25C56
arch=arm64
user=jeremywatt
hardware_uuid=TEST-HARDWARE-UUID
OUT
    ;;
  *"brew --version"*)
    cat <<'OUT'
homebrew=Homebrew 6.0.5-test
gh=gh version 2.88.1-test
xcodebuild=Xcode 26.2 Build version 17C99
OUT
    ;;
  *"sudo -n true"*)
    echo "sudo_noninteractive=no"
    ;;
  *"RUNNER_NAME"*)
    cat <<'OUT'
github_actions=
runner_name=
runner_os=
runner_arch=
github_run_id=
github_ref=
github_sha=
OUT
    ;;
  *"pgrep -x Foil"*)
    cat <<'OUT'
collected_at=2026-07-07T00:00:00Z
console_user=jeremywatt
foil_running=yes
pid=123
123 /Applications/Foil.app/Contents/MacOS/Foil
OUT
    ;;
  *"tail -120"*)
    cat <<'OUT'
log_path=/Users/jeremywatt/Library/Application Support/Foil/Diagnostics/foil.log
log_exists=yes
log_size=12345
2026-07-07T00:00:00Z SetupHealth: accessibilityTrusted=true
2026-07-07T00:00:00Z SetupHealth: microphone=authorized
2026-07-07T00:00:00Z SetupHealth: inputDevices count=0 selectedUID=systemDefault microphoneState=needsAction(No microphone detected)
OUT
    ;;
  *"system_profiler SPAudioDataType"*)
    cat <<'OUT'
Audio:

    Devices:

        Mac mini Speakers:

          Default Output Device: Yes
          Manufacturer: Apple Inc.
OUT
    ;;
  *"sqlite3"*)
    cat <<'OUT'
db_path=/Users/jeremywatt/Library/Application Support/com.apple.TCC/TCC.db
db_exists=yes
kTCCServiceMicrophone|com.neonwatty.Foil|2|3|1780000000
OUT
    ;;
  *"PlistBuddy"*)
    cat <<'OUT'
app_path=/Applications/Foil.app
exists=yes
bundle_id=com.neonwatty.Foil
short_version=1.13.4
build=39
OUT
    ;;
  *)
    echo "unexpected command: \$cmd" >&2
    exit 99
    ;;
esac
SH
  chmod +x "$shim_path"
}

expect_preflight_success() {
  local name="preflight-success"
  local dir="$TMP_ROOT/$name"
  local ssh_log="$dir/ssh.log"
  local output="$dir/output.txt"
  mkdir -p "$dir"
  make_ssh_shim "$dir/ssh" "$ssh_log"

  SSH="$dir/ssh" "$SCRIPT" preflight --host mm2 --evidence-dir "$dir/evidence" \
    --expected-hostname "Jeremys-Mac-mini-2.local" >"$output" 2>&1

  assert_contains "$output" "Preflight passed."
  assert_contains "$ssh_log" "AddressFamily=inet6"
  assert_contains "$dir/evidence/app-identity.txt" "short_version=1.13.4"
  assert_contains "$dir/evidence/summary.txt" "macos_version=26.2"
  assert_contains "$dir/evidence/summary.txt" "private_artifact_note="
  assert_contains "$dir/evidence/manifest.json" '"macos_version": "26.2"'
  assert_contains "$dir/evidence/manifest.json" '"hardware_uuid": "TEST-HARDWARE-UUID"'
  assert_contains "$dir/evidence/manifest.json" '"sudo_noninteractive": "no"'
  assert_contains "$dir/evidence/manifest.json" '"expected_bundle_id": "com.neonwatty.Foil"'
  assert_contains "$dir/evidence/manifest.json" '"manual_rows_status": "operator_confirmed_required"'
  assert_contains "$dir/evidence/operator-notes.md" "operator_confirmed"
}

expect_wrong_host_refused() {
  local name="wrong-host"
  local dir="$TMP_ROOT/$name"
  local ssh_log="$dir/ssh.log"
  local output="$dir/output.txt"
  mkdir -p "$dir"
  make_ssh_shim "$dir/ssh" "$ssh_log"

  if SSH="$dir/ssh" "$SCRIPT" preflight --host not-the-lab --evidence-dir "$dir/evidence" >"$output" 2>&1; then
    fail "wrong host preflight unexpectedly succeeded"
  fi

  assert_contains "$output" "refusing to contact non-allowlisted host"
  if [ -f "$ssh_log" ]; then
    fail "ssh was called for a non-allowlisted host"
  fi
}

expect_stale_app_fails_expected_version() {
  local name="stale-version"
  local dir="$TMP_ROOT/$name"
  local output="$dir/output.txt"
  mkdir -p "$dir"
  make_ssh_shim "$dir/ssh" "$dir/ssh.log"

  if SSH="$dir/ssh" "$SCRIPT" preflight --host mm2 --evidence-dir "$dir/evidence" \
    --expected-version "1.13.11" --expected-build "46" >"$output" 2>&1; then
    fail "stale app preflight unexpectedly succeeded"
  fi

  assert_contains "$output" "expected short_version '1.13.11' but found '1.13.4'"
  assert_contains "$dir/evidence/app-identity.txt" "build=39"
}

expect_wrong_arch_fails() {
  local name="wrong-arch"
  local dir="$TMP_ROOT/$name"
  local output="$dir/output.txt"
  mkdir -p "$dir"
  make_ssh_shim "$dir/ssh" "$dir/ssh.log"

  if SSH="$dir/ssh" "$SCRIPT" preflight --host mm2 --evidence-dir "$dir/evidence" \
    --expected-arch "x86_64" >"$output" 2>&1; then
    fail "wrong architecture preflight unexpectedly succeeded"
  fi

  assert_contains "$output" "expected arch 'x86_64' but found 'arm64'"
}

expect_wrong_bundle_id_fails() {
  local name="wrong-bundle-id"
  local dir="$TMP_ROOT/$name"
  local output="$dir/output.txt"
  mkdir -p "$dir"
  make_ssh_shim "$dir/ssh" "$dir/ssh.log"

  if SSH="$dir/ssh" "$SCRIPT" preflight --host mm2 --evidence-dir "$dir/evidence" \
    --expected-bundle-id "com.example.Other" >"$output" 2>&1; then
    fail "wrong bundle id preflight unexpectedly succeeded"
  fi

  assert_contains "$output" "expected bundle_id 'com.example.Other' but found 'com.neonwatty.Foil'"
}

expect_privileged_lifecycle_blocked() {
  local name="blocked-lifecycle"
  local dir="$TMP_ROOT/$name"
  local output="$dir/output.txt"
  mkdir -p "$dir"

  if "$SCRIPT" create-user --host mm2 >"$output" 2>&1; then
    fail "create-user unexpectedly succeeded"
  fi

  assert_contains "$output" "intentionally blocked"
}

expect_operator_rows_not_automated() {
  local name="operator-checklist"
  local dir="$TMP_ROOT/$name"
  local output="$dir/output.txt"
  mkdir -p "$dir"

  "$SCRIPT" print-operator-checklist >"$output"
  assert_contains "$output" "microphone-prompt-grant: operator_confirmed"
  assert_contains "$output" "must not be marked automated"
  assert_not_contains "$output" "microphone-prompt-grant: automated"
}

expect_collect_diagnostics() {
  local name="collect-diagnostics"
  local dir="$TMP_ROOT/$name"
  local ssh_log="$dir/ssh.log"
  local output="$dir/output.txt"
  mkdir -p "$dir"
  make_ssh_shim "$dir/ssh" "$ssh_log"

  SSH="$dir/ssh" "$SCRIPT" collect-diagnostics --host mm2 --evidence-dir "$dir/evidence" >"$output" 2>&1

  assert_contains "$output" "Diagnostics: $dir/evidence"
  assert_contains "$dir/evidence/process.txt" "foil_running=yes"
  assert_contains "$dir/evidence/process.txt" "/Applications/Foil.app/Contents/MacOS/Foil"
  assert_contains "$dir/evidence/diagnostics-tail.txt" "SetupHealth: microphone=authorized"
  assert_contains "$dir/evidence/diagnostics-tail.txt" "No microphone detected"
  assert_contains "$dir/evidence/audio-hardware.txt" "Mac mini Speakers"
  assert_contains "$dir/evidence/tcc-readonly.txt" "kTCCServiceMicrophone|com.neonwatty.Foil"
  assert_not_contains "$ssh_log" "tccutil reset"
  assert_not_contains "$ssh_log" "rm -rf"
}

expect_preflight_success
expect_wrong_host_refused
expect_stale_app_fails_expected_version
expect_wrong_arch_fails
expect_wrong_bundle_id_fails
expect_privileged_lifecycle_blocked
expect_operator_rows_not_automated
expect_collect_diagnostics

echo "fresh-user-tcc-qa shell tests passed."

#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/prepare-local-permissions-qa.sh"
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
    echo "---- output ----" >&2
    cat "$file" >&2
    echo "----------------" >&2
    fail "expected output to contain: $expected"
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq "$unexpected" "$file"; then
    echo "---- output ----" >&2
    cat "$file" >&2
    echo "----------------" >&2
    fail "expected output not to contain: $unexpected"
  fi
}

make_fixture_app() {
  local app_path="$1"
  local executable_name="${2:-GroqTalk}"
  local include_microphone="${3:-yes}"
  local create_executable="${4:-yes}"

  mkdir -p "$app_path/Contents/MacOS"
  cat >"$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.neonwatty.GroqTalk</string>
  <key>CFBundleExecutable</key>
  <string>$executable_name</string>
PLIST

  if [ "$include_microphone" = "yes" ]; then
    cat >>"$app_path/Contents/Info.plist" <<PLIST
  <key>NSMicrophoneUsageDescription</key>
  <string>GroqTalk needs microphone access to transcribe speech.</string>
PLIST
  fi

  cat >>"$app_path/Contents/Info.plist" <<PLIST
</dict>
</plist>
PLIST

  if [ "$create_executable" = "yes" ]; then
    printf '#!/bin/bash\nexit 0\n' >"$app_path/Contents/MacOS/$executable_name"
    chmod +x "$app_path/Contents/MacOS/$executable_name"
  fi
}

make_shims() {
  local shim_dir="$1"
  local pgrep_status="${2:-1}"
  mkdir -p "$shim_dir"

  cat >"$shim_dir/codesign" <<'SH'
#!/bin/bash
identifier="${SIGNED_IDENTIFIER:-com.neonwatty.GroqTalk}"
echo "Identifier=$identifier" >&2
if [ "${INCLUDE_AUTHORITY:-yes}" = "yes" ]; then
  echo "Authority=Apple Development: Local Test" >&2
fi
if [ "${INCLUDE_TEAM:-yes}" = "yes" ]; then
  echo "TeamIdentifier=LOCALTEAM" >&2
fi
SH
  chmod +x "$shim_dir/codesign"

  cat >"$shim_dir/pgrep" <<SH
#!/bin/bash
exit $pgrep_status
SH
  chmod +x "$shim_dir/pgrep"

  cat >"$shim_dir/forbidden" <<'SH'
#!/bin/bash
echo "forbidden command called: $0 $*" >&2
exit 99
SH
  chmod +x "$shim_dir/forbidden"
}

run_check() {
  local app_path="$1"
  local shim_dir="$2"
  local output="$3"
  shift 3

  env \
    APP_NAME="GroqTalk" \
    APP_PATH="$app_path" \
    CODESIGN="$shim_dir/codesign" \
    PGREP="$shim_dir/pgrep" \
    MAKE_CMD="$shim_dir/forbidden" \
    PKILL="$shim_dir/forbidden" \
    TCCUTIL="$shim_dir/forbidden" \
    OPEN_CMD="$shim_dir/forbidden" \
    SLEEP_CMD="$shim_dir/forbidden" \
    "$@" \
    "$SCRIPT" --check >"$output" 2>&1
}

expect_success() {
  local name="$1"
  local app_path="$TMP_ROOT/$name/GroqTalk.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path"
  make_shims "$shim_dir" 1

  run_check "$app_path" "$shim_dir" "$output"
  assert_contains "$output" "Result: passed"
  assert_contains "$output" "codesign identifier matches bundle id: com.neonwatty.GroqTalk"
  assert_contains "$output" "NSMicrophoneUsageDescription is present"
  assert_contains "$output" "macOS does not allow scripts to silently grant"
  assert_not_contains "$output" "forbidden command called"
}

expect_identifier_mismatch_failure() {
  local name="identifier-mismatch"
  local app_path="$TMP_ROOT/$name/GroqTalk.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path"
  make_shims "$shim_dir" 1

  if run_check "$app_path" "$shim_dir" "$output" SIGNED_IDENTIFIER="com.example.Other"; then
    fail "identifier mismatch check unexpectedly succeeded"
  fi
  assert_contains "$output" "signed identifier 'com.example.Other' does not match bundle id 'com.neonwatty.GroqTalk'"
  assert_contains "$output" "Result: failed"
}

expect_missing_microphone_failure() {
  local name="missing-microphone"
  local app_path="$TMP_ROOT/$name/GroqTalk.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path" "GroqTalk" "no"
  make_shims "$shim_dir" 1

  if run_check "$app_path" "$shim_dir" "$output"; then
    fail "missing microphone usage check unexpectedly succeeded"
  fi
  assert_contains "$output" "missing NSMicrophoneUsageDescription"
  assert_contains "$output" "Result: failed"
}

expect_missing_executable_failure() {
  local name="missing-executable"
  local app_path="$TMP_ROOT/$name/GroqTalk.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path" "GroqTalk" "yes" "no"
  make_shims "$shim_dir" 1

  if run_check "$app_path" "$shim_dir" "$output"; then
    fail "missing executable check unexpectedly succeeded"
  fi
  assert_contains "$output" "bundle executable is missing or not executable"
  assert_contains "$output" "Result: failed"
}

expect_running_warning() {
  local name="running-warning"
  local app_path="$TMP_ROOT/$name/GroqTalk.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path"
  make_shims "$shim_dir" 0

  run_check "$app_path" "$shim_dir" "$output"
  assert_contains "$output" "warning: GroqTalk is currently running"
  assert_contains "$output" "Result: passed with 1 warning(s)."
}

expect_success "success"
expect_identifier_mismatch_failure
expect_missing_microphone_failure
expect_missing_executable_failure
expect_running_warning

echo "prepare-local-permissions-qa shell tests passed."

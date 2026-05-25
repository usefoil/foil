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
  local executable_name="${2:-Foil}"
  local include_microphone="${3:-yes}"
  local create_executable="${4:-yes}"

  mkdir -p "$app_path/Contents/MacOS"
  cat >"$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.neonwatty.Foil</string>
  <key>CFBundleShortVersionString</key>
  <string>1.12.0</string>
  <key>CFBundleVersion</key>
  <string>42</string>
  <key>CFBundleExecutable</key>
  <string>$executable_name</string>
PLIST

  if [ "$include_microphone" = "yes" ]; then
    cat >>"$app_path/Contents/Info.plist" <<PLIST
  <key>NSMicrophoneUsageDescription</key>
  <string>Foil needs microphone access to transcribe speech.</string>
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
identifier="${SIGNED_IDENTIFIER:-com.neonwatty.Foil}"
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
if [ "$pgrep_status" -eq 0 ]; then
  echo "\${PGREP_OUTPUT:-123}"
fi
exit $pgrep_status
SH
  chmod +x "$shim_dir/pgrep"

  cat >"$shim_dir/ps" <<'SH'
#!/bin/bash
echo "${RUNNING_APP_ARGS:-/tmp/fixture/Foil.app/Contents/MacOS/Foil}"
SH
  chmod +x "$shim_dir/ps"

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
    APP_NAME="Foil" \
    APP_PATH="$app_path" \
    CODESIGN="$shim_dir/codesign" \
    PGREP="$shim_dir/pgrep" \
    PS_CMD="$shim_dir/ps" \
    MAKE_CMD="$shim_dir/forbidden" \
    PKILL="$shim_dir/forbidden" \
    TCCUTIL="$shim_dir/forbidden" \
    OPEN_CMD="$shim_dir/forbidden" \
    SLEEP_CMD="$shim_dir/forbidden" \
    "$@" \
    "$SCRIPT" --check >"$output" 2>&1
}

run_guide() {
  local app_path="$1"
  local shim_dir="$2"
  local output="$3"
  shift 3

  env \
    APP_NAME="Foil" \
    APP_PATH="$app_path" \
    EXPECTED_VERSION="1.12.0" \
    EXPECTED_BUILD="42" \
    CODESIGN="$shim_dir/codesign" \
    PGREP="$shim_dir/pgrep" \
    PS_CMD="$shim_dir/ps" \
    MAKE_CMD="$shim_dir/forbidden" \
    PKILL="$shim_dir/forbidden" \
    TCCUTIL="$shim_dir/forbidden" \
    OPEN_CMD="$shim_dir/open" \
    SLEEP_CMD="$shim_dir/sleep" \
    "$@" \
    "$SCRIPT" --guide-installed >"$output" 2>&1
}

expect_success() {
  local name="$1"
  local app_path="$TMP_ROOT/$name/Foil.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path"
  make_shims "$shim_dir" 1

  run_check "$app_path" "$shim_dir" "$output"
  assert_contains "$output" "Result: passed"
  assert_contains "$output" "bundle version is 1.12.0"
  assert_contains "$output" "bundle build is 42"
  assert_contains "$output" "codesign identifier matches bundle id: com.neonwatty.Foil"
  assert_contains "$output" "NSMicrophoneUsageDescription is present"
  assert_contains "$output" "macOS does not allow scripts to silently grant"
  assert_not_contains "$output" "forbidden command called"
}

expect_identifier_mismatch_failure() {
  local name="identifier-mismatch"
  local app_path="$TMP_ROOT/$name/Foil.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path"
  make_shims "$shim_dir" 1

  if run_check "$app_path" "$shim_dir" "$output" SIGNED_IDENTIFIER="com.example.Other"; then
    fail "identifier mismatch check unexpectedly succeeded"
  fi
  assert_contains "$output" "signed identifier 'com.example.Other' does not match bundle id 'com.neonwatty.Foil'"
  assert_contains "$output" "Result: failed"
}

expect_missing_microphone_failure() {
  local name="missing-microphone"
  local app_path="$TMP_ROOT/$name/Foil.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path" "Foil" "no"
  make_shims "$shim_dir" 1

  if run_check "$app_path" "$shim_dir" "$output"; then
    fail "missing microphone usage check unexpectedly succeeded"
  fi
  assert_contains "$output" "missing NSMicrophoneUsageDescription"
  assert_contains "$output" "Result: failed"
}

expect_missing_executable_failure() {
  local name="missing-executable"
  local app_path="$TMP_ROOT/$name/Foil.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path" "Foil" "yes" "no"
  make_shims "$shim_dir" 1

  if run_check "$app_path" "$shim_dir" "$output"; then
    fail "missing executable check unexpectedly succeeded"
  fi
  assert_contains "$output" "bundle executable is missing or not executable"
  assert_contains "$output" "Result: failed"
}

expect_running_warning() {
  local name="running-warning"
  local app_path="$TMP_ROOT/$name/Foil.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path"
  make_shims "$shim_dir" 0

  run_check "$app_path" "$shim_dir" "$output" RUNNING_APP_ARGS="$app_path/Contents/MacOS/Foil"
  assert_contains "$output" "warning: Foil is currently running from the installed app"
  assert_contains "$output" "Result: passed with 1 warning(s)."
}

expect_running_wrong_app_warning() {
  local name="running-wrong-app-warning"
  local app_path="$TMP_ROOT/$name/Foil.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path"
  make_shims "$shim_dir" 0

  run_check "$app_path" "$shim_dir" "$output" RUNNING_APP_ARGS="/tmp/DerivedData/Foil.app/Contents/MacOS/Foil"
  assert_contains "$output" "warning: Foil is running from a different path than the installed app"
  assert_contains "$output" "Result: passed with 1 warning(s)."
}

expect_guide_installed_opens_panes_and_launches() {
  local name="guide-installed"
  local app_path="$TMP_ROOT/$name/Foil.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  local open_log="$TMP_ROOT/$name/open.log"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path"
  make_shims "$shim_dir" 1

  cat >"$shim_dir/open" <<SH
#!/bin/bash
echo "\$*" >>"$open_log"
SH
  chmod +x "$shim_dir/open"

  cat >"$shim_dir/sleep" <<'SH'
#!/bin/bash
exit 0
SH
  chmod +x "$shim_dir/sleep"

  run_guide "$app_path" "$shim_dir" "$output"
  assert_contains "$output" "Installed-app permissions QA guide"
  assert_contains "$output" "Release-smoke checklist"
  assert_contains "$output" "Result: guide opened"
  assert_contains "$open_log" "$app_path"
  assert_contains "$open_log" "Privacy_Accessibility"
  assert_contains "$open_log" "Privacy_ListenEvent"
  assert_contains "$open_log" "Privacy_Microphone"
  assert_not_contains "$output" "forbidden command called"
}

expect_guide_installed_rejects_wrong_running_app() {
  local name="guide-installed-wrong-app"
  local app_path="$TMP_ROOT/$name/Foil.app"
  local shim_dir="$TMP_ROOT/$name/shims"
  local output="$TMP_ROOT/$name/output.txt"
  mkdir -p "$TMP_ROOT/$name"
  make_fixture_app "$app_path"
  make_shims "$shim_dir" 0

  cat >"$shim_dir/open" <<'SH'
#!/bin/bash
exit 0
SH
  chmod +x "$shim_dir/open"

  cat >"$shim_dir/sleep" <<'SH'
#!/bin/bash
exit 0
SH
  chmod +x "$shim_dir/sleep"

  if run_guide "$app_path" "$shim_dir" "$output" RUNNING_APP_ARGS="/tmp/DerivedData/Foil.app/Contents/MacOS/Foil"; then
    fail "guide-installed unexpectedly succeeded with a wrong running app"
  fi
  assert_contains "$output" "running from a different path"
  assert_contains "$output" "Result: failed"
  assert_not_contains "$output" "Release-smoke checklist"
}

expect_success "success"
expect_identifier_mismatch_failure
expect_missing_microphone_failure
expect_missing_executable_failure
expect_running_warning
expect_running_wrong_app_warning
expect_guide_installed_opens_panes_and_launches
expect_guide_installed_rejects_wrong_running_app

echo "prepare-local-permissions-qa shell tests passed."

#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/run-installed-live-microphone-qa.sh"
TMP_ROOT="$(mktemp -d)"

trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    echo "---- output: $file ----" >&2
    if [[ -f "$file" ]]; then
      cat "$file" >&2
    else
      echo "<missing>" >&2
    fi
    echo "------------------------" >&2
    fail "expected output to contain: $expected"
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if [[ -f "$file" ]] && grep -Fq -- "$unexpected" "$file"; then
    echo "---- output: $file ----" >&2
    cat "$file" >&2
    echo "------------------------" >&2
    fail "expected output not to contain: $unexpected"
  fi
}

write_info_plist() {
  local app_path="$1"
  mkdir -p "$app_path/Contents/MacOS"
  cat >"$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.neonwatty.Foil</string>
  <key>CFBundleShortVersionString</key>
  <string>1.13.14</string>
  <key>CFBundleVersion</key>
  <string>28885978664</string>
</dict>
</plist>
PLIST
  : >"$app_path/Contents/MacOS/Foil"
  chmod +x "$app_path/Contents/MacOS/Foil"
}

write_ssh_shim() {
  local shim_path="$1"
  local ssh_log="$2"
  cat >"$shim_path" <<SH
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >>"$ssh_log"
cmd="\${@: -1}"
/bin/bash -c "\$cmd"
SH
  chmod +x "$shim_path"
}

write_open_shim() {
  local shim_path="$1"
  local open_log="$2"
  cat >"$shim_path" <<SH
#!/bin/bash
set -euo pipefail

if [[ "\${1:-}" == "-h" ]]; then
  echo "Usage: open ... --env VAR ... --args arguments"
  exit 1
fi

printf '%s\n' "\$*" >>"$open_log"

result_path=""
input_route=""
stdout_path=""
stderr_path=""
while [[ "\$#" -gt 0 ]]; do
  case "\$1" in
    --env)
      case "\${2:-}" in
        LIVE_MICROPHONE_RESULT_PATH=*) result_path="\${2#LIVE_MICROPHONE_RESULT_PATH=}" ;;
        LIVE_MICROPHONE_INPUT_ROUTE=*) input_route="\${2#LIVE_MICROPHONE_INPUT_ROUTE=}" ;;
      esac
      shift 2
      ;;
    -o|--stdout)
      stdout_path="\${2:-}"
      shift 2
      ;;
    --stderr)
      stderr_path="\${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "\$stdout_path" ]] && : >"\$stdout_path"
[[ -n "\$stderr_path" ]] && : >"\$stderr_path"
if [[ -z "\$result_path" ]]; then
  echo "missing LIVE_MICROPHONE_RESULT_PATH" >&2
  exit 4
fi

bytes=141696
level_peak=1.0000
file_level_peak=1.0000
case "\${OPEN_RESULT_MODE:-pass}" in
  zero-bytes) bytes=0 ;;
  silent) level_peak=0.0000; file_level_peak=0.0000 ;;
  fail-status)
    {
      echo "status=fail"
      echo "microphone_permission_status=authorized"
      echo "input_route_request=\$input_route"
      echo "bytes=0"
      echo "level_peak=0.0000"
      echo "file_level_peak=0.0000"
    } >"\$result_path"
    exit 0
    ;;
esac

{
  echo "status=pass"
  echo "app_path=\${APP_PATH:-}"
  echo "signing_identity=Developer ID Application: Mean Weasel LLC (B3A6AN2HA4)"
  echo "microphone_permission_status=authorized"
  echo "recording_started=true"
  echo "recording_stopped=true"
  echo "input_route_request=\$input_route"
  echo "available_input_devices=USB PnP Sound Device(uid=test, id=80, transport=USB)"
  echo "apple_voice_playback=enabled"
  echo "apple_voice_process_started=true"
  echo "apple_voice_exit_status=0"
  echo "level_sample_count=43"
  echo "level_peak=\$level_peak"
  echo "file_level_peak=\$file_level_peak"
  echo "bytes=\$bytes"
} >"\$result_path"
SH
  chmod +x "$shim_path"
}

write_codesign_shim() {
  local shim_path="$1"
  cat >"$shim_path" <<'SH'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "--verify" ]]; then
  exit 0
fi
cat >&2 <<'OUT'
Executable=/Applications/Foil.app/Contents/MacOS/Foil
Identifier=com.neonwatty.Foil
Authority=Developer ID Application: Mean Weasel LLC (B3A6AN2HA4)
TeamIdentifier=B3A6AN2HA4
OUT
SH
  chmod +x "$shim_path"
}

write_spctl_shim() {
  local shim_path="$1"
  cat >"$shim_path" <<'SH'
#!/bin/bash
set -euo pipefail
echo "${*: -1}: accepted"
echo "source=Notarized Developer ID"
echo "origin=Developer ID Application: Mean Weasel LLC (B3A6AN2HA4)"
SH
  chmod +x "$shim_path"
}

write_noop_shim() {
  local shim_path="$1"
  cat >"$shim_path" <<'SH'
#!/bin/bash
exit 0
SH
  chmod +x "$shim_path"
}

expect_opt_in_skip() {
  local name="opt-in-skip"
  local dir="$TMP_ROOT/$name"
  local output="$dir/output.txt"
  mkdir -p "$dir"

  "$SCRIPT" >"$output" 2>&1

  assert_contains "$output" "skip: set RUN_INSTALLED_LIVE_MICROPHONE_TESTS=1"
}

expect_success_uses_launchservices_and_system_default() {
  local name="success"
  local dir="$TMP_ROOT/$name"
  local output="$dir/output.txt"
  local ssh_log="$dir/ssh.log"
  local open_log="$dir/open.log"
  local app_path="$dir/Foil.app"
  local evidence_dir="$dir/evidence"
  mkdir -p "$dir/bin"
  write_info_plist "$app_path"
  write_ssh_shim "$dir/bin/ssh" "$ssh_log"
  write_open_shim "$dir/bin/open" "$open_log"
  write_codesign_shim "$dir/bin/codesign"
  write_spctl_shim "$dir/bin/spctl"
  write_noop_shim "$dir/bin/pkill"

  RUN_INSTALLED_LIVE_MICROPHONE_TESTS=1 \
    SSH="$dir/bin/ssh" \
    HOST=mm2 \
    APP_PATH="$app_path" \
    EVIDENCE_DIR="$evidence_dir" \
    LIVE_MICROPHONE_DURATION_SECONDS=1 \
    REMOTE_OPEN="$dir/bin/open" \
    REMOTE_CODESIGN="$dir/bin/codesign" \
    REMOTE_SPCTL="$dir/bin/spctl" \
    REMOTE_PKILL="$dir/bin/pkill" \
    "$SCRIPT" >"$output" 2>&1

  assert_contains "$output" "Installed live microphone QA passed."
  assert_contains "$output" "evidence_dir=$evidence_dir"
  assert_contains "$ssh_log" "AddressFamily=inet6"
  assert_contains "$ssh_log" "mm2"
  assert_contains "$open_log" "-a $app_path"
  assert_contains "$open_log" "--env LIVE_MICROPHONE_INPUT_ROUTE=system-default"
  assert_contains "$open_log" "--env FOIL_ENABLE_RELEASE_LIVE_MICROPHONE_SMOKE=1"
  assert_contains "$open_log" "--args --ui-testing --reset-defaults --seed-setup-ready --live-microphone-smoke"
  assert_contains "$evidence_dir/live-microphone-result.txt" "status=pass"
  assert_contains "$evidence_dir/live-microphone-result.txt" "input_route_request=system-default"
  assert_contains "$evidence_dir/summary.txt" "bundle_id=com.neonwatty.Foil"
  assert_contains "$evidence_dir/summary.txt" "gatekeeper_status=accepted"
  assert_contains "$evidence_dir/manifest.txt" "host=mm2"
}

expect_zero_bytes_fails() {
  local name="zero-bytes"
  local dir="$TMP_ROOT/$name"
  local output="$dir/output.txt"
  local app_path="$dir/Foil.app"
  mkdir -p "$dir/bin"
  write_info_plist "$app_path"
  write_ssh_shim "$dir/bin/ssh" "$dir/ssh.log"
  write_open_shim "$dir/bin/open" "$dir/open.log"
  write_codesign_shim "$dir/bin/codesign"
  write_spctl_shim "$dir/bin/spctl"
  write_noop_shim "$dir/bin/pkill"

  if RUN_INSTALLED_LIVE_MICROPHONE_TESTS=1 \
    OPEN_RESULT_MODE=zero-bytes \
    SSH="$dir/bin/ssh" \
    HOST=mm2 \
    APP_PATH="$app_path" \
    EVIDENCE_DIR="$dir/evidence" \
    LIVE_MICROPHONE_DURATION_SECONDS=1 \
    REMOTE_OPEN="$dir/bin/open" \
    REMOTE_CODESIGN="$dir/bin/codesign" \
    REMOTE_SPCTL="$dir/bin/spctl" \
    REMOTE_PKILL="$dir/bin/pkill" \
    "$SCRIPT" >"$output" 2>&1; then
    fail "zero-byte installed live microphone QA unexpectedly succeeded"
  fi

  assert_contains "$output" "bytes must be positive"
  assert_contains "$dir/evidence/live-microphone-result.txt" "status=pass"
  assert_contains "$dir/evidence/live-microphone-result.txt" "bytes=0"
}

expect_silent_capture_fails() {
  local name="silent"
  local dir="$TMP_ROOT/$name"
  local output="$dir/output.txt"
  local app_path="$dir/Foil.app"
  mkdir -p "$dir/bin"
  write_info_plist "$app_path"
  write_ssh_shim "$dir/bin/ssh" "$dir/ssh.log"
  write_open_shim "$dir/bin/open" "$dir/open.log"
  write_codesign_shim "$dir/bin/codesign"
  write_spctl_shim "$dir/bin/spctl"
  write_noop_shim "$dir/bin/pkill"

  if RUN_INSTALLED_LIVE_MICROPHONE_TESTS=1 \
    OPEN_RESULT_MODE=silent \
    SSH="$dir/bin/ssh" \
    HOST=mm2 \
    APP_PATH="$app_path" \
    EVIDENCE_DIR="$dir/evidence" \
    LIVE_MICROPHONE_DURATION_SECONDS=1 \
    REMOTE_OPEN="$dir/bin/open" \
    REMOTE_CODESIGN="$dir/bin/codesign" \
    REMOTE_SPCTL="$dir/bin/spctl" \
    REMOTE_PKILL="$dir/bin/pkill" \
    "$SCRIPT" >"$output" 2>&1; then
    fail "silent installed live microphone QA unexpectedly succeeded"
  fi

  assert_contains "$output" "level_peak or file_level_peak must be positive"
  assert_contains "$dir/evidence/live-microphone-result.txt" "level_peak=0.0000"
  assert_contains "$dir/evidence/live-microphone-result.txt" "file_level_peak=0.0000"
}

expect_opt_in_skip
expect_success_uses_launchservices_and_system_default
expect_zero_bytes_fails
expect_silent_capture_fails

echo "run-installed-live-microphone-qa shell tests passed."

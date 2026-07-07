#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/run-live-microphone-qa.sh"
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

write_xcodebuild_shim() {
  local shim_path="$1"
  local raw_exec_log="$2"
  cat >"$shim_path" <<SH
#!/bin/bash
set -euo pipefail

command="\${1:-}"
shift || true

derived_data=""
while [[ "\$#" -gt 0 ]]; do
  case "\$1" in
    -derivedDataPath)
      derived_data="\${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

case "\$command" in
  build-for-testing)
    if [[ -z "\$derived_data" ]]; then
      echo "missing -derivedDataPath" >&2
      exit 2
    fi
    app_path="\$derived_data/Build/Products/Debug/Foil.app"
    mkdir -p "\$app_path/Contents/MacOS" "\$derived_data/Build/Products"
    cat >"\$app_path/Contents/MacOS/Foil" <<'APP'
#!/bin/bash
set -euo pipefail
printf 'raw-executable-used\n' >>"__RAW_EXEC_LOG__"
if [[ -n "\${LIVE_MICROPHONE_RESULT_PATH:-}" ]]; then
  {
    echo "status=pass"
    echo "input_route_request=\${LIVE_MICROPHONE_INPUT_ROUTE:-}"
    echo "bytes=1"
  } >"\$LIVE_MICROPHONE_RESULT_PATH"
fi
APP
    perl -0pi -e 's#__RAW_EXEC_LOG__#'"$raw_exec_log"'#g' "\$app_path/Contents/MacOS/Foil"
    chmod +x "\$app_path/Contents/MacOS/Foil"
    cat >"\$derived_data/Build/Products/Foil-live-microphone.xctestrun" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>TestConfigurations</key>
  <array>
    <dict>
      <key>TestTargets</key>
      <array>
        <dict>
          <key>BlueprintName</key>
          <string>FoilUITests</string>
          <key>EnvironmentVariables</key>
          <dict/>
          <key>TestHostPath</key>
          <string>\$app_path</string>
        </dict>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST
    ;;
  test-without-building)
    exit 65
    ;;
  *)
    echo "unexpected xcodebuild command: \$command" >&2
    exit 3
    ;;
esac
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
  exit 0
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
{
  echo "status=pass"
  echo "input_route_request=\$input_route"
  echo "apple_voice_process_started=true"
  echo "bytes=1"
} >"\$result_path"
SH
  chmod +x "$shim_path"
}

expect_launchservices_fallback_uses_system_default() {
  local name="launchservices-fallback-system-default"
  local dir="$TMP_ROOT/$name"
  local output="$dir/output.txt"
  local open_log="$dir/open.log"
  local raw_exec_log="$dir/raw-executable.log"
  mkdir -p "$dir/bin"

  write_xcodebuild_shim "$dir/bin/xcodebuild" "$raw_exec_log"
  write_open_shim "$dir/bin/open" "$open_log"

  RUN_LIVE_MICROPHONE_TESTS=1 \
    PATH="$dir/bin:$PATH" \
    OPEN="$dir/bin/open" \
    DERIVED_DATA_PATH="$dir/derived-data" \
    LIVE_MICROPHONE_RESULT_PATH="$dir/live-microphone-result.txt" \
    LIVE_MICROPHONE_SCREENSHOT_DIR="$dir/screenshots" \
    LIVE_MICROPHONE_ARTIFACT_DIR="$dir/artifacts" \
    "$SCRIPT" >"$output" 2>&1

  assert_contains "$output" "By default this smoke records from the system default input route."
  assert_not_contains "$output" "forces Foil to record from a built-in input route"
  assert_contains "$output" "Attempting direct app-hook fallback via LaunchServices open --env"
  assert_contains "$open_log" "--env LIVE_MICROPHONE_INPUT_ROUTE=system-default"
  assert_contains "$dir/live-microphone-result.txt" "status=pass"
  assert_contains "$dir/live-microphone-result.txt" "input_route_request=system-default"
  if [[ -s "$raw_exec_log" ]]; then
    fail "raw executable fallback was used instead of LaunchServices open --env"
  fi
}

expect_launchservices_fallback_uses_system_default

echo "run-live-microphone-qa shell tests passed."

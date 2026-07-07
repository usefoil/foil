#!/usr/bin/env bash
set -euo pipefail

if [[ "${RUN_LIVE_MICROPHONE_TESTS:-}" != "1" ]]; then
  echo "skip: set RUN_LIVE_MICROPHONE_TESTS=1 to run live microphone QA"
  exit 0
fi

SCHEME="${SCHEME:-Foil}"
CONFIG="${CONFIG:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/foil-live-microphone-derived-data}"
LIVE_MICROPHONE_RESULT_PATH="${LIVE_MICROPHONE_RESULT_PATH:-/tmp/foil-live-microphone-result.txt}"
LIVE_MICROPHONE_DURATION_SECONDS="${LIVE_MICROPHONE_DURATION_SECONDS:-8}"
LIVE_MICROPHONE_INPUT_ROUTE="${LIVE_MICROPHONE_INPUT_ROUTE:-built-in}"
LIVE_MICROPHONE_APPLE_VOICE_TEXT="${LIVE_MICROPHONE_APPLE_VOICE_TEXT:-Foil microphone test.}"
LIVE_MICROPHONE_SCREENSHOT_DIR="${LIVE_MICROPHONE_SCREENSHOT_DIR:-/tmp/foil-live-microphone-screenshots}"
LIVE_MICROPHONE_XCTRUNNER_SCREENSHOT_DIR="${LIVE_MICROPHONE_XCTRUNNER_SCREENSHOT_DIR:-${HOME}/Library/Containers/com.neonwatty.FoilUITests.xctrunner/Data/tmp/foil-live-microphone-screenshots}"
LIVE_MICROPHONE_DIRECT_LOG_PATH="${LIVE_MICROPHONE_DIRECT_LOG_PATH:-/tmp/foil-live-microphone-direct.log}"
LIVE_MICROPHONE_ARTIFACT_DIR="${LIVE_MICROPHONE_ARTIFACT_DIR:-/tmp/foil-live-microphone-artifacts}"
PLISTBUDDY="/usr/libexec/PlistBuddy"
patched=""

cleanup() {
  if [[ -n "${patched}" ]]; then
    rm -f "${patched}"
  fi
}

copy_file_if_present() {
  local source="$1"
  local destination="$2"

  if [[ -f "${source}" ]]; then
    mkdir -p "$(dirname "${destination}")"
    cp "${source}" "${destination}"
  fi
}

copy_screenshots_if_present() {
  local source_dir="$1"
  local destination_dir="$2"

  if [[ -d "${source_dir}" ]]; then
    mkdir -p "${destination_dir}"
    find "${source_dir}" -maxdepth 1 -type f -name '*.png' -print0 \
      | xargs -0 -I {} cp {} "${destination_dir}/" 2>/dev/null || true
  fi
}

capture_direct_screenshot() {
  local output_path="$1"

  if ! screencapture -x "${output_path}" >/dev/null 2>&1; then
    echo "screencapture failed for ${output_path}" >> "${LIVE_MICROPHONE_DIRECT_LOG_PATH}"
  fi
}

collect_artifacts() {
  local status="$1"

  set +e
  rm -rf "${LIVE_MICROPHONE_ARTIFACT_DIR}"
  mkdir -p "${LIVE_MICROPHONE_ARTIFACT_DIR}"

  {
    echo "exit_status=${status}"
    echo "result_path=${LIVE_MICROPHONE_RESULT_PATH}"
    echo "screenshot_dir=${LIVE_MICROPHONE_SCREENSHOT_DIR}"
    echo "xctrunner_screenshot_dir=${LIVE_MICROPHONE_XCTRUNNER_SCREENSHOT_DIR}"
    echo "direct_log_path=${LIVE_MICROPHONE_DIRECT_LOG_PATH}"
    echo "input_route=${LIVE_MICROPHONE_INPUT_ROUTE}"
    echo "duration_seconds=${LIVE_MICROPHONE_DURATION_SECONDS}"
    echo "artifact_dir=${LIVE_MICROPHONE_ARTIFACT_DIR}"
    date -u '+generated_at=%Y-%m-%dT%H:%M:%SZ'
  } > "${LIVE_MICROPHONE_ARTIFACT_DIR}/manifest.txt"

  copy_file_if_present "${LIVE_MICROPHONE_RESULT_PATH}" "${LIVE_MICROPHONE_ARTIFACT_DIR}/live-microphone-result.txt"
  copy_file_if_present "${LIVE_MICROPHONE_DIRECT_LOG_PATH}" "${LIVE_MICROPHONE_ARTIFACT_DIR}/direct-fallback.log"
  copy_screenshots_if_present "${LIVE_MICROPHONE_SCREENSHOT_DIR}" "${LIVE_MICROPHONE_ARTIFACT_DIR}/screenshots/requested"
  if [[ "${LIVE_MICROPHONE_XCTRUNNER_SCREENSHOT_DIR}" != "${LIVE_MICROPHONE_SCREENSHOT_DIR}" ]]; then
    copy_screenshots_if_present "${LIVE_MICROPHONE_XCTRUNNER_SCREENSHOT_DIR}" "${LIVE_MICROPHONE_ARTIFACT_DIR}/screenshots/xctrunner"
  fi

  if [[ -f "${LIVE_MICROPHONE_RESULT_PATH}" ]]; then
    captured_audio_path="$(sed -n 's/^captured_audio_path=//p' "${LIVE_MICROPHONE_RESULT_PATH}" | head -1)"
    if [[ -n "${captured_audio_path}" && -f "${captured_audio_path}" ]]; then
      copy_file_if_present "${captured_audio_path}" "${LIVE_MICROPHONE_ARTIFACT_DIR}/captured-audio/$(basename "${captured_audio_path}")"
    fi
  fi

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "## Live Microphone QA"
      echo
      echo "- Artifact directory: \`${LIVE_MICROPHONE_ARTIFACT_DIR}\`"
      echo "- Exit status: \`${status}\`"
      echo
      if [[ -f "${LIVE_MICROPHONE_ARTIFACT_DIR}/live-microphone-result.txt" ]]; then
        echo "### Receipt"
        echo
        echo '```text'
        cat "${LIVE_MICROPHONE_ARTIFACT_DIR}/live-microphone-result.txt"
        echo '```'
      else
        echo "_No live microphone result receipt was generated._"
      fi
      echo
      echo "### Files"
      echo
      find "${LIVE_MICROPHONE_ARTIFACT_DIR}" -type f | sort | sed "s#^${LIVE_MICROPHONE_ARTIFACT_DIR}/#- #"
    } >> "${GITHUB_STEP_SUMMARY}"
  fi

  echo "artifacts=${LIVE_MICROPHONE_ARTIFACT_DIR}"
  set -e
}

on_exit() {
  local status="$?"
  collect_artifacts "${status}"
  cleanup
  exit "${status}"
}
trap on_exit EXIT

print_screenshots_status() {
  local paths=()
  if find "${LIVE_MICROPHONE_SCREENSHOT_DIR}" -maxdepth 1 -type f -name '*.png' 2>/dev/null | grep -q .; then
    paths+=( "${LIVE_MICROPHONE_SCREENSHOT_DIR}" )
  fi
  if [[ "${LIVE_MICROPHONE_XCTRUNNER_SCREENSHOT_DIR}" != "${LIVE_MICROPHONE_SCREENSHOT_DIR}" ]] \
    && find "${LIVE_MICROPHONE_XCTRUNNER_SCREENSHOT_DIR}" -maxdepth 1 -type f -name '*.png' 2>/dev/null | grep -q .; then
    paths+=( "${LIVE_MICROPHONE_XCTRUNNER_SCREENSHOT_DIR}" )
  fi

  if [[ "${#paths[@]}" -gt 0 ]]; then
    local joined="${paths[0]}"
    for path in "${paths[@]:1}"; do
      joined="${joined};${path}"
    done
    echo "screenshots=${joined}"
  else
    echo "screenshots=none"
  fi
}

echo "Live microphone QA prerequisites:"
echo "- A working input device is selected in macOS Sound settings."
echo "- By default this smoke forces Foil to record from a built-in input route."
echo "- By default this smoke plays Apple-generated speech with /usr/bin/say."
echo "- The Xcode-built Foil test app can be granted Microphone permission when prompted."
echo "- This target is local-only; regular CI should use make test-ui."
echo ""
echo "If permission state is stale, run:"
echo "  tccutil reset Microphone com.neonwatty.Foil"
echo ""

build_args=(
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}"
)

echo "== Build for testing"
xcodebuild build-for-testing "${build_args[@]}"

find_root="${DERIVED_DATA_PATH}"
xctestrun="$(find "${find_root}" -name '*.xctestrun' -path '*Foil*' -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 || true)"
if [[ -z "${xctestrun}" || ! -f "${xctestrun}" ]]; then
  echo "error: could not locate generated .xctestrun" >&2
  exit 1
fi

patched="${xctestrun%.xctestrun}.live-microphone-qa.xctestrun"
cp "${xctestrun}" "${patched}"

ui_target_index=""
for index in $(seq 0 20); do
  blueprint="$("${PLISTBUDDY}" -c "Print :TestConfigurations:0:TestTargets:${index}:BlueprintName" "${patched}" 2>/dev/null || true)"
  if [[ "${blueprint}" == "FoilUITests" ]]; then
    ui_target_index="${index}"
    break
  fi
  if [[ -z "${blueprint}" ]]; then
    break
  fi
done

if [[ -z "${ui_target_index}" ]]; then
  echo "error: FoilUITests target not found in ${patched}" >&2
  exit 1
fi

env_root=":TestConfigurations:0:TestTargets:${ui_target_index}:EnvironmentVariables"
for key in RUN_LIVE_MICROPHONE_TESTS FOIL_ENABLE_RELEASE_LIVE_MICROPHONE_SMOKE LIVE_MICROPHONE_RESULT_PATH LIVE_MICROPHONE_DURATION_SECONDS LIVE_MICROPHONE_INPUT_ROUTE LIVE_MICROPHONE_APPLE_VOICE_TEXT LIVE_MICROPHONE_SCREENSHOT_DIR; do
  "${PLISTBUDDY}" -c "Delete ${env_root}:${key}" "${patched}" >/dev/null 2>&1 || true
done

test_host="$("${PLISTBUDDY}" -c "Print :TestConfigurations:0:TestTargets:${ui_target_index}:TestHostPath" "${patched}" 2>/dev/null || true)"
if [[ -z "${test_host}" || ! -e "${test_host}" ]]; then
  test_host="$(find "${find_root}" -path '*Build/Products/Debug/Foil.app' -type d -print0 2>/dev/null | xargs -0 ls -dt 2>/dev/null | head -1 || true)"
fi
signing_identity="unknown"
if [[ -n "${test_host}" && -e "${test_host}" ]]; then
  echo "app_path=${test_host}"
  signing_identity="$(codesign -dv "${test_host}" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true)"
  if [[ -z "${signing_identity}" ]]; then
    signing_identity="$(codesign -dv "${test_host}" 2>&1 | sed -n 's/^Signature=//p' | head -1 || true)"
  fi
  signing_identity="${signing_identity:-Sign to Run Locally (ad-hoc)}"
  echo "signing_identity=${signing_identity}"
else
  echo "app_path=unknown"
  signing_identity="Sign to Run Locally (ad-hoc)"
  echo "signing_identity=${signing_identity}"
fi

for key in LIVE_MICROPHONE_SIGNING_IDENTITY; do
  "${PLISTBUDDY}" -c "Delete ${env_root}:${key}" "${patched}" >/dev/null 2>&1 || true
done
"${PLISTBUDDY}" -c "Add ${env_root}:RUN_LIVE_MICROPHONE_TESTS string 1" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:FOIL_ENABLE_RELEASE_LIVE_MICROPHONE_SMOKE string 1" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:LIVE_MICROPHONE_RESULT_PATH string ${LIVE_MICROPHONE_RESULT_PATH}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:LIVE_MICROPHONE_DURATION_SECONDS string ${LIVE_MICROPHONE_DURATION_SECONDS}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:LIVE_MICROPHONE_INPUT_ROUTE string ${LIVE_MICROPHONE_INPUT_ROUTE}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:LIVE_MICROPHONE_SIGNING_IDENTITY string ${signing_identity}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:LIVE_MICROPHONE_APPLE_VOICE_TEXT string ${LIVE_MICROPHONE_APPLE_VOICE_TEXT}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:LIVE_MICROPHONE_SCREENSHOT_DIR string ${LIVE_MICROPHONE_SCREENSHOT_DIR}" "${patched}"
rm -f "${LIVE_MICROPHONE_RESULT_PATH}"
mkdir -p "${LIVE_MICROPHONE_SCREENSHOT_DIR}"

echo "== XCUITest live microphone QA"
set +e
xcodebuild test-without-building \
  -xctestrun "${patched}" \
  -destination "${DESTINATION}" \
  -only-testing:FoilUITests/FoilUITests/testLiveMicrophoneSmoke
xctest_status=$?
set -e

if [[ "${xctest_status}" -eq 0 ]]; then
  print_screenshots_status
  exit 0
fi

echo "XCUITest live microphone QA failed with status ${xctest_status}."
echo "Attempting direct app-hook fallback so the live recorder still produces a receipt."

if [[ -z "${test_host}" || ! -d "${test_host}" ]]; then
  echo "error: cannot run direct fallback because app_path is unavailable" >&2
  exit "${xctest_status}"
fi

executable="${test_host}/Contents/MacOS/Foil"
if [[ ! -x "${executable}" ]]; then
  echo "error: direct fallback executable missing: ${executable}" >&2
  exit "${xctest_status}"
fi

rm -f "${LIVE_MICROPHONE_RESULT_PATH}" "${LIVE_MICROPHONE_DIRECT_LOG_PATH}"
pkill -x Foil >/dev/null 2>&1 || true

LIVE_MICROPHONE_RESULT_PATH="${LIVE_MICROPHONE_RESULT_PATH}" \
FOIL_ENABLE_RELEASE_LIVE_MICROPHONE_SMOKE=1 \
LIVE_MICROPHONE_DURATION_SECONDS="${LIVE_MICROPHONE_DURATION_SECONDS}" \
LIVE_MICROPHONE_INPUT_ROUTE="${LIVE_MICROPHONE_INPUT_ROUTE}" \
LIVE_MICROPHONE_APPLE_VOICE_TEXT="${LIVE_MICROPHONE_APPLE_VOICE_TEXT}" \
LIVE_MICROPHONE_SIGNING_IDENTITY="${signing_identity}" \
"${executable}" --ui-testing --reset-defaults --seed-setup-ready --live-microphone-smoke \
  >"${LIVE_MICROPHONE_DIRECT_LOG_PATH}" 2>&1 &
direct_pid=$!

( sleep 1.5; capture_direct_screenshot "${LIVE_MICROPHONE_SCREENSHOT_DIR}/direct-recording-ui.png" ) &
direct_recording_capture_pid=$!

direct_recording_screenshot_taken=0
direct_final_screenshot_taken=0
direct_poll_count=0
for _ in $(seq 1 120); do
  direct_poll_count=$((direct_poll_count + 1))
  result_contents=""
  if [[ -f "${LIVE_MICROPHONE_RESULT_PATH}" ]]; then
    result_contents="$(cat "${LIVE_MICROPHONE_RESULT_PATH}")"
  fi

  if [[ "${direct_recording_screenshot_taken}" == "0" && "${result_contents}" == *"status=recording"* ]]; then
    capture_direct_screenshot "${LIVE_MICROPHONE_SCREENSHOT_DIR}/direct-recording-ui.png"
    direct_recording_screenshot_taken=1
  fi
  if [[ "${direct_recording_screenshot_taken}" == "0" && "${direct_poll_count}" -eq 6 ]]; then
    capture_direct_screenshot "${LIVE_MICROPHONE_SCREENSHOT_DIR}/direct-recording-ui.png"
    direct_recording_screenshot_taken=1
  fi

  if [[ "${result_contents}" == *"status=pass"* || "${result_contents}" == *"status=fail"* ]]; then
    if [[ "${direct_final_screenshot_taken}" == "0" ]]; then
      capture_direct_screenshot "${LIVE_MICROPHONE_SCREENSHOT_DIR}/direct-ui.png"
      direct_final_screenshot_taken=1
    fi
    break
  fi
  sleep 0.25
done

if [[ "${direct_final_screenshot_taken}" == "0" ]]; then
  capture_direct_screenshot "${LIVE_MICROPHONE_SCREENSHOT_DIR}/direct-ui.png"
fi
pkill -x Foil >/dev/null 2>&1 || true
wait "${direct_recording_capture_pid}" 2>/dev/null || true
wait "${direct_pid}" 2>/dev/null || true

if [[ ! -f "${LIVE_MICROPHONE_RESULT_PATH}" ]]; then
  echo "error: direct fallback produced no result file" >&2
  echo "direct_log=${LIVE_MICROPHONE_DIRECT_LOG_PATH}" >&2
  exit "${xctest_status}"
fi

cat "${LIVE_MICROPHONE_RESULT_PATH}"
echo "direct_log=${LIVE_MICROPHONE_DIRECT_LOG_PATH}"
print_screenshots_status

if grep -q '^status=pass$' "${LIVE_MICROPHONE_RESULT_PATH}"; then
  exit 0
fi
exit 1

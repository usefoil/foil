#!/usr/bin/env bash
set -euo pipefail

SCHEME="${SCHEME:-Foil}"
CONFIG="${CONFIG:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-}"
MODEL="${E2E_TRANSCRIPTION_MODEL:-whisper-1}"
PLISTBUDDY="/usr/libexec/PlistBuddy"

api_key="${OPENAI_API_KEY:-${E2E_API_KEY:-}}"

if [[ -z "${api_key}" ]]; then
  echo "skip: OPENAI_API_KEY or E2E_API_KEY not found in environment"
  exit 0
fi

echo "== OpenAI credential preflight"
preflight_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  https://api.openai.com/v1/models \
  -H "Authorization: Bearer ${api_key}")"
if [[ "${preflight_status}" == "401" || "${preflight_status}" == "403" ]]; then
  echo "error: OpenAI API key is present but was rejected with HTTP ${preflight_status}" >&2
  exit 2
fi
if [[ "${preflight_status}" != "200" ]]; then
  echo "error: OpenAI credential preflight returned HTTP ${preflight_status}" >&2
  exit 2
fi

patched=""
cleanup() {
  if [[ -n "${patched}" ]]; then
    rm -f "${patched}"
  fi
}
trap cleanup EXIT

echo "== Build for testing"
build_args=(
  -scheme "${SCHEME}"
  -configuration "${CONFIG}"
  -destination "${DESTINATION}"
)
if [[ -n "${DERIVED_DATA_PATH}" ]]; then
  build_args+=( -derivedDataPath "${DERIVED_DATA_PATH}" )
fi
xcodebuild build-for-testing "${build_args[@]}"

find_root="${DERIVED_DATA_PATH:-${HOME}/Library/Developer/Xcode/DerivedData}"
xctestrun="$(find "${find_root}" -name '*.xctestrun' -path '*Foil*' -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 || true)"
if [[ -z "${xctestrun}" || ! -f "${xctestrun}" ]]; then
  echo "error: could not locate generated .xctestrun" >&2
  exit 1
fi

patched="${xctestrun%.xctestrun}.live-openai-provider-qa.xctestrun"
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
for key in \
  E2E_TRANSCRIPTION_PROVIDER \
  E2E_TRANSCRIPTION_MODEL \
  E2E_API_KEY \
  E2E_TRANSCRIPTION_TIMEOUT_SECONDS; do
  "${PLISTBUDDY}" -c "Delete ${env_root}:${key}" "${patched}" >/dev/null 2>&1 || true
done
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_PROVIDER string openai" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_MODEL string ${MODEL}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_API_KEY string ${api_key}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_TIMEOUT_SECONDS string ${E2E_TRANSCRIPTION_TIMEOUT_SECONDS:-90}" "${patched}"

echo "== XCUITest live OpenAI provider QA"
xcodebuild test-without-building \
  -xctestrun "${patched}" \
  -destination "${DESTINATION}" \
  -only-testing:FoilUITests/FoilUITests/testE2ETranscription

#!/usr/bin/env bash
set -euo pipefail

SCHEME="${SCHEME:-GroqTalk}"
CONFIG="${CONFIG:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-}"
PLISTBUDDY="/usr/libexec/PlistBuddy"

api_key="${GROQ_API_KEY:-}"
if [[ -z "${api_key}" ]]; then
  api_key="$(security find-generic-password -s com.neonwatty.GroqTalk -a groq-api-key -w 2>/dev/null || true)"
fi

if [[ -z "${api_key}" ]]; then
  echo "skip: GROQ_API_KEY not found in environment or keychain"
  exit 0
fi

echo "== Groq credential preflight"
preflight_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  https://api.groq.com/openai/v1/models \
  -H "Authorization: Bearer ${api_key}")"
if [[ "${preflight_status}" == "401" || "${preflight_status}" == "403" ]]; then
  echo "error: Groq API key is present but was rejected with HTTP ${preflight_status}" >&2
  exit 2
fi
if [[ "${preflight_status}" != "200" ]]; then
  echo "error: Groq credential preflight returned HTTP ${preflight_status}" >&2
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
xctestrun="$(find "${find_root}" -name '*.xctestrun' -path '*GroqTalk*' -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 || true)"
if [[ -z "${xctestrun}" || ! -f "${xctestrun}" ]]; then
  echo "error: could not locate generated .xctestrun" >&2
  exit 1
fi

patched="${xctestrun%.xctestrun}.live-groq-provider-qa.xctestrun"
cp "${xctestrun}" "${patched}"

ui_target_index=""
for index in $(seq 0 20); do
  blueprint="$("${PLISTBUDDY}" -c "Print :TestConfigurations:0:TestTargets:${index}:BlueprintName" "${patched}" 2>/dev/null || true)"
  if [[ "${blueprint}" == "GroqTalkUITests" ]]; then
    ui_target_index="${index}"
    break
  fi
  if [[ -z "${blueprint}" ]]; then
    break
  fi
done

if [[ -z "${ui_target_index}" ]]; then
  echo "error: GroqTalkUITests target not found in ${patched}" >&2
  exit 1
fi

env_root=":TestConfigurations:0:TestTargets:${ui_target_index}:EnvironmentVariables"
for key in RUN_LIVE_GROQ_TESTS GROQ_API_KEY E2E_TRANSCRIPTION_TIMEOUT_SECONDS; do
  "${PLISTBUDDY}" -c "Delete ${env_root}:${key}" "${patched}" >/dev/null 2>&1 || true
done
"${PLISTBUDDY}" -c "Add ${env_root}:RUN_LIVE_GROQ_TESTS string 1" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_TIMEOUT_SECONDS string ${E2E_TRANSCRIPTION_TIMEOUT_SECONDS:-90}" "${patched}"
if [[ -n "${GROQ_API_KEY:-}" ]]; then
  "${PLISTBUDDY}" -c "Add ${env_root}:GROQ_API_KEY string ${GROQ_API_KEY}" "${patched}"
fi

echo "== XCUITest live Groq provider QA"
xcodebuild test-without-building \
  -xctestrun "${patched}" \
  -destination "${DESTINATION}" \
  -only-testing:GroqTalkUITests/GroqTalkUITests/testE2ETranscription

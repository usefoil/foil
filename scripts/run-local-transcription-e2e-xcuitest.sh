#!/usr/bin/env bash
set -euo pipefail

SCHEME="${SCHEME:-Foil}"
CONFIG="${CONFIG:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
BASE_URL="${E2E_TRANSCRIPTION_BASE_URL:-http://127.0.0.1:8080/v1}"
MODEL="${E2E_TRANSCRIPTION_MODEL:-whisper-1}"
API_KEY="${E2E_API_KEY:-local}"
PROVIDER="${E2E_TRANSCRIPTION_PROVIDER:-openai-compatible}"
AUDIO_PATH="${E2E_WAV_PATH:-Foil/e2e-test-audio.wav}"
RESULT_PATH="${E2E_RESULT_PATH:-/tmp/foil-e2e-result.txt}"
LATENCY_RUNS="${LOCAL_E2E_LATENCY_RUNS:-1}"
EXPECTED="${E2E_EXPECTED_TRANSCRIPT:-the quick brown fox jumps over the lazy dog}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-}"
PLISTBUDDY="/usr/libexec/PlistBuddy"

if [[ "${PROVIDER}" != "openai-compatible" ]]; then
  echo "error: this harness is for E2E_TRANSCRIPTION_PROVIDER=openai-compatible" >&2
  exit 2
fi

if [[ ! -f "${AUDIO_PATH}" ]]; then
  echo "error: audio fixture not found: ${AUDIO_PATH}" >&2
  exit 2
fi

if ! [[ "${LATENCY_RUNS}" =~ ^[0-9]+$ ]] || [[ "${LATENCY_RUNS}" -lt 1 ]]; then
  echo "error: LOCAL_E2E_LATENCY_RUNS must be a positive integer" >&2
  exit 2
fi

endpoint="${BASE_URL%/}/audio/transcriptions"
tmpdir="$(mktemp -d)"
patched=""
cleanup() {
  rm -rf "${tmpdir}"
  if [[ -n "${patched}" ]]; then
    rm -f "${patched}"
  fi
}
trap cleanup EXIT

transcript_words() {
  tr '[:upper:]' '[:lower:]' | tr -cs '[:alpha:]' '\n' | sed '/^$/d'
}

word_recall() {
  local transcript="$1"
  local expected_words transcript_words_file
  expected_words="${tmpdir}/expected-words"
  transcript_words_file="${tmpdir}/transcript-words"
  printf '%s' "${EXPECTED}" | transcript_words >"${expected_words}"
  printf '%s' "${transcript}" | transcript_words >"${transcript_words_file}"
  awk '
    FNR == NR { transcript[$1]++; next }
    { total++; if (transcript[$1] > 0) { transcript[$1]--; recall++ } }
    END { printf "%d/%d", recall, total }
  ' "${transcript_words_file}" "${expected_words}"
}

assert_min_recall() {
  local transcript="$1"
  local recall total
  IFS=/ read -r recall total <<<"$(word_recall "${transcript}")"
  if [[ "${recall}" -lt 8 ]]; then
    echo "error: transcript matched ${recall}/${total} expected words" >&2
    echo "transcript: ${transcript}" >&2
    echo "expected: ${EXPECTED}" >&2
    exit 1
  fi
}

curl_transcription() {
  curl -sS -w $'\n__HTTP_STATUS__:%{http_code}\n__TOTAL_TIME__:%{time_total}\n' \
    "${endpoint}" \
    -H "Authorization: Bearer ${API_KEY}" \
    -F "file=@${AUDIO_PATH};type=audio/wav" \
    -F "model=${MODEL}" \
    -F "response_format=text"
}

echo "== Endpoint smoke: ${endpoint}"
timings="${tmpdir}/timings"
for run in $(seq 1 "${LATENCY_RUNS}"); do
  response="$(curl_transcription)"
  transcript="$(printf '%s\n' "${response}" | sed '/^__HTTP_STATUS__:/,$d' | tr -d '\r' | sed 's/^ *//; s/ *$//')"
  http_status="$(printf '%s\n' "${response}" | sed -n 's/^__HTTP_STATUS__://p')"
  total_time="$(printf '%s\n' "${response}" | sed -n 's/^__TOTAL_TIME__://p')"

  if [[ "${http_status}" != "200" ]]; then
    echo "error: endpoint returned HTTP ${http_status}" >&2
    echo "${response}" >&2
    exit 1
  fi

  assert_min_recall "${transcript}"
  printf '%s\n' "${total_time}" >>"${timings}"
  printf 'run=%02d status=%s time=%ss recall=%s transcript=%s\n' \
    "${run}" "${http_status}" "${total_time}" "$(word_recall "${transcript}")" "${transcript}"
done

sort -n "${timings}" | awk '
  { a[++n] = $1 }
  END {
    median = (n % 2 == 1) ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2
    p95_index = int(0.95 * n + 0.999999)
    if (p95_index < 1) p95_index = 1
    if (p95_index > n) p95_index = n
    printf "latency median=%.6fs p95=%.6fs runs=%d\n", median, a[p95_index], n
  }
'

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

patched="${xctestrun%.xctestrun}.local-openai.xctestrun"
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
  E2E_TRANSCRIPTION_BASE_URL \
  E2E_TRANSCRIPTION_MODEL \
  E2E_API_KEY \
  E2E_WAV_PATH; do
  "${PLISTBUDDY}" -c "Delete ${env_root}:${key}" "${patched}" >/dev/null 2>&1 || true
done
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_PROVIDER string ${PROVIDER}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_BASE_URL string ${BASE_URL}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_MODEL string ${MODEL}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_API_KEY string ${API_KEY}" "${patched}"
if [[ -n "${E2E_WAV_PATH:-}" ]]; then
  "${PLISTBUDDY}" -c "Add ${env_root}:E2E_WAV_PATH string ${E2E_WAV_PATH}" "${patched}"
fi

echo "== XCUITest local transcription"
rm -f "${RESULT_PATH}"
test_log="${tmpdir}/xcuitest.log"
set +e
xcodebuild test-without-building \
  -xctestrun "${patched}" \
  -destination "${DESTINATION}" \
  -only-testing:FoilUITests/FoilUITests/testE2ETranscription \
  2>&1 | tee "${test_log}"
test_status="${PIPESTATUS[0]}"
set -e

if grep -qi 'Test skipped' "${test_log}"; then
  echo "error: XCUITest skipped; local E2E environment was not applied" >&2
  exit 1
fi

if [[ "${test_status}" -ne 0 ]]; then
  echo "error: XCUITest failed" >&2
  exit "${test_status}"
fi

if ! grep -Eq '\*\* TEST (EXECUTE )?SUCCEEDED \*\*' "${test_log}"; then
  echo "error: XCUITest did not report success" >&2
  exit 1
fi

if [[ ! -s "${RESULT_PATH}" ]]; then
  echo "error: result file missing or empty: ${RESULT_PATH}" >&2
  exit 1
fi

app_transcript="$(tr -d '\r' <"${RESULT_PATH}" | sed 's/^ *//; s/ *$//')"
assert_min_recall "${app_transcript}"
printf 'app_result=%s\n' "${app_transcript}"
printf 'app_recall=%s\n' "$(word_recall "${app_transcript}")"

#!/usr/bin/env bash
set -euo pipefail

SCHEME="${SCHEME:-Foil}"
CONFIG="${CONFIG:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
MODEL="${E2E_TRANSCRIPTION_MODEL:-whisper-1}"
API_KEY="${E2E_API_KEY:-local-fixture}"
AUDIO_PATH="${E2E_WAV_PATH:-Foil/e2e-test-audio.wav}"
DEFAULT_RESULT_PATH="/tmp/foil-fixture-e2e-result.txt"
RESULT_PATH="${E2E_RESULT_PATH:-${DEFAULT_RESULT_PATH}}"
EXPECTED="${E2E_EXPECTED_TRANSCRIPT:-the quick brown fox jumps over the lazy dog}"
TIMEOUT_SECONDS="${E2E_TRANSCRIPTION_TIMEOUT_SECONDS:-30}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-}"
PLISTBUDDY="/usr/libexec/PlistBuddy"

if [[ ! -f "${AUDIO_PATH}" ]]; then
  echo "error: audio fixture not found: ${AUDIO_PATH}" >&2
  exit 2
fi

if ! command -v node >/dev/null 2>&1; then
  echo "error: node is required for the fixture transcription server" >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
server_pid=""
patched=""
cleanup_result_path=""
if [[ -z "${E2E_RESULT_PATH:-}" ]]; then
  cleanup_result_path="${RESULT_PATH}"
fi

cleanup() {
  if [[ -n "${server_pid}" ]] && kill -0 "${server_pid}" >/dev/null 2>&1; then
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" >/dev/null 2>&1 || true
  fi
  rm -rf "${tmpdir}"
  if [[ -n "${patched}" ]]; then
    rm -f "${patched}"
  fi
  if [[ -n "${cleanup_result_path}" ]]; then
    rm -f "${cleanup_result_path}"
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

assert_receipt_bool() {
  local key="$1"
  node -e '
    const fs = require("fs")
    const receipt = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
    const key = process.argv[2]
    if (receipt[key] !== true) {
      console.error(`error: receipt ${key} was ${receipt[key]}`)
      process.exit(1)
    }
  ' "${receipt_path}" "${key}"
}

ready_path="${tmpdir}/ready"
receipt_path="${tmpdir}/receipt.json"
server_log="${tmpdir}/server.log"

echo "== Fixture transcription server"
FIXTURE_TRANSCRIPTION_READY_PATH="${ready_path}" \
FIXTURE_TRANSCRIPTION_RECEIPT_PATH="${receipt_path}" \
FIXTURE_TRANSCRIPTION_MODEL="${MODEL}" \
node scripts/fixture-transcription-server.mjs >"${server_log}" 2>&1 &
server_pid=$!

for _ in $(seq 1 100); do
  if [[ -s "${ready_path}" ]]; then
    break
  fi
  if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
    echo "error: fixture server exited before becoming ready" >&2
    cat "${server_log}" >&2 || true
    exit 1
  fi
  sleep 0.1
done

if [[ ! -s "${ready_path}" ]]; then
  echo "error: fixture server did not become ready" >&2
  cat "${server_log}" >&2 || true
  exit 1
fi

BASE_URL="$(tr -d '\r\n' <"${ready_path}")"
echo "server=${BASE_URL}"

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

patched="${xctestrun%.xctestrun}.fixture-openai.xctestrun"
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
  E2E_WAV_PATH \
  E2E_RESULT_PATH \
  E2E_TRANSCRIPTION_TIMEOUT_SECONDS \
  E2E_CLEANUP_PROVIDER \
  E2E_CLEANUP_MODEL \
  E2E_CLEANUP_BASE_URL \
  E2E_CLEANUP_API_KEY; do
  "${PLISTBUDDY}" -c "Delete ${env_root}:${key}" "${patched}" >/dev/null 2>&1 || true
done
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_PROVIDER string openai-compatible" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_BASE_URL string ${BASE_URL}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_MODEL string ${MODEL}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_API_KEY string ${API_KEY}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_RESULT_PATH string ${RESULT_PATH}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_TIMEOUT_SECONDS string ${TIMEOUT_SECONDS}" "${patched}"
if [[ -n "${E2E_WAV_PATH:-}" ]]; then
  "${PLISTBUDDY}" -c "Add ${env_root}:E2E_WAV_PATH string ${E2E_WAV_PATH}" "${patched}"
fi
for key in E2E_CLEANUP_PROVIDER E2E_CLEANUP_MODEL E2E_CLEANUP_BASE_URL E2E_CLEANUP_API_KEY; do
  if [[ -n "${!key:-}" ]]; then
    "${PLISTBUDDY}" -c "Add ${env_root}:${key} string ${!key}" "${patched}"
  fi
done

echo "== XCUITest fixture transcription"
rm -f "${RESULT_PATH}" "${receipt_path}"
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
  echo "error: XCUITest skipped; fixture E2E environment was not applied" >&2
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

if [[ ! -s "${receipt_path}" ]]; then
  echo "error: fixture server receipt missing or empty: ${receipt_path}" >&2
  cat "${server_log}" >&2 || true
  exit 1
fi

app_transcript="$(tr -d '\r' <"${RESULT_PATH}" | sed 's/^ *//; s/ *$//')"
assert_min_recall "${app_transcript}"
assert_receipt_bool valid
assert_receipt_bool hasFileField
assert_receipt_bool hasRIFF
assert_receipt_bool hasWAVE

receipt_model="$(node -e 'const fs=require("fs"); const r=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); process.stdout.write(r.model || "")' "${receipt_path}")"
if [[ "${receipt_model}" != "${MODEL}" ]]; then
  echo "error: fixture receipt model ${receipt_model} did not match ${MODEL}" >&2
  exit 1
fi

printf 'app_result=%s\n' "${app_transcript}"
printf 'app_recall=%s\n' "$(word_recall "${app_transcript}")"
printf 'fixture_receipt=%s\n' "${receipt_path}"

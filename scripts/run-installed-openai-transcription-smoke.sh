#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-/Applications/Foil.app}"
APP_BIN="${APP_PATH}/Contents/MacOS/Foil"
AUDIO_PATH="${E2E_WAV_PATH:-Foil/e2e-test-audio.wav}"
EXPECTED="${E2E_EXPECTED_TEXT:-the quick brown fox jumps over the lazy dog}"
MODEL="${E2E_TRANSCRIPTION_MODEL:-whisper-1}"
TIMEOUT_SECONDS="${E2E_TRANSCRIPTION_TIMEOUT_SECONDS:-120}"
RESULT_PATH="${E2E_RESULT_PATH:-/tmp/foil-installed-openai-e2e-result.txt}"
LOG_PATH="${E2E_LOG_PATH:-/tmp/foil-installed-openai-e2e.log}"
app_pid=""
RUNTIME_AUDIO_PATH=""

cleanup() {
  if [[ -n "${app_pid}" ]] && kill -0 "${app_pid}" >/dev/null 2>&1; then
    kill "${app_pid}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${RUNTIME_AUDIO_PATH}" ]]; then
    rm -f "${RUNTIME_AUDIO_PATH}"
  fi
}
trap cleanup EXIT

if [[ ! -x "${APP_BIN}" ]]; then
  echo "error: installed Foil binary not found at ${APP_BIN}" >&2
  exit 1
fi

if [[ ! -f "${AUDIO_PATH}" ]]; then
  echo "error: E2E audio file not found at ${AUDIO_PATH}" >&2
  exit 1
fi

RUNTIME_AUDIO_PATH="$(mktemp -t foil-installed-openai-e2e.XXXXXX.wav)"
cp "${AUDIO_PATH}" "${RUNTIME_AUDIO_PATH}"

if [[ -z "${OPENAI_API_KEY:-}" && -z "${E2E_API_KEY:-}" && -f ".env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source ".env.local"
  set +a
fi

api_key="${E2E_API_KEY:-${OPENAI_API_KEY:-}}"
if [[ -z "${api_key}" ]]; then
  echo "error: OPENAI_API_KEY or E2E_API_KEY is required" >&2
  exit 2
fi

rm -f "${RESULT_PATH}" "${LOG_PATH}"

osascript -e 'tell application id "com.neonwatty.Foil" to quit' >/dev/null 2>&1 || true
sleep 1

E2E_ALLOW_RELEASE_APP_SMOKE=1 \
E2E_TRANSCRIPTION_PROVIDER=openai \
E2E_TRANSCRIPTION_MODEL="${MODEL}" \
E2E_API_KEY="${api_key}" \
E2E_WAV_PATH="${RUNTIME_AUDIO_PATH}" \
E2E_RESULT_PATH="${RESULT_PATH}" \
"${APP_BIN}" --e2e-transcribe >"${LOG_PATH}" 2>&1 &
app_pid=$!

deadline=$((SECONDS + TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  if [[ -s "${RESULT_PATH}" ]]; then
    break
  fi
  if ! kill -0 "${app_pid}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if [[ ! -s "${RESULT_PATH}" ]]; then
  echo "status=fail"
  echo "error=installed app smoke did not produce a transcript within ${TIMEOUT_SECONDS}s"
  if [[ -f "${LOG_PATH}" ]]; then
    sed -E 's/sk-[A-Za-z0-9_-]{12,}/<redacted-api-key>/g; s/gsk_[A-Za-z0-9_-]+/<redacted-api-key>/g' "${LOG_PATH}" | tail -40
  fi
  exit 1
fi

transcript="$(cat "${RESULT_PATH}")"
missing=0
for word in ${EXPECTED}; do
  normalized_word="$(printf '%s' "${word}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alpha:]')"
  if [[ -n "${normalized_word}" ]] && ! printf '%s' "${transcript}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alpha:] \n' | grep -qw "${normalized_word}"; then
    missing=$((missing + 1))
  fi
done

if (( missing > 1 )); then
  echo "status=fail"
  echo "error=transcript missing ${missing} expected words"
  echo "transcript=${transcript}"
  exit 1
fi

echo "status=pass"
echo "transcript=${transcript}"

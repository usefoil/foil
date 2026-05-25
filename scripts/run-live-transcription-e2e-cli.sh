#!/usr/bin/env bash
set -euo pipefail

SCHEME="${SCHEME:-FoilE2E}"
CONFIG="${CONFIG:-Debug}"
ARCH="${ARCH:-arm64}"
AUDIO_PATH="${E2E_WAV_PATH:-Foil/e2e-test-audio.wav}"
EXPECTED="${E2E_EXPECTED_TEXT:-the quick brown fox jumps over the lazy dog}"
TIMEOUT_SECONDS="${E2E_TRANSCRIPTION_TIMEOUT_SECONDS:-90}"
OUTPUT_PATH="${E2E_OUTPUT_PATH:-local-e2e-output.txt}"
DERIVED_DATA_PATH="${E2E_DERIVED_DATA_PATH:-LocalCLIE2EDerivedData}"

if [[ -z "${GROQ_API_KEY:-${E2E_API_KEY:-}}" ]]; then
  echo "error: GROQ_API_KEY or E2E_API_KEY is required for live transcription E2E." >&2
  exit 1
fi

xcodebuild build \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  ARCHS="${ARCH}" \
  -destination "platform=macOS,arch=${ARCH}" \
  -derivedDataPath "${DERIVED_DATA_PATH}"

BUILT_PRODUCTS_DIR="$(
  xcodebuild \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    ARCHS="${ARCH}" \
    -destination "platform=macOS,arch=${ARCH}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    -showBuildSettings 2>/dev/null \
    | awk '/ BUILT_PRODUCTS_DIR = / {print $3; exit}'
)"

E2E_BIN="${BUILT_PRODUCTS_DIR}/${SCHEME}"
if [[ ! -x "${E2E_BIN}" ]]; then
  echo "error: missing executable ${E2E_BIN}" >&2
  exit 1
fi

rm -f "${OUTPUT_PATH}"

"${E2E_BIN}" \
  --audio "${AUDIO_PATH}" \
  --expected "${EXPECTED}" \
  --timeout "${TIMEOUT_SECONDS}" \
  > "${OUTPUT_PATH}" 2>&1 &
E2E_PID=$!

caffeinate -dimsu -w "${E2E_PID}" &
CAFFEINATE_PID=$!

(
  sleep 180 && kill -TERM "${E2E_PID}" 2>/dev/null
  sleep 30 && kill -9 "${E2E_PID}" 2>/dev/null
) &
WATCHDOG_PID=$!

set +e
wait "${E2E_PID}"
TEST_EXIT=$?
kill "${WATCHDOG_PID}" "${CAFFEINATE_PID}" 2>/dev/null
wait "${WATCHDOG_PID}" "${CAFFEINATE_PID}" 2>/dev/null
set -e

cat "${OUTPUT_PATH}"
exit "${TEST_EXIT}"

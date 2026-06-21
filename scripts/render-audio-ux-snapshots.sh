#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-Debug}"
SCHEME="${SCHEME:-Foil}"
OUTPUT_DIR="${SNAPSHOT_OUTPUT_DIR:-${ROOT_DIR}/docs/evidence/audio-ux-snapshots/latest}"

if [[ -z "${APP_PATH:-}" ]]; then
  BUILD_DIR="$(
    xcodebuild -scheme "${SCHEME}" -configuration "${CONFIG}" -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
      | awk '/BUILT_PRODUCTS_DIR = / {print substr($0, index($0, "=") + 2); exit}'
  )"
  APP_PATH="${BUILD_DIR}/Foil.app"
fi

EXECUTABLE="${APP_PATH}/Contents/MacOS/Foil"
if [[ ! -x "${EXECUTABLE}" ]]; then
  echo "ERROR: Foil executable not found at ${EXECUTABLE}. Run make build first or set APP_PATH." >&2
  exit 2
fi

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

"${EXECUTABLE}" --render-audio-ux-snapshots --snapshot-output "${OUTPUT_DIR}"

if [[ ! -f "${OUTPUT_DIR}/receipt.json" ]]; then
  echo "ERROR: snapshot receipt missing at ${OUTPUT_DIR}/receipt.json" >&2
  exit 1
fi

png_count="$(find "${OUTPUT_DIR}" -maxdepth 1 -name '*.png' -type f | wc -l | tr -d ' ')"
if [[ "${png_count}" != "12" ]]; then
  echo "ERROR: expected 12 PNG snapshots, found ${png_count}" >&2
  find "${OUTPUT_DIR}" -maxdepth 1 -type f | sort >&2
  exit 1
fi

echo "Rendered audio UX snapshots to ${OUTPUT_DIR}"
find "${OUTPUT_DIR}" -maxdepth 1 -type f | sort

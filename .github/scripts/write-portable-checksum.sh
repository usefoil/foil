#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $(basename "$0") ARTIFACT_PATH" >&2
  exit 2
fi

ARTIFACT_PATH="$1"
if [ ! -f "$ARTIFACT_PATH" ]; then
  echo "Artifact not found: $ARTIFACT_PATH" >&2
  exit 1
fi

ARTIFACT_DIRECTORY="$(cd "$(dirname "$ARTIFACT_PATH")" && pwd)"
ARTIFACT_NAME="$(basename "$ARTIFACT_PATH")"
CHECKSUM_PATH="${ARTIFACT_PATH}.sha256"

(
  cd "$ARTIFACT_DIRECTORY"
  shasum -a 256 "$ARTIFACT_NAME"
) > "$CHECKSUM_PATH"

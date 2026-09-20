#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_directory=$(mktemp -d "${TMPDIR:-/tmp}/foil-local-corrections.XXXXXX")
trap 'rm -rf "$build_directory"' EXIT HUP INT TERM

xcrun swiftc \
  -O \
  "$repository_root/Foil/LocalCorrectionEngine.swift" \
  "$repository_root/tools/local-corrections-adapter/main.swift" \
  -o "$build_directory/local-corrections-adapter"

python3 "$repository_root/tests/local_corrections_harness.py" \
  --split all \
  --adapter "$build_directory/local-corrections-adapter"

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_SCRIPT="$REPO_ROOT/.github/scripts/build-notarized-qa-dmg.sh"
PROJECT_FILE="$REPO_ROOT/Foil.xcodeproj/project.pbxproj"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expected_version="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PROJECT_FILE" | head -1)"
expected_build="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' "$PROJECT_FILE" | head -1)"

output="$(cd "$REPO_ROOT" && env -u GITHUB_RUN_ID "$BUILD_SCRIPT" --print-version-defaults)"
printf '%s\n' "$output" | grep -Fxq "version=$expected_version" || fail "default version should come from project"
printf '%s\n' "$output" | grep -Fxq "build=$expected_build" || fail "local default build should come from project"

output="$(cd "$REPO_ROOT" && GITHUB_RUN_ID=26819001441 "$BUILD_SCRIPT" --print-version-defaults)"
printf '%s\n' "$output" | grep -Fxq "build=26819001441" || fail "GitHub QA build should default to run id"

output="$(cd "$REPO_ROOT" && GITHUB_RUN_ID=26819001441 BUILD_NUMBER=123 "$BUILD_SCRIPT" --print-version-defaults)"
printf '%s\n' "$output" | grep -Fxq "build=123" || fail "explicit build input should win"

if (cd "$REPO_ROOT" && BUILD_NUMBER=abc "$BUILD_SCRIPT" --print-version-defaults) >/tmp/foil-invalid-build.out 2>&1; then
  fail "invalid explicit build should fail"
fi
grep -Fq "BUILD_NUMBER must be numeric" /tmp/foil-invalid-build.out || fail "invalid build error should explain numeric requirement"
rm -f /tmp/foil-invalid-build.out

echo "PASS: build-notarized-qa-dmg defaults"

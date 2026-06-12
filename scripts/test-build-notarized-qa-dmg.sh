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

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/sign_update" <<'SH'
#!/bin/bash
set -euo pipefail

private_key="$(cat)"
if [ "$private_key" != "test-private-key" ]; then
  echo "unexpected private key" >&2
  exit 1
fi

if [ "$1" != "--ed-key-file" ] || [ "$2" != "-" ]; then
  echo "unexpected sign_update key arguments: $*" >&2
  exit 1
fi
shift 2

if [ "${1:-}" = "--verify" ]; then
  shift
  if [ "$#" -ne 2 ] || [ "$2" != "test-signature" ]; then
    echo "unexpected verify arguments: $*" >&2
    exit 1
  fi
  exit 0
fi

if [ "$#" -ne 1 ]; then
  echo "unexpected signing arguments: $*" >&2
  exit 1
fi
size="$(stat -f%z "$1")"
printf 'sparkle:edSignature="test-signature" length="%s"\n' "$size"
SH
chmod +x "$tmpdir/sign_update"

cat >"$tmpdir/gh" <<'SH'
#!/bin/bash
set -euo pipefail

if [ "$1" != "release" ] || [ "$2" != "upload" ] || [ "$3" != "v9.8.7" ]; then
  echo "unexpected gh arguments: $*" >&2
  exit 1
fi
if [ ! -f "$4" ]; then
  echo "missing appcast upload path: $4" >&2
  exit 1
fi
SH
chmod +x "$tmpdir/gh"

printf 'fake dmg' >"$tmpdir/Foil-9.8.7-macos.dmg"
(
  cd "$REPO_ROOT"
  PATH="$tmpdir:$PATH" \
    RUNNER_TEMP="$tmpdir" \
    VERSION=9.8.7 \
    BUILD_NUMBER=123 \
    GITHUB_TOKEN=dummy \
    SPARKLE_PRIVATE_ED_KEY=test-private-key \
    SIGN_UPDATE="$tmpdir/sign_update" \
    .github/scripts/generate-appcast.sh >/tmp/foil-generate-appcast.out
)

grep -Fq 'sparkle:edSignature="test-signature"' "$tmpdir/appcast.xml" || fail "appcast should include Sparkle EdDSA signature"
grep -Fq 'sparkle:length="8"' "$tmpdir/appcast.xml" || fail "appcast should include Sparkle signed length"
grep -Fq 'length="8"' "$tmpdir/appcast.xml" || fail "appcast should include enclosure length"
rm -f /tmp/foil-generate-appcast.out

(
  cd "$REPO_ROOT"
  public_key="$(openssl rand -base64 32)"
  info_backup="$(mktemp)"
  build_log="$(mktemp)"

  restore_info_plist() {
    cp "$info_backup" Foil/Info.plist
    rm -f "$info_backup" "$build_log"
  }
  cp Foil/Info.plist "$info_backup"
  trap restore_info_plist EXIT

  /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" Foil/Info.plist >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $public_key" Foil/Info.plist

  if ! xcodebuild build \
    -scheme Foil \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$tmpdir/DerivedData" \
    CODE_SIGNING_ALLOWED=NO >"$build_log" 2>&1; then
    tail -80 "$build_log" >&2
    fail "xcodebuild should build with injected SUPublicEDKey"
  fi

  embedded_key="$(defaults read "$tmpdir/DerivedData/Build/Products/Debug/Foil.app/Contents/Info.plist" SUPublicEDKey)"
  [ "$embedded_key" = "$public_key" ] || fail "built app should contain injected SUPublicEDKey"
  printf '%s' "$embedded_key" | base64 --decode | wc -c | grep -Eq '^[[:space:]]*32$' || fail "injected SUPublicEDKey should decode to 32 bytes"
)

echo "PASS: build-notarized-qa-dmg defaults"

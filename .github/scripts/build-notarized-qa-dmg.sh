#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
DMG_BACKGROUND="$REPO_ROOT/.github/assets/dmg-background.png"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
QA_SUFFIX="${QA_SUFFIX:-qa-${GITHUB_RUN_NUMBER:-local}}"
PRINT_VERSION_DEFAULTS="no"

if [ "${1:-}" = "--print-version-defaults" ]; then
  PRINT_VERSION_DEFAULTS="yes"
  shift
fi

if [ "$#" -gt 0 ]; then
  echo "Usage: $(basename "$0") [--print-version-defaults]" >&2
  exit 2
fi

if [ -z "$VERSION" ]; then
  VERSION="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$REPO_ROOT/Foil.xcodeproj/project.pbxproj" | head -1)"
fi
if [ -z "$BUILD_NUMBER" ]; then
  if [ -n "${GITHUB_RUN_ID:-}" ]; then
    BUILD_NUMBER="$GITHUB_RUN_ID"
  else
    BUILD_NUMBER="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' "$REPO_ROOT/Foil.xcodeproj/project.pbxproj" | head -1)"
  fi
fi
if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
  echo "Could not infer VERSION or BUILD_NUMBER from Foil.xcodeproj." >&2
  exit 1
fi
if ! printf '%s' "$BUILD_NUMBER" | grep -Eq '^[0-9]+$'; then
  echo "BUILD_NUMBER must be numeric, got '$BUILD_NUMBER'" >&2
  exit 2
fi

if [ "$PRINT_VERSION_DEFAULTS" = "yes" ]; then
  echo "version=$VERSION"
  echo "build=$BUILD_NUMBER"
  exit 0
fi

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APP_STORE_CONNECT_KEY_ID:?APP_STORE_CONNECT_KEY_ID is required}"
: "${APP_STORE_CONNECT_ISSUER_ID:?APP_STORE_CONNECT_ISSUER_ID is required}"
: "${APP_STORE_CONNECT_PRIVATE_KEY:?APP_STORE_CONNECT_PRIVATE_KEY is required}"
: "${SPARKLE_PUBLIC_ED_KEY:?SPARKLE_PUBLIC_ED_KEY is required}"

SAFE_SUFFIX="$(printf '%s' "$QA_SUFFIX" | tr -c 'A-Za-z0-9._-' '-')"
ARCHIVE_PATH="$RUNNER_TEMP/Foil-QA.xcarchive"
EXPORT_PATH="$RUNNER_TEMP/foil-qa-export"
DMG_ROOT="$RUNNER_TEMP/foil-qa-dmg-root"
DMG_PATH="$RUNNER_TEMP/Foil-${VERSION}-${BUILD_NUMBER}-${SAFE_SUFFIX}-macos.dmg"
CHECKSUM_PATH="${DMG_PATH}.sha256"
EXPORT_OPTIONS="$RUNNER_TEMP/Foil-QA-ExportOptions.plist"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$RUNNER_TEMP/DerivedData}"
INFO_PLIST="$REPO_ROOT/Foil/Info.plist"
INFO_PLIST_BACKUP="$(mktemp)"

restore_info_plist() {
  cp "$INFO_PLIST_BACKUP" "$INFO_PLIST"
  rm -f "$INFO_PLIST_BACKUP"
}
cp "$INFO_PLIST" "$INFO_PLIST_BACKUP"
trap restore_info_plist EXIT

sed "s/\$(APPLE_TEAM_ID)/$APPLE_TEAM_ID/" "$REPO_ROOT/ExportOptions.plist" > "$EXPORT_OPTIONS"

if ! printf '%s' "$SPARKLE_PUBLIC_ED_KEY" | base64 --decode | wc -c | grep -Eq '^[[:space:]]*32$'; then
  echo "SPARKLE_PUBLIC_ED_KEY must be a base64-encoded 32-byte EdDSA public key" >&2
  exit 2
fi
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$INFO_PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST"

xcodebuild archive \
  -scheme Foil \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

codesign --verify --deep --strict --verbose=2 "$EXPORT_PATH/Foil.app"
codesign -dv --verbose=4 "$EXPORT_PATH/Foil.app"

APP_VERSION="$(defaults read "$EXPORT_PATH/Foil.app/Contents/Info.plist" CFBundleShortVersionString)"
APP_BUILD="$(defaults read "$EXPORT_PATH/Foil.app/Contents/Info.plist" CFBundleVersion)"
APP_SPARKLE_PUBLIC_KEY="$(defaults read "$EXPORT_PATH/Foil.app/Contents/Info.plist" SUPublicEDKey)"
if [ "$APP_VERSION" != "$VERSION" ]; then
  echo "Expected CFBundleShortVersionString '$VERSION' but found '$APP_VERSION'" >&2
  exit 1
fi
if [ "$APP_BUILD" != "$BUILD_NUMBER" ]; then
  echo "Expected CFBundleVersion '$BUILD_NUMBER' but found '$APP_BUILD'" >&2
  exit 1
fi
if [ "$APP_SPARKLE_PUBLIC_KEY" != "$SPARKLE_PUBLIC_ED_KEY" ]; then
  echo "Expected SUPublicEDKey to match SPARKLE_PUBLIC_ED_KEY" >&2
  exit 1
fi
echo "Verified app bundle version: $APP_VERSION ($APP_BUILD)"
echo "Verified Sparkle public EdDSA key is embedded."

if ! command -v create-dmg >/dev/null 2>&1; then
  brew install create-dmg
fi

mkdir -p "$DMG_ROOT"
cp -R "$EXPORT_PATH/Foil.app" "$DMG_ROOT/Foil.app"

if [ ! -f "$DMG_BACKGROUND" ]; then
  echo "Expected DMG background at $DMG_BACKGROUND" >&2
  exit 1
fi

create-dmg \
  --volname "Foil QA" \
  --background "$DMG_BACKGROUND" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Foil.app" 150 190 \
  --app-drop-link 450 190 \
  "$DMG_PATH" \
  "$DMG_ROOT"

codesign --force \
  --sign "Developer ID Application" \
  --timestamp \
  "$DMG_PATH"

PRIVATE_KEYS_DIR="$RUNNER_TEMP/private_keys"
mkdir -p "$PRIVATE_KEYS_DIR"
KEY_PATH="$PRIVATE_KEYS_DIR/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
printf '%s' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$KEY_PATH"
chmod 600 "$KEY_PATH"

xcrun notarytool submit \
  "$DMG_PATH" \
  --key "$KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"

echo "Created notarized QA DMG: $DMG_PATH"
cat "$CHECKSUM_PATH"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "dmg_path=$DMG_PATH"
    echo "checksum_path=$CHECKSUM_PATH"
    echo "version=$VERSION"
    echo "build=$BUILD_NUMBER"
  } >> "$GITHUB_OUTPUT"
fi

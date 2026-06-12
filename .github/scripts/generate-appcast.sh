#!/usr/bin/env bash
set -euo pipefail

# Generate appcast.xml for Sparkle auto-updates and upload to GitHub Release.
#
# Required environment variables:
#   VERSION        — semantic version (e.g., 1.9.0)
#   GITHUB_TOKEN   — token for gh CLI
#   RUNNER_TEMP    — temp directory (set by GitHub Actions)
#
# Optional:
#   BUILD_NUMBER      — used as sparkle:version (defaults to GITHUB_RUN_NUMBER)

: "${VERSION:?VERSION is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${SPARKLE_PRIVATE_ED_KEY:?SPARKLE_PRIVATE_ED_KEY is required}"

REPO="${RELEASE_REPO:-${GITHUB_REPOSITORY:-usefoil/foil}}"
DMG_PATH="$RUNNER_TEMP/Foil-${VERSION}-macos.dmg"
DMG_FILENAME="Foil-${VERSION}-macos.dmg"
DMG_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${DMG_FILENAME}"
FILE_SIZE=$(stat -f%z "$DMG_PATH")
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
APPCAST_PATH="$RUNNER_TEMP/appcast.xml"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$RUNNER_TEMP/DerivedData}"

find_sign_update() {
  if [ -n "${SIGN_UPDATE:-}" ] && [ -x "$SIGN_UPDATE" ]; then
    printf '%s\n' "$SIGN_UPDATE"
    return
  fi

  local derived_sign_update="$DERIVED_DATA_PATH/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
  if [ -x "$derived_sign_update" ]; then
    printf '%s\n' "$derived_sign_update"
    return
  fi

  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update' \
    -type f \
    -print 2>/dev/null | sort | tail -1
}

SIGN_UPDATE_BIN="$(find_sign_update)"
if [ -z "$SIGN_UPDATE_BIN" ] || [ ! -x "$SIGN_UPDATE_BIN" ]; then
  echo "Could not find Sparkle sign_update. Build the app before generating appcast.xml." >&2
  exit 1
fi

SIGNATURE_ATTRIBUTES="$(printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$SIGN_UPDATE_BIN" --ed-key-file - "$DMG_PATH")"
ED_SIGNATURE="$(printf '%s\n' "$SIGNATURE_ATTRIBUTES" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
SIGNED_LENGTH="$(printf '%s\n' "$SIGNATURE_ATTRIBUTES" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
if [ -z "$ED_SIGNATURE" ] || [ -z "$SIGNED_LENGTH" ]; then
  echo "Sparkle sign_update did not produce enclosure signature attributes" >&2
  exit 1
fi
if [ "$SIGNED_LENGTH" != "$FILE_SIZE" ]; then
  echo "Sparkle signed length '$SIGNED_LENGTH' does not match DMG size '$FILE_SIZE'" >&2
  exit 1
fi

cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Foil</title>
    <link>https://github.com/${REPO}</link>
    <description>Foil Updates</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${DMG_URL}"
        length="${FILE_SIZE}"
        sparkle:edSignature="${ED_SIGNATURE}"
        sparkle:length="${SIGNED_LENGTH}"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
EOF

echo "Generated appcast.xml:"
cat "$APPCAST_PATH"

printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$SIGN_UPDATE_BIN" --ed-key-file - --verify "$DMG_PATH" "$ED_SIGNATURE"

gh release upload "v${VERSION}" "$APPCAST_PATH" --repo "$REPO" --clobber

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

REPO="${RELEASE_REPO:-${GITHUB_REPOSITORY:-usefoil/foil}}"
DMG_PATH="$RUNNER_TEMP/Foil-${VERSION}-macos.dmg"
DMG_FILENAME="Foil-${VERSION}-macos.dmg"
DMG_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${DMG_FILENAME}"
FILE_SIZE=$(stat -f%z "$DMG_PATH")
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
APPCAST_PATH="$RUNNER_TEMP/appcast.xml"

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
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
EOF

echo "Generated appcast.xml:"
cat "$APPCAST_PATH"

gh release upload "v${VERSION}" "$APPCAST_PATH" --repo "$REPO" --clobber

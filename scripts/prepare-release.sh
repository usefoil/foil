#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/prepare-release.sh VERSION BUILD_NUMBER NOTES_FILE

Prepares an intentional Foil release PR by updating:
  - Foil.xcodeproj MARKETING_VERSION and CURRENT_PROJECT_VERSION
  - package.json/package-lock.json version
  - CHANGELOG.md with release notes

After the PR merges through the merge queue, create and push the tag manually:
  git tag vVERSION
  git push origin vVERSION

Then run the Release workflow with VERSION.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

VERSION="${1:-}"
BUILD_NUMBER="${2:-}"
NOTES_FILE="${3:-}"

if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ] || [ -z "$NOTES_FILE" ]; then
  usage >&2
  exit 2
fi

if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
  echo "VERSION must be a semantic version without a leading v, for example 1.12.1" >&2
  exit 2
fi

if ! printf '%s' "$BUILD_NUMBER" | grep -Eq '^[0-9]+$'; then
  echo "BUILD_NUMBER must be a positive integer" >&2
  exit 2
fi

if [ ! -f "$NOTES_FILE" ]; then
  echo "NOTES_FILE does not exist: $NOTES_FILE" >&2
  exit 2
fi

if [ ! -s "$NOTES_FILE" ]; then
  echo "NOTES_FILE is empty: $NOTES_FILE" >&2
  exit 2
fi

PROJECT_FILE="Foil.xcodeproj/project.pbxproj"
TODAY="$(date +%Y-%m-%d)"
PREVIOUS_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"

perl -0pi -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/g" "$PROJECT_FILE"
perl -0pi -e "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PROJECT_FILE"

npm pkg set "version=$VERSION" >/dev/null
npm install --package-lock-only >/dev/null

CHANGELOG_ENTRY="$(mktemp)"
{
  if [ -n "$PREVIOUS_TAG" ]; then
    printf '## [%s](https://github.com/mean-weasel/foil/compare/%s...v%s) (%s)\n\n' "$VERSION" "$PREVIOUS_TAG" "$VERSION" "$TODAY"
  else
    printf '## [%s] (%s)\n\n' "$VERSION" "$TODAY"
  fi
  cat "$NOTES_FILE"
  printf '\n\n'
} > "$CHANGELOG_ENTRY"

CHANGELOG_NEXT="$(mktemp)"
cat "$CHANGELOG_ENTRY" CHANGELOG.md > "$CHANGELOG_NEXT"
mv "$CHANGELOG_NEXT" CHANGELOG.md
rm -f "$CHANGELOG_ENTRY"

echo "Prepared Foil $VERSION ($BUILD_NUMBER)."
echo "Review CHANGELOG.md, then open a PR and merge through the queue before tagging v$VERSION."

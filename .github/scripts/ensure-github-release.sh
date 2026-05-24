#!/usr/bin/env bash
set -euo pipefail

: "${VERSION:?VERSION is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

REPO="${RELEASE_REPO:-${GITHUB_REPOSITORY:-mean-weasel/groqtalk}}"
TAG="v${VERSION}"
NOTES_FILE="${RUNNER_TEMP:-/tmp}/GroqTalk-${VERSION}-release-notes.md"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "GitHub release $TAG already exists."
  exit 0
fi

if [ -f CHANGELOG.md ]; then
  awk -v version="$VERSION" '
    BEGIN { capture = 0 }
    $0 ~ "^#* \\[?" version "\\]?" {
      capture = 1
      next
    }
    capture && $0 ~ "^#+" {
      exit
    }
    capture {
      print
    }
  ' CHANGELOG.md > "$NOTES_FILE"
fi

if [ ! -s "$NOTES_FILE" ]; then
  cat > "$NOTES_FILE" <<EOF
GroqTalk ${VERSION}

See the tagged source for this release.
EOF
fi

echo "Creating GitHub release $TAG in $REPO."
gh release create "$TAG" \
  --repo "$REPO" \
  --title "GroqTalk ${VERSION}" \
  --notes-file "$NOTES_FILE"

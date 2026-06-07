#!/usr/bin/env bash
set -euo pipefail

event_name="${GITHUB_EVENT_NAME:-}"
event_path="${GITHUB_EVENT_PATH:-}"

app_ci="true"
changed_files=""
base_sha=""
head_sha=""

if [ -n "$event_path" ] && [ -f "$event_path" ]; then
  case "$event_name" in
    pull_request|pull_request_target)
      base_sha="$(jq -r '.pull_request.base.sha // empty' "$event_path")"
      head_sha="$(jq -r '.pull_request.head.sha // empty' "$event_path")"
      ;;
    merge_group)
      base_sha="$(jq -r '.merge_group.base_sha // empty' "$event_path")"
      head_sha="$(jq -r '.merge_group.head_sha // empty' "$event_path")"
      ;;
    push)
      base_sha="$(jq -r '.before // empty' "$event_path")"
      head_sha="$(jq -r '.after // empty' "$event_path")"
      if printf '%s' "$base_sha" | grep -Eq '^0+$'; then
        base_sha=""
      fi
      ;;
  esac
fi

if [ -n "$base_sha" ] && [ -n "$head_sha" ]; then
  if changed_files="$(git diff --name-only "$base_sha" "$head_sha")"; then
    app_ci="false"
    while IFS= read -r path; do
      case "$path" in
        Foil/*|FoilTests/*|FoilUITests/*|Foil.xcodeproj/*|project.yml|.github/*|ExportOptions.plist|Makefile|package.json|package-lock.json|scripts/*|docs/release-*.md)
          app_ci="true"
          break
          ;;
      esac
    done <<< "$changed_files"
  else
    echo "::warning::Could not diff $base_sha..$head_sha; running app CI conservatively."
    app_ci="true"
  fi
else
  echo "::notice::No comparable base/head found for ${event_name:-unknown event}; running app CI conservatively."
  app_ci="true"
fi

echo "app_ci=$app_ci" >> "$GITHUB_OUTPUT"
{
  echo "changed_files<<EOF"
  printf '%s\n' "$changed_files"
  echo "EOF"
} >> "$GITHUB_OUTPUT"

echo "App CI required: $app_ci"
if [ -n "$changed_files" ]; then
  echo "$changed_files"
fi

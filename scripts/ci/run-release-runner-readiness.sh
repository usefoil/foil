#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
: "${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${RUNNER_NAME:?RUNNER_NAME is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${READINESS_SLOT:?READINESS_SLOT is required}"
[[ "$GITHUB_RUN_ID" =~ ^[0-9]+$ && "$GITHUB_RUN_ATTEMPT" =~ ^[0-9]+$ ]] || exit 2
case "$READINESS_SLOT" in 1|2|3) ;; *) echo "invalid readiness slot" >&2; exit 2 ;; esac

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
artifact_root="$repo_root/artifacts/readiness-$READINESS_SLOT"
run_parent="$RUNNER_TEMP/foil-readiness-runs"
run_root="$run_parent/$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT-$READINESS_SLOT"
preflight="$artifact_root/preflight.json"
receipt="$artifact_root/receipt-$READINESS_SLOT.json"
[ ! -e "$artifact_root" ] && [ ! -e "$run_root" ] || { echo "refusing to overwrite readiness evidence" >&2; exit 2; }
mkdir -p "$artifact_root" "$run_root"
printf '%s\n' "$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT-$READINESS_SLOT" > "$run_root/.foil-readiness-owned"

classification="infrastructure_failed"
cleanup_status="failed"
interrupted=false
trap 'interrupted=true; exit 143' INT TERM HUP
finish() {
  status=$?
  trap - EXIT INT TERM HUP
  if bash "$repo_root/scripts/ci/release-readiness-cleanup.sh" --run-root "$run_root" >"$artifact_root/cleanup.log" 2>&1; then
    cleanup_status=passed
  fi
  if [ "$interrupted" = true ]; then classification=cancelled
  elif [ "$status" -eq 0 ] && [ "$cleanup_status" = passed ]; then classification=passed
  fi
  node "$repo_root/scripts/ci/release-runner-receipt.mjs" --preflight "$preflight" \
    --cleanup-status "$cleanup_status" --classification "$classification" --output "$receipt" || exit 1
  [ "$classification" = passed ] || exit 1
}
trap finish EXIT

node "$repo_root/scripts/ci/runner-preflight.mjs" \
  --baseline "$repo_root/scripts/ci/runner-baseline.json" --output "$preflight" >"$artifact_root/preflight.log" 2>&1

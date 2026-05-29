#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/foil-queued-paste-compatibility-${STAMP}}"

usage() {
  cat <<'EOF'
Usage: scripts/run-queued-paste-compatibility-smoke.sh [--skip-runs] [--include-cross-app]

Runs local prerequisite smoke checks for queued-paste compatibility evidence and
prints or records the queued-paste rows in docs/queued-paste-compatibility-smoke.md.

This script drives the visible macOS desktop. By default it may open TextEdit
and /Applications/Foil.app, and it may open a disposable browser tab for the
queued smoke. It must not quit the user's browser or close browser tabs.

Options:
  --skip-runs    Print checklist and create the artifact directory without
                 running desktop automation commands.
  --include-cross-app
                 Also run make test-cross-app. This is opt-in because that
                 existing local integration test drives Terminal/Chrome and may
                 close the Chrome tab it opens.
EOF
}

SKIP_RUNS=0
INCLUDE_CROSS_APP=0
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      usage
      exit 0
      ;;
    --skip-runs)
      SKIP_RUNS=1
      ;;
    --include-cross-app)
      INCLUDE_CROSS_APP=1
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$ARTIFACT_DIR"

run_step() {
  local name="$1"
  shift
  local log="$ARTIFACT_DIR/${name}.log"
  echo "=== $name ==="
  echo "Command: $*" | tee "$log"
  set +e
  (cd "$ROOT_DIR" && "$@") 2>&1 | tee -a "$log"
  local status=${PIPESTATUS[0]}
  set -e
  echo "Exit status: $status" | tee -a "$log"
  echo
  return "$status"
}

cat >"$ARTIFACT_DIR/README.md" <<EOF
# Queued Paste Compatibility Smoke Artifacts

Created: ${STAMP}
Runbook: docs/queued-paste-compatibility-smoke.md

The logs in this directory are local compatibility evidence for target capture,
browser text-entry behavior, and real-target queued delivery.
EOF

echo "Artifacts: $ARTIFACT_DIR"
echo

if [[ "$SKIP_RUNS" == "0" ]]; then
  failures=0
  run_step "textedit-installed-app-target" make test-paste-real || failures=$((failures + 1))
  if [[ "$INCLUDE_CROSS_APP" == "1" ]]; then
    run_step "cross-app-browser-targets" make test-cross-app || failures=$((failures + 1))
  else
    echo "Skipping make test-cross-app by default because it drives Chrome/Terminal."
    echo "Pass --include-cross-app on an idle desktop if you want that prerequisite gate."
    echo
  fi
  run_step "queued-real-targets" swift tests/test_queued_paste_compatibility.swift || failures=$((failures + 1))
else
  failures=0
  echo "Skipping desktop automation runs."
  echo
fi

cat <<EOF | tee "$ARTIFACT_DIR/manual-queued-paste-checklist.md"
# Queued-Paste Rows

Record or confirm these rows in docs/queued-paste-compatibility-smoke.md:

- TextEdit disposable document: app name, pid, document/window title, queued
  state before Paste Next, delivery result, focus result, evidence path.
- Browser text field: browser app name, pid, page/window title, queued state
  before Paste Next, delivery result, focus result, evidence path.
- Closed/unavailable target: captured target identity before close/quit,
  queued state before Paste Next, fallback/manual-paste result, evidence path.

The queued-real-targets log is the authoritative local automation evidence for
real-target queued delivery.
EOF

echo
if [[ "$failures" -gt 0 ]]; then
  echo "Completed with $failures failing prerequisite gate(s). See $ARTIFACT_DIR."
  exit 1
fi

echo "Completed prerequisite gates. See $ARTIFACT_DIR."

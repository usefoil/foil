#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/foil-queued-paste-compatibility-${STAMP}}"

usage() {
  cat <<'EOF'
Usage: scripts/run-queued-paste-compatibility-smoke.sh [--skip-runs]

Runs local prerequisite smoke checks for queued-paste compatibility evidence and
prints or records the queued-paste rows in docs/queued-paste-compatibility-smoke.md.

This script drives the visible macOS desktop. It may open TextEdit, Terminal,
Google Chrome, and /Applications/Foil.app. It must not quit the user's browser.

Options:
  --skip-runs    Print checklist and create the artifact directory without
                 running desktop automation commands.
EOF
}

SKIP_RUNS=0
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      usage
      exit 0
      ;;
    --skip-runs)
      SKIP_RUNS=1
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
  run_step "cross-app-browser-targets" make test-cross-app || failures=$((failures + 1))
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

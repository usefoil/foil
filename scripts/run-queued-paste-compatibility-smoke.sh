#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/foil-queued-paste-compatibility-${STAMP}}"

usage() {
  cat <<'EOF'
Usage: scripts/run-queued-paste-compatibility-smoke.sh [--skip-runs] [--installed-app]

Runs local prerequisite smoke checks for queued-paste compatibility evidence and
prints or records the queued-paste rows in docs/queued-paste-compatibility-smoke.md.

This script drives the visible macOS desktop. It may open TextEdit, Terminal,
Google Chrome, Firefox/Safari when installed, and /Applications/Foil.app. Browser
targets use disposable localhost pages, request private windows where supported,
close only the disposable target tabs/windows they create, and must not quit the
user's browser.

Options:
  --installed-app
                 Run against the existing /Applications/Foil.app. This mode
                 does not build or install a local debug app and runs identity
                 checks before visible desktop automation.
  --skip-runs    Print checklist and create the artifact directory without
                 running desktop automation commands.
EOF
}

SKIP_RUNS=0
INSTALLED_APP_MODE=0
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      usage
      exit 0
      ;;
    --skip-runs)
      SKIP_RUNS=1
      ;;
    --installed-app)
      INSTALLED_APP_MODE=1
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
Mode: $([[ "$INSTALLED_APP_MODE" == "1" ]] && echo "installed app" || echo "local debug")

The logs in this directory are local compatibility evidence for target capture,
browser text-entry behavior, and real-target queued delivery.
EOF

echo "Artifacts: $ARTIFACT_DIR"
echo

if [[ "$SKIP_RUNS" == "0" ]]; then
  failures=0
  if [[ "$INSTALLED_APP_MODE" == "1" ]]; then
    if run_step "installed-app-identity" make prepare-local-permissions-qa-check; then
      if ! run_step "textedit-installed-app-target" make test-paste-real-installed; then
        failures=$((failures + 1))
        echo "Installed-app TextEdit target smoke failed; skipping remaining visible desktop automation in --installed-app mode."
        echo
        SKIP_REMAINING_INSTALLED_APP_STEPS=1
      fi
    else
      failures=$((failures + 1))
      echo "Installed-app identity failed; skipping visible desktop queued-paste automation in --installed-app mode."
      echo
      SKIP_REMAINING_INSTALLED_APP_STEPS=1
    fi
  else
    run_step "textedit-installed-app-target" make test-paste-real || failures=$((failures + 1))
    run_step "installed-app-identity" make prepare-local-permissions-qa-check || failures=$((failures + 1))
  fi
  if [[ "${SKIP_REMAINING_INSTALLED_APP_STEPS:-0}" != "1" ]]; then
    run_step "cross-app-browser-targets" make test-cross-app || failures=$((failures + 1))
    run_step "queued-real-targets" swift tests/test_queued_paste_compatibility.swift || failures=$((failures + 1))
  fi
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
- Browser text field: browser app name, pid, page/window title, localhost/private
  target state, queued state before Paste Next, delivery result, focus result,
  evidence path.
- Additional browser text field when installed: app name, pid, page/window
  title, localhost/private target state, queued state before Paste Next,
  delivery result, focus result, evidence path.
- Closed/unavailable target: captured target identity before close/quit,
  queued state before Paste Next, fallback/manual-paste result, recovery
  message, evidence path.

The queued-real-targets log is the authoritative local automation evidence for
real-target queued delivery.
EOF

echo
if [[ "$failures" -gt 0 ]]; then
  echo "Completed with $failures failing prerequisite gate(s). See $ARTIFACT_DIR."
  exit 1
fi

echo "Completed prerequisite gates. See $ARTIFACT_DIR."

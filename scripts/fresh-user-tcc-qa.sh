#!/bin/bash
set -euo pipefail

APP_NAME="${APP_NAME:-Foil}"
BUNDLE_ID="${BUNDLE_ID:-com.neonwatty.Foil}"
APP_PATH="${APP_PATH:-/Applications/$APP_NAME.app}"
DEFAULT_HOST="${FRESH_USER_TCC_QA_HOST:-mm2}"
SSH="${SSH:-ssh}"
PLISTBUDDY="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"

SUBCOMMAND="${1:-}"
HOST="$DEFAULT_HOST"
LOCAL_MODE=0
EVIDENCE_DIR=""
EXPECTED_HOSTNAME="${EXPECTED_HOSTNAME:-}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-$BUNDLE_ID}"
EXPECTED_ARCH="${EXPECTED_ARCH:-}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
EXPECTED_BUILD="${EXPECTED_BUILD:-}"
EXPECTED_RUNNER_NAME="${EXPECTED_RUNNER_NAME:-foil-mac-mini-2}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <preflight|collect|collect-diagnostics|plan|print-operator-checklist> [options]

Commands:
  preflight                 Collect evidence and fail if explicit expectations are not met.
  collect                   Collect the same evidence packet without expectation checks.
  collect-diagnostics       Collect preflight plus read-only process, diagnostics, audio,
                            and user TCC evidence.
  plan                      Print current phases and blocked privileged work.
  print-operator-checklist  Print manual fresh-user/TCC rows.

Options:
  --host HOST                  SSH host alias or host name. Default: $DEFAULT_HOST
  --local                      Run checks on the current machine instead of SSH.
  --evidence-dir DIR           Output directory. Default: /tmp/foil-fresh-user-tcc-qa-<timestamp>
  --expected-hostname NAME     Expected hostname for preflight.
  --expected-bundle-id ID      Expected app bundle id. Default: $BUNDLE_ID
  --expected-arch ARCH         Expected host architecture.
  --expected-version VERSION   Expected /Applications app version for preflight.
  --expected-build BUILD       Expected /Applications app build for preflight.
  --expected-runner-name NAME  Expected GitHub Actions runner name for local workflow runs.

This phase is intentionally non-destructive. It does not create users, delete
users, install apps, replace /Applications/$APP_NAME.app, reset TCC, or grant
privacy permissions.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

allowed_host() {
  case "$1" in
    mm2|mac-mini-2|foil-mac-mini-2|Jeremys-Mac-mini-2.local|Jeremys-Mac-mini-2.local.)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

run_remote() {
  local command="$1"
  if [ "$LOCAL_MODE" -eq 1 ]; then
    bash -lc "$command"
  else
    "$SSH" -o BatchMode=yes -o AddressFamily=inet6 -o ConnectTimeout=10 "$HOST" "$command"
  fi
}

prepare_evidence_dir() {
  if [ -z "$EVIDENCE_DIR" ]; then
    EVIDENCE_DIR="/tmp/foil-fresh-user-tcc-qa-$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  mkdir -p "$EVIDENCE_DIR"
}

collect_host_facts() {
  run_remote 'set -e
echo "hostname=$(hostname)"
echo "local_hostname=$(scutil --get LocalHostName 2>/dev/null || true)"
echo "computer_name=$(scutil --get ComputerName 2>/dev/null || true)"
sw_vers | awk -F: "{value=\$2; gsub(/^[ \t]+|[ \t]+$/, \"\", value); print \"sw_vers.\"\$1\"=\"value}"
echo "arch=$(uname -m)"
echo "user=$(id -un)"
ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F\" "/IOPlatformUUID/{print \"hardware_uuid=\" \$4}" || true' \
    >"$EVIDENCE_DIR/host.txt"
}

collect_tooling_facts() {
  run_remote 'set -e
if command -v /opt/homebrew/bin/brew >/dev/null 2>&1; then /opt/homebrew/bin/brew --version | head -1 | sed "s/^/homebrew=/"; else echo "homebrew=missing"; fi
if command -v /opt/homebrew/bin/gh >/dev/null 2>&1; then /opt/homebrew/bin/gh --version | head -1 | sed "s/^/gh=/"; else echo "gh=missing"; fi
if command -v xcodebuild >/dev/null 2>&1; then xcodebuild -version | tr "\n" " " | sed "s/^/xcodebuild=/"; echo; else echo "xcodebuild=missing"; fi' \
    >"$EVIDENCE_DIR/tooling.txt"
}

collect_sudo_facts() {
  run_remote 'if sudo -n true >/dev/null 2>&1; then echo "sudo_noninteractive=yes"; else echo "sudo_noninteractive=no"; fi' \
    >"$EVIDENCE_DIR/sudo.txt"
}

collect_runner_facts() {
  run_remote 'set -e
echo "github_actions=${GITHUB_ACTIONS:-}"
echo "runner_name=${RUNNER_NAME:-}"
echo "runner_os=${RUNNER_OS:-}"
echo "runner_arch=${RUNNER_ARCH:-}"
echo "github_run_id=${GITHUB_RUN_ID:-}"
echo "github_ref=${GITHUB_REF:-}"
echo "github_sha=${GITHUB_SHA:-}"' \
    >"$EVIDENCE_DIR/runner.txt"
}

collect_app_facts() {
  local remote_app_path
  remote_app_path="$(printf '%s' "$APP_PATH" | sed "s/'/'\\\\''/g")"
  run_remote "set -e
app='$remote_app_path'
echo \"app_path=\$app\"
if [ -d \"\$app\" ]; then
  echo \"exists=yes\"
  $PLISTBUDDY -c 'Print :CFBundleIdentifier' \"\$app/Contents/Info.plist\" 2>/dev/null | sed 's/^/bundle_id=/' || echo 'bundle_id='
  $PLISTBUDDY -c 'Print :CFBundleShortVersionString' \"\$app/Contents/Info.plist\" 2>/dev/null | sed 's/^/short_version=/' || echo 'short_version='
  $PLISTBUDDY -c 'Print :CFBundleVersion' \"\$app/Contents/Info.plist\" 2>/dev/null | sed 's/^/build=/' || echo 'build='
else
  echo \"exists=no\"
fi" >"$EVIDENCE_DIR/app-identity.txt"
}

collect_diagnostics_facts() {
  run_remote 'set -e
echo "collected_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "console_user=$(stat -f %Su /dev/console 2>/dev/null || true)"
if pgrep -x Foil >/dev/null 2>&1; then
  echo "foil_running=yes"
  pgrep -x Foil | sed "s/^/pid=/"
  ps -axo pid,command | grep "/Applications/Foil.app/Contents/MacOS/Foil" | grep -v grep || true
else
  echo "foil_running=no"
fi' >"$EVIDENCE_DIR/process.txt"

  run_remote 'set -e
log="$HOME/Library/Application Support/Foil/Diagnostics/foil.log"
echo "log_path=$log"
if [ -f "$log" ]; then
  echo "log_exists=yes"
  echo "log_size=$(stat -f %z "$log" 2>/dev/null || true)"
  tail -120 "$log"
else
  echo "log_exists=no"
fi' >"$EVIDENCE_DIR/diagnostics-tail.txt"

  run_remote 'system_profiler SPAudioDataType 2>/dev/null | sed -n "1,220p" || true' \
    >"$EVIDENCE_DIR/audio-hardware.txt"

  run_remote 'set -e
db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
echo "db_path=$db"
if [ -f "$db" ]; then
  echo "db_exists=yes"
  sqlite3 "$db" "select service,client,auth_value,auth_reason,last_modified from access where client like '\''%Foil%'\'' or client='\''com.neonwatty.Foil'\'' order by service;" 2>/dev/null || true
else
  echo "db_exists=no"
fi' >"$EVIDENCE_DIR/tcc-readonly.txt"
}

write_operator_notes() {
  cat >"$EVIDENCE_DIR/operator-notes.md" <<'EOF'
# Fresh-User/TCC Operator Notes

These rows are not automated. Mark a row PASS only after a human operator
confirms the visible macOS consent/setup behavior in a disposable account or
managed lab account.

| Row ID | Scenario | Automation status | Result | Screenshot/evidence path | Notes |
| --- | --- | --- | --- | --- | --- |
| fresh-install | No prior Foil TCC, Keychain, defaults, diagnostics, or app data before first launch. | operator_confirmed | PENDING |  |  |
| accessibility-already-granted | Accessibility is already enabled before onboarding reaches the step. | operator_confirmed | PENDING |  |  |
| accessibility-grant-while-open | Accessibility starts disabled, then is granted while onboarding is open. | operator_confirmed | PENDING |  |  |
| microphone-prompt-grant | Microphone starts not determined, then the real macOS prompt is granted. | operator_confirmed | PENDING |  |  |
| microphone-already-granted | Microphone is authorized before onboarding reaches the step. | operator_confirmed | PENDING |  |  |
| permission-revoked-running | A ready permission is revoked while Foil is running, then restored. | operator_confirmed | PENDING |  |  |
| quit-relaunch-persistence | Ready setup state survives quit and relaunch. | operator_confirmed | PENDING |  |  |
EOF
}

value_for_key() {
  local file="$1"
  local key="$2"
  sed -n "s/^$key=//p" "$file" | head -1
}

write_summary() {
  local host_value local_hostname product_version arch_value app_exists app_bundle app_version app_build sudo_value runner_name
  host_value="$(value_for_key "$EVIDENCE_DIR/host.txt" "hostname")"
  local_hostname="$(value_for_key "$EVIDENCE_DIR/host.txt" "local_hostname")"
  product_version="$(value_for_key "$EVIDENCE_DIR/host.txt" "sw_vers.ProductVersion")"
  arch_value="$(value_for_key "$EVIDENCE_DIR/host.txt" "arch")"
  app_exists="$(value_for_key "$EVIDENCE_DIR/app-identity.txt" "exists")"
  app_bundle="$(value_for_key "$EVIDENCE_DIR/app-identity.txt" "bundle_id")"
  app_version="$(value_for_key "$EVIDENCE_DIR/app-identity.txt" "short_version")"
  app_build="$(value_for_key "$EVIDENCE_DIR/app-identity.txt" "build")"
  sudo_value="$(value_for_key "$EVIDENCE_DIR/sudo.txt" "sudo_noninteractive")"
  runner_name="$(value_for_key "$EVIDENCE_DIR/runner.txt" "runner_name")"

  cat >"$EVIDENCE_DIR/summary.txt" <<EOF
Foil Mac mini 2 fresh-user/TCC QA preflight
created_at=$(timestamp)
mode=$SUBCOMMAND
host_argument=$HOST
hostname=$host_value
local_hostname=$local_hostname
macos_version=$product_version
arch=$arch_value
app_path=$APP_PATH
app_exists=$app_exists
bundle_id=$app_bundle
app_version=$app_version
app_build=$app_build
sudo_noninteractive=$sudo_value
runner_name=$runner_name
manual_rows=operator_confirmed_required
destructive_steps=not_implemented
private_artifact_note=Evidence may include local usernames, hostnames, hardware UUIDs, paths, and screenshots added by an operator. Review before posting publicly.
EOF
}

write_manifest() {
  local host_value local_hostname computer_name product_version build_version arch_value user_value hardware_uuid app_exists app_bundle app_version app_build sudo_value homebrew_value gh_value xcodebuild_value runner_name github_actions github_run_id github_ref github_sha
  host_value="$(value_for_key "$EVIDENCE_DIR/host.txt" "hostname")"
  local_hostname="$(value_for_key "$EVIDENCE_DIR/host.txt" "local_hostname")"
  computer_name="$(value_for_key "$EVIDENCE_DIR/host.txt" "computer_name")"
  product_version="$(value_for_key "$EVIDENCE_DIR/host.txt" "sw_vers.ProductVersion")"
  build_version="$(value_for_key "$EVIDENCE_DIR/host.txt" "sw_vers.BuildVersion")"
  arch_value="$(value_for_key "$EVIDENCE_DIR/host.txt" "arch")"
  user_value="$(value_for_key "$EVIDENCE_DIR/host.txt" "user")"
  hardware_uuid="$(value_for_key "$EVIDENCE_DIR/host.txt" "hardware_uuid")"
  app_exists="$(value_for_key "$EVIDENCE_DIR/app-identity.txt" "exists")"
  app_bundle="$(value_for_key "$EVIDENCE_DIR/app-identity.txt" "bundle_id")"
  app_version="$(value_for_key "$EVIDENCE_DIR/app-identity.txt" "short_version")"
  app_build="$(value_for_key "$EVIDENCE_DIR/app-identity.txt" "build")"
  sudo_value="$(value_for_key "$EVIDENCE_DIR/sudo.txt" "sudo_noninteractive")"
  homebrew_value="$(value_for_key "$EVIDENCE_DIR/tooling.txt" "homebrew")"
  gh_value="$(value_for_key "$EVIDENCE_DIR/tooling.txt" "gh")"
  xcodebuild_value="$(value_for_key "$EVIDENCE_DIR/tooling.txt" "xcodebuild")"
  github_actions="$(value_for_key "$EVIDENCE_DIR/runner.txt" "github_actions")"
  runner_name="$(value_for_key "$EVIDENCE_DIR/runner.txt" "runner_name")"
  github_run_id="$(value_for_key "$EVIDENCE_DIR/runner.txt" "github_run_id")"
  github_ref="$(value_for_key "$EVIDENCE_DIR/runner.txt" "github_ref")"
  github_sha="$(value_for_key "$EVIDENCE_DIR/runner.txt" "github_sha")"
  cat >"$EVIDENCE_DIR/manifest.json" <<EOF
{
  "schema_version": 1,
  "run_id": "$(json_escape "$(basename "$EVIDENCE_DIR")")",
  "created_at": "$(timestamp)",
  "mode": "$(json_escape "$SUBCOMMAND")",
  "host_argument": "$(json_escape "$HOST")",
  "local_mode": $LOCAL_MODE,
  "hostname": "$(json_escape "$host_value")",
  "local_hostname": "$(json_escape "$local_hostname")",
  "computer_name": "$(json_escape "$computer_name")",
  "macos_version": "$(json_escape "$product_version")",
  "macos_build": "$(json_escape "$build_version")",
  "arch": "$(json_escape "$arch_value")",
  "user": "$(json_escape "$user_value")",
  "hardware_uuid": "$(json_escape "$hardware_uuid")",
  "app_path": "$(json_escape "$APP_PATH")",
  "app_exists": "$(json_escape "$app_exists")",
  "bundle_id": "$(json_escape "$app_bundle")",
  "app_version": "$(json_escape "$app_version")",
  "app_build": "$(json_escape "$app_build")",
  "sudo_noninteractive": "$(json_escape "$sudo_value")",
  "homebrew": "$(json_escape "$homebrew_value")",
  "gh": "$(json_escape "$gh_value")",
  "xcodebuild": "$(json_escape "$xcodebuild_value")",
  "github_actions": "$(json_escape "$github_actions")",
  "runner_name": "$(json_escape "$runner_name")",
  "github_run_id": "$(json_escape "$github_run_id")",
  "github_ref": "$(json_escape "$github_ref")",
  "github_sha": "$(json_escape "$github_sha")",
  "expected_hostname": "$(json_escape "$EXPECTED_HOSTNAME")",
  "expected_bundle_id": "$(json_escape "$EXPECTED_BUNDLE_ID")",
  "expected_arch": "$(json_escape "$EXPECTED_ARCH")",
  "expected_version": "$(json_escape "$EXPECTED_VERSION")",
  "expected_build": "$(json_escape "$EXPECTED_BUILD")",
  "manual_rows_status": "operator_confirmed_required",
  "destructive_steps": "not_implemented",
  "private_artifact_note": "Review before posting publicly: evidence may include local usernames, hostnames, hardware UUIDs, paths, and operator screenshots."
}
EOF
}

collect_evidence() {
  prepare_evidence_dir
  collect_host_facts
  collect_tooling_facts
  collect_sudo_facts
  collect_runner_facts
  collect_app_facts
  write_operator_notes
  write_summary
  write_manifest
  echo "Evidence: $EVIDENCE_DIR"
}

collect_diagnostics_evidence() {
  collect_evidence
  collect_diagnostics_facts
  echo "Diagnostics: $EVIDENCE_DIR"
}

expect_value() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(value_for_key "$file" "$key")"
  if [ "$actual" != "$expected" ]; then
    fail "expected $key '$expected' but found '${actual:-<empty>}' in $file"
  fi
}

run_preflight() {
  collect_evidence
  if [ -n "$EXPECTED_HOSTNAME" ]; then
    expect_value "$EVIDENCE_DIR/host.txt" "hostname" "$EXPECTED_HOSTNAME"
  fi
  if [ -n "$EXPECTED_BUNDLE_ID" ]; then
    expect_value "$EVIDENCE_DIR/app-identity.txt" "bundle_id" "$EXPECTED_BUNDLE_ID"
  fi
  if [ -n "$EXPECTED_ARCH" ]; then
    expect_value "$EVIDENCE_DIR/host.txt" "arch" "$EXPECTED_ARCH"
  fi
  if [ -n "$EXPECTED_VERSION" ]; then
    expect_value "$EVIDENCE_DIR/app-identity.txt" "short_version" "$EXPECTED_VERSION"
  fi
  if [ -n "$EXPECTED_BUILD" ]; then
    expect_value "$EVIDENCE_DIR/app-identity.txt" "build" "$EXPECTED_BUILD"
  fi
  if [ "$LOCAL_MODE" -eq 1 ] && [ -n "${GITHUB_ACTIONS:-}" ]; then
    expect_value "$EVIDENCE_DIR/runner.txt" "runner_name" "$EXPECTED_RUNNER_NAME"
  fi
  echo "Preflight passed."
}

print_plan() {
  cat <<'EOF'
Mac mini 2 fresh-user/TCC QA automation plan:

1. Non-destructive preflight and evidence collection.
2. Managed-lab lane for unattended checks with persistent or managed consent.
3. Operator-confirmed lane for real fresh Microphone consent prompts.
4. Later privileged user lifecycle only through a root-owned helper or audited
   narrow sudo path. Raw repo-writable root scripts are intentionally out of
   scope.
EOF
}

print_operator_checklist() {
  cat <<'EOF'
Fresh-user/TCC rows:

- fresh-install: operator_confirmed
- accessibility-already-granted: operator_confirmed
- accessibility-grant-while-open: operator_confirmed
- microphone-prompt-grant: operator_confirmed
- microphone-already-granted: operator_confirmed
- permission-revoked-running: operator_confirmed
- quit-relaunch-persistence: operator_confirmed

These rows must not be marked automated. PPPC/managed lab setup can provide
unattended already-granted coverage, but the real fresh Microphone prompt row
remains human-confirmed.
EOF
}

if [ -z "$SUBCOMMAND" ]; then
  usage >&2
  exit 2
fi
shift

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift
      ;;
    --local)
      LOCAL_MODE=1
      ;;
    --evidence-dir)
      EVIDENCE_DIR="${2:-}"
      shift
      ;;
    --expected-hostname)
      EXPECTED_HOSTNAME="${2:-}"
      shift
      ;;
    --expected-bundle-id)
      EXPECTED_BUNDLE_ID="${2:-}"
      shift
      ;;
    --expected-arch)
      EXPECTED_ARCH="${2:-}"
      shift
      ;;
    --expected-version)
      EXPECTED_VERSION="${2:-}"
      shift
      ;;
    --expected-build)
      EXPECTED_BUILD="${2:-}"
      shift
      ;;
    --expected-runner-name)
      EXPECTED_RUNNER_NAME="${2:-}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument '$1'"
      ;;
  esac
  shift
done

case "$SUBCOMMAND" in
  preflight|collect|collect-diagnostics)
    if [ "$LOCAL_MODE" -eq 0 ] && ! allowed_host "$HOST"; then
      fail "refusing to contact non-allowlisted host '$HOST'"
    fi
    if [ "$SUBCOMMAND" = "preflight" ]; then
      run_preflight
    elif [ "$SUBCOMMAND" = "collect" ]; then
      collect_evidence
    else
      collect_diagnostics_evidence
    fi
    ;;
  plan)
    print_plan
    ;;
  print-operator-checklist)
    print_operator_checklist
    ;;
  create-user|cleanup-user|verify-clean-user)
    fail "$SUBCOMMAND is intentionally blocked until a root-owned helper or audited narrow sudo path exists"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

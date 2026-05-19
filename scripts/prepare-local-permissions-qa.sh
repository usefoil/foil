#!/bin/bash
set -euo pipefail

APP_NAME="${APP_NAME:-GroqTalk}"
SCHEME="${SCHEME:-GroqTalk}"
CONFIG="${CONFIG:-Debug}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP_PATH="${APP_PATH:-$INSTALL_DIR/$APP_NAME.app}"

MAKE_CMD="${MAKE_CMD:-make}"
PLISTBUDDY="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"
CODESIGN="${CODESIGN:-codesign}"
PGREP="${PGREP:-pgrep}"
PKILL="${PKILL:-pkill}"
TCCUTIL="${TCCUTIL:-tccutil}"
OPEN_CMD="${OPEN_CMD:-open}"
SLEEP_CMD="${SLEEP_CMD:-sleep}"

MODE="run"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--check]

Modes:
  --check   Run non-mutating diagnostics for the installed app bundle.
  default   Ensure stable local signing, build, install, reset app-scoped TCC
            records, open macOS privacy panes, and launch the app for manual QA.

macOS privacy boundary:
  This script can verify bundle/signing preconditions and can reset this
  app's TCC records when run in default mode. It cannot and must not silently
  grant Accessibility, Input Monitoring, or Microphone consent.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)
      MODE="check"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

failures=0
warnings=0
bundle_id=""
bundle_executable=""

section() {
  echo "== $*"
}

pass() {
  echo "ok: $*"
}

warn() {
  warnings=$((warnings + 1))
  echo "warning: $*" >&2
}

fail() {
  failures=$((failures + 1))
  echo "error: $*" >&2
}

plist_value() {
  local key="$1"
  local plist="$2"
  "$PLISTBUDDY" -c "Print :$key" "$plist" 2>/dev/null || true
}

require_plist_value() {
  local key="$1"
  local plist="$2"
  local value
  value="$(plist_value "$key" "$plist")"
  if [ -z "$value" ]; then
    fail "missing Info.plist key '$key' in $plist"
    return 1
  fi
  printf '%s\n' "$value"
}

codesign_details() {
  "$CODESIGN" -dv --verbose=4 "$APP_PATH" 2>&1 || true
}

print_privacy_boundary() {
  cat <<EOF

Manual step still required by macOS:
1. Enable $APP_NAME in Accessibility.
2. Enable $APP_NAME in Input Monitoring if it appears there.
3. Enable Microphone access if macOS prompts for it.
4. Quit and reopen $APP_NAME.
5. Run Test Setup.

macOS does not allow scripts to silently grant Accessibility, Input Monitoring, or Microphone consent.
EOF
}

diagnose_installed_app() {
  section "Diagnose installed app identity"

  if [ ! -d "$APP_PATH" ]; then
    fail "expected installed app at $APP_PATH"
    return
  fi
  pass "installed app exists at $APP_PATH"

  local plist="$APP_PATH/Contents/Info.plist"
  if [ ! -f "$plist" ]; then
    fail "expected Info.plist at $plist"
    return
  fi
  pass "Info.plist exists"

  bundle_id="$(require_plist_value "CFBundleIdentifier" "$plist" || true)"
  if [ -n "$bundle_id" ]; then
    pass "bundle id is $bundle_id"
  fi

  bundle_executable="$(require_plist_value "CFBundleExecutable" "$plist" || true)"
  if [ -n "$bundle_executable" ]; then
    local executable="$APP_PATH/Contents/MacOS/$bundle_executable"
    if [ -x "$executable" ]; then
      pass "bundle executable exists and is executable: $executable"
    else
      fail "bundle executable is missing or not executable: $executable"
    fi
  fi

  local microphone_usage
  microphone_usage="$(plist_value "NSMicrophoneUsageDescription" "$plist")"
  if [ -n "$microphone_usage" ]; then
    pass "NSMicrophoneUsageDescription is present"
  else
    fail "missing NSMicrophoneUsageDescription; macOS may deny or omit microphone prompts"
  fi

  local details
  details="$(codesign_details)"
  if [ -z "$details" ]; then
    fail "codesign did not return details for $APP_PATH"
  else
    local signed_identifier
    signed_identifier="$(printf '%s\n' "$details" | sed -n 's/^Identifier=//p' | head -1)"
    if [ -z "$signed_identifier" ]; then
      fail "codesign details did not include an Identifier"
    elif [ -n "$bundle_id" ] && [ "$signed_identifier" != "$bundle_id" ]; then
      fail "signed identifier '$signed_identifier' does not match bundle id '$bundle_id'"
    else
      pass "codesign identifier matches bundle id: $signed_identifier"
    fi

    local authority
    authority="$(printf '%s\n' "$details" | sed -n 's/^Authority=//p' | paste -sd ', ' -)"
    local team_identifier
    team_identifier="$(printf '%s\n' "$details" | sed -n 's/^TeamIdentifier=//p' | head -1)"
    if [ -n "$authority" ]; then
      pass "codesign authority: $authority"
    else
      warn "codesign authority is absent; ad-hoc signing can make TCC permissions appear enabled for a different app identity"
    fi
    if [ -n "$team_identifier" ] && [ "$team_identifier" != "not set" ]; then
      pass "codesign team identifier: $team_identifier"
    else
      warn "codesign team identifier is absent; TCC rows can differ from Developer ID builds"
    fi
  fi

  if "$PGREP" -x "$APP_NAME" >/dev/null 2>&1; then
    warn "$APP_NAME is currently running; quit and reopen after changing privacy toggles"
  else
    pass "$APP_NAME is not currently running"
  fi

  section "Privacy consent boundary"
  echo "Accessibility, Input Monitoring, and Microphone grants remain user-controlled in System Settings."
  echo "This script does not write TCC databases, install MDM/PPPC profiles, or silently grant privacy permissions."
}

if [ "$MODE" = "check" ]; then
  section "Non-mutating local permissions QA check"
  diagnose_installed_app
  print_privacy_boundary
  if [ "$failures" -gt 0 ]; then
    echo
    echo "Result: failed with $failures error(s) and $warnings warning(s)."
    exit 1
  fi
  echo
  echo "Result: passed with $warnings warning(s)."
  exit 0
fi

section "Stop running app"
"$PKILL" -x "$APP_NAME" 2>/dev/null || true
"$SLEEP_CMD" 0.5

section "Ensure stable local signing identity"
"$MAKE_CMD" setup-local-signing

section "Build and install local app"
"$MAKE_CMD" install CONFIG="$CONFIG"

if [ ! -d "$APP_PATH" ]; then
  echo "error: expected installed app at $APP_PATH" >&2
  exit 1
fi

diagnose_installed_app
if [ "$failures" -gt 0 ]; then
  echo
  echo "Result: failed with $failures diagnostic error(s); not resetting privacy records." >&2
  exit 1
fi

section "Reset macOS privacy records for this app identity"
echo "This clears Accessibility and Input Monitoring rows for $bundle_id only; it does not grant consent."
"$TCCUTIL" reset Accessibility "$bundle_id" || true
"$TCCUTIL" reset ListenEvent "$bundle_id" || true

section "Open Privacy & Security panes"
"$OPEN_CMD" "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
"$SLEEP_CMD" 0.8
"$OPEN_CMD" "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

section "Launch app"
"$OPEN_CMD" "$APP_PATH"
"$SLEEP_CMD" 1.5

if "$PGREP" -x "$APP_NAME" >/dev/null 2>&1; then
  echo "$APP_NAME launched."
else
  warn "$APP_NAME did not appear in the process list."
fi

print_privacy_boundary

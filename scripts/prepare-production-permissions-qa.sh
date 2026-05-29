#!/bin/bash
set -euo pipefail

APP_NAME="${APP_NAME:-Foil}"
BUNDLE_ID="${BUNDLE_ID:-com.neonwatty.Foil}"
APP_PATH="${APP_PATH:-/Applications/$APP_NAME.app}"
TAP="${TAP:-mean-weasel/foil}"
TAP_URL="${TAP_URL:-https://github.com/mean-weasel/homebrew-foil}"
CASK="${CASK:-mean-weasel/foil/foil}"
REPO="${REPO:-mean-weasel/foil}"
TEMP_APP_DIR="${TEMP_APP_DIR:-/tmp/foil-release-apps}"
REQUIRED_COMMIT="${REQUIRED_COMMIT:-}"

BREW="${BREW:-brew}"
GH="${GH:-gh}"
GIT="${GIT:-git}"
PLISTBUDDY="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"
SPCTL="${SPCTL:-spctl}"
CODESIGN="${CODESIGN:-codesign}"
OPEN_CMD="${OPEN_CMD:-open}"
PGREP="${PGREP:-pgrep}"
PS_CMD="${PS_CMD:-ps}"
SLEEP_CMD="${SLEEP_CMD:-sleep}"

MODE="check-cask"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--check-cask|--guide-applications|--evidence-template]

Modes:
  --check-cask
            Tap the public Homebrew repo, install the cask into TEMP_APP_DIR,
            and verify bundle identity, Gatekeeper notarization, and codesign.
            This does not touch /Applications.
  --guide-applications
            Verify the production app already installed at APP_PATH, launch it,
            open the privacy panes, and print the manual permission checklist.
            Install or reinstall the public cask into /Applications separately.
  --evidence-template
            Print a GitHub/release-log evidence template for the production
            setup-permission smoke.

Environment:
  REQUIRED_COMMIT   Optional commit that the latest release tag must contain.
  TEMP_APP_DIR      Temporary appdir for --check-cask. Default: /tmp/foil-release-apps
  REPO              GitHub repo for release lookup. Default: mean-weasel/foil
  CASK              Homebrew cask token. Default: mean-weasel/foil/foil
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-cask)
      MODE="check-cask"
      ;;
    --guide-applications)
      MODE="guide-applications"
      ;;
    --evidence-template)
      MODE="evidence-template"
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

latest_release_tag() {
  "$GH" release view --repo "$REPO" --json tagName --jq '.tagName'
}

print_latest_release() {
  section "Latest GitHub release"
  if ! "$GH" release view --repo "$REPO" --json tagName,publishedAt,targetCommitish,url; then
    fail "could not read latest release for $REPO"
  fi
}

verify_required_commit() {
  if [ -z "$REQUIRED_COMMIT" ]; then
    return
  fi

  section "Required commit inclusion"
  local tag
  tag="$(latest_release_tag || true)"
  if [ -z "$tag" ]; then
    fail "could not determine latest release tag for required commit check"
    return
  fi

  "$GIT" fetch --tags origin "$tag" >/dev/null 2>&1 || true
  if "$GIT" merge-base --is-ancestor "$REQUIRED_COMMIT" "$tag" 2>/dev/null; then
    pass "latest release $tag contains required commit $REQUIRED_COMMIT"
  else
    fail "latest release $tag does not contain required commit $REQUIRED_COMMIT"
  fi
}

verify_app_bundle() {
  local app_path="$1"
  local require_notarized="$2"

  section "Verify app bundle: $app_path"
  if [ ! -d "$app_path" ]; then
    fail "expected app at $app_path"
    return
  fi
  pass "app exists"

  local plist="$app_path/Contents/Info.plist"
  if [ ! -f "$plist" ]; then
    fail "missing Info.plist"
    return
  fi

  local bundle_id short_version build_version microphone_usage executable
  bundle_id="$(plist_value CFBundleIdentifier "$plist")"
  short_version="$(plist_value CFBundleShortVersionString "$plist")"
  build_version="$(plist_value CFBundleVersion "$plist")"
  microphone_usage="$(plist_value NSMicrophoneUsageDescription "$plist")"
  executable="$(plist_value CFBundleExecutable "$plist")"

  if [ "$bundle_id" = "$BUNDLE_ID" ]; then
    pass "bundle id is $bundle_id"
  else
    fail "bundle id is '$bundle_id', expected '$BUNDLE_ID'"
  fi

  [ -n "$short_version" ] && pass "bundle version is $short_version" || fail "missing bundle version"
  [ -n "$build_version" ] && pass "bundle build is $build_version" || fail "missing bundle build"
  [ -n "$microphone_usage" ] && pass "NSMicrophoneUsageDescription is present" || fail "missing NSMicrophoneUsageDescription"

  if [ -n "$executable" ] && [ -x "$app_path/Contents/MacOS/$executable" ]; then
    pass "bundle executable exists and is executable: $app_path/Contents/MacOS/$executable"
  else
    fail "bundle executable is missing or not executable"
  fi

  local codesign_output
  codesign_output="$("$CODESIGN" -dv --verbose=4 "$app_path" 2>&1 || true)"
  local signed_identifier authority team_identifier
  signed_identifier="$(printf '%s\n' "$codesign_output" | sed -n 's/^Identifier=//p' | head -1)"
  authority="$(printf '%s\n' "$codesign_output" | sed -n 's/^Authority=//p' | paste -sd ', ' -)"
  team_identifier="$(printf '%s\n' "$codesign_output" | sed -n 's/^TeamIdentifier=//p' | head -1)"

  if [ "$signed_identifier" = "$BUNDLE_ID" ]; then
    pass "codesign identifier matches bundle id: $signed_identifier"
  else
    fail "signed identifier is '$signed_identifier', expected '$BUNDLE_ID'"
  fi

  if printf '%s\n' "$authority" | grep -Fq "Developer ID Application"; then
    pass "codesign authority includes Developer ID Application: $authority"
  else
    fail "codesign authority does not include Developer ID Application: $authority"
  fi

  if [ -n "$team_identifier" ] && [ "$team_identifier" != "not set" ]; then
    pass "codesign team identifier: $team_identifier"
  else
    fail "codesign team identifier is absent"
  fi

  section "Gatekeeper and deep codesign"
  local spctl_output codesign_verify_output
  spctl_output="$("$SPCTL" -a -vv -t execute "$app_path" 2>&1 || true)"
  printf '%s\n' "$spctl_output"
  if printf '%s\n' "$spctl_output" | grep -Fq "accepted"; then
    pass "Gatekeeper accepted app"
  else
    fail "Gatekeeper did not accept app"
  fi
  if [ "$require_notarized" = "yes" ]; then
    if printf '%s\n' "$spctl_output" | grep -Fq "Notarized Developer ID"; then
      pass "Gatekeeper source is Notarized Developer ID"
    else
      fail "Gatekeeper source is not Notarized Developer ID"
    fi
  fi

  codesign_verify_output="$("$CODESIGN" --verify --deep --strict --verbose=2 "$app_path" 2>&1 || true)"
  printf '%s\n' "$codesign_verify_output"
  if printf '%s\n' "$codesign_verify_output" | grep -Fq "valid on disk" &&
    printf '%s\n' "$codesign_verify_output" | grep -Fq "satisfies its Designated Requirement"; then
    pass "deep strict codesign verification passed"
  else
    fail "deep strict codesign verification did not pass"
  fi
}

running_app_paths() {
  local pids
  pids="$("$PGREP" -x "$APP_NAME" 2>/dev/null || true)"
  [ -n "$pids" ] || return 0

  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    "$PS_CMD" -p "$pid" -o args= 2>/dev/null || true
  done <<<"$pids"
}

open_privacy_panes() {
  section "Open Privacy & Security panes"
  "$OPEN_CMD" "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  "$SLEEP_CMD" 0.8
  "$OPEN_CMD" "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
  "$SLEEP_CMD" 0.8
  "$OPEN_CMD" "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
}

print_manual_checklist() {
  cat <<EOF

Manual production setup-permission checklist:
1. Confirm /Applications/$APP_NAME.app is the active app.
2. Remove stale $APP_NAME privacy rows only if this is an approved disposable/fresh QA environment.
3. Launch $APP_NAME and confirm first-run setup or Settings setup is visible.
4. Grant Accessibility for /Applications/$APP_NAME.app.
5. Grant Input Monitoring if macOS presents that row.
6. Trigger the in-app Microphone action and allow the macOS prompt.
7. Confirm diagnostics show:
   - SetupHealth: accessibilityTrusted=true
   - MicrophonePermission: requestAccess granted=true
   - SetupHealth: microphone=authorized
8. Quit and relaunch /Applications/$APP_NAME.app.
9. Confirm diagnostics still show Accessibility trusted and Microphone authorized.

Record all PASS/FAIL results, exact diagnostics, and any visible setup text in docs/release-qa-log.md or the release tracking issue.
EOF
}

print_evidence_template() {
  cat <<'EOF'
## Production setup-permission smoke

- Date:
- Tester:
- Machine/account type:
- macOS version/build:
- Architecture:
- Artifact:
- Required commit included:
- Install method:
- Installed app path:
- Bundle id:
- Version/build:
- Gatekeeper result:
- Codesign result:
- Active process path:
- Accessibility grant while setup is open: PASS/FAIL
- Accessibility diagnostics:
- Microphone prompt appeared from in-app action: PASS/FAIL
- Microphone grant result: PASS/FAIL
- Microphone diagnostics:
- Quit/relaunch persistence: PASS/FAIL
- Provider/API setup path:
- Final setup state / Get Started state:
- Friction observed:
- Follow-up issues:
EOF
}

run_check_cask() {
  print_latest_release
  verify_required_commit

  section "Homebrew public cask"
  "$BREW" tap "$TAP" "$TAP_URL"
  "$BREW" info --cask "$CASK"

  section "Temporary cask install"
  rm -rf "$TEMP_APP_DIR"
  mkdir -p "$TEMP_APP_DIR"
  "$BREW" install --cask --appdir="$TEMP_APP_DIR" "$CASK"
  verify_app_bundle "$TEMP_APP_DIR/$APP_NAME.app" yes

  section "Next step"
  echo "Install the same cask into /Applications, then run:"
  echo "  make guide-production-permissions-qa"
}

run_guide_applications() {
  verify_app_bundle "$APP_PATH" yes

  section "Launch app"
  "$OPEN_CMD" "$APP_PATH"
  "$SLEEP_CMD" 1.5

  local paths
  paths="$(running_app_paths)"
  if printf '%s\n' "$paths" | grep -Fxq "$APP_PATH/Contents/MacOS/$APP_NAME"; then
    pass "active process path is $APP_PATH/Contents/MacOS/$APP_NAME"
  else
    fail "active process path is not the production app. Running paths: ${paths:-none}"
  fi

  open_privacy_panes
  print_manual_checklist
}

case "$MODE" in
  check-cask)
    run_check_cask
    ;;
  guide-applications)
    run_guide_applications
    ;;
  evidence-template)
    print_evidence_template
    ;;
esac

if [ "$failures" -gt 0 ]; then
  echo
  echo "Result: failed with $failures error(s) and $warnings warning(s)." >&2
  exit 1
fi

echo
echo "Result: passed with $warnings warning(s)."

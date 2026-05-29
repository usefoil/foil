#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLAVOR="${FOIL_RUN_FLAVOR:-dev}"

case "$FLAVOR" in
  dev)
    APP_NAME="Foil Dev"
    BUNDLE_ID="com.neonwatty.Foil.Dev"
    INSTALL_TARGET="install-dev"
    ;;
  prod|production)
    APP_NAME="Foil"
    BUNDLE_ID="com.neonwatty.Foil"
    INSTALL_TARGET="install"
    ;;
  *)
    echo "FOIL_RUN_FLAVOR must be 'dev' or 'prod'" >&2
    exit 2
    ;;
esac

APP_PATH="/Applications/${APP_NAME}.app"

cd "$ROOT_DIR"

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n "$APP_PATH"
}

case "$MODE" in
  run)
    stop_app
    make setup-local-signing
    make "$INSTALL_TARGET"
    open_app
    ;;
  --debug|debug)
    stop_app
    make setup-local-signing
    make "$INSTALL_TARGET"
    lldb -- "$APP_PATH/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    stop_app
    make setup-local-signing
    make "$INSTALL_TARGET"
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_app
    make setup-local-signing
    make "$INSTALL_TARGET"
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stop_app
    make setup-local-signing
    make "$INSTALL_TARGET"
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    echo "set FOIL_RUN_FLAVOR=prod to run the production flavor" >&2
    exit 2
    ;;
esac

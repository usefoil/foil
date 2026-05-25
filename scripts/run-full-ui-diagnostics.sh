#!/usr/bin/env bash
set -euo pipefail

SCHEME="${SCHEME:-Foil}"
CONFIG="${CONFIG:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-FullUITestResults.xcresult}"
LOG_PATH="${LOG_PATH:-full-ui-diagnostics.log}"
GRACE_SECONDS="${GRACE_SECONDS:-60}"
TIMEOUT_SECONDS="${FULL_UI_TIMEOUT_SECONDS:-1200}"

rm -rf "$RESULT_BUNDLE_PATH"
rm -f "$LOG_PATH"

pkill -x Foil 2>/dev/null || true
sleep 0.5

echo "Running full Foil UI diagnostics."
echo "Result bundle: $RESULT_BUNDLE_PATH"
echo "Log: $LOG_PATH"
echo "Timeout: ${TIMEOUT_SECONDS}s, grace: ${GRACE_SECONDS}s"

xcodebuild test \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "$DESTINATION" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-device-destinations 1 \
  -enableCodeCoverage NO \
  -only-testing:FoilUITests \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  > "$LOG_PATH" 2>&1 &
XCODE_PID=$!

(
  sleep "$TIMEOUT_SECONDS"
  kill -TERM "$XCODE_PID" 2>/dev/null || true
  sleep "$GRACE_SECONDS"
  kill -KILL "$XCODE_PID" 2>/dev/null || true
) &
WATCHDOG_PID=$!

set +e
wait "$XCODE_PID" 2>/dev/null
TEST_EXIT=$?
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null
set -e

echo "xcodebuild exit: $TEST_EXIT"
tail -120 "$LOG_PATH" || true

if [ -d "$RESULT_BUNDLE_PATH" ]; then
  echo "Full UI diagnostics result bundle captured at $RESULT_BUNDLE_PATH."
  if xcrun xcresulttool get test-results summary \
    --path "$RESULT_BUNDLE_PATH" \
    --compact > full-ui-summary.json 2>/dev/null; then
    echo "Summary captured at full-ui-summary.json."
    if grep -q '"result" : "Failed"' full-ui-summary.json; then
      echo "Full UI diagnostics found failing tests."
      exit 1
    fi
  else
    echo "Could not parse full UI diagnostics summary."
  fi
else
  echo "No full UI diagnostics result bundle was produced."
fi

exit "$TEST_EXIT"

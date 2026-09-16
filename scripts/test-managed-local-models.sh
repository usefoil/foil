#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scenario= app= state_root=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) scenario="$2"; shift 2 ;;
    --app) app="$2"; shift 2 ;;
    --state-root) state_root="$2"; shift 2 ;;
    *) echo 'Unknown argument' >&2; exit 2 ;;
  esac
done
[[ "$scenario" == clean-install-switch || "$scenario" == offline-relaunch ]]
[[ -x "$app/Contents/Helpers/whisper-server" && "$state_root" == /tmp/foil-397-t003-model-acceptance ]]
result="/tmp/foil-397-t003-model-${scenario}-$(date +%s).xcresult"
TEST_RUNNER_FOIL_MODELS_SCENARIO="$scenario" \
TEST_RUNNER_FOIL_MODELS_STATE_ROOT="$state_root" \
TEST_RUNNER_FOIL_MODELS_APP="$app" \
RUN_LIVE_GROQ_TESTS=0 RUN_LIVE_MICROPHONE_TESTS=0 \
xcodebuild test -scheme Foil -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FoilTests/ManagedLocalModelAcceptanceTests \
  -resultBundlePath "$result" CODE_SIGN_IDENTITY='Foil Local Code Signing' \
  CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=NO
[[ -s "$state_root/receipt-$scenario.json" ]]
echo "Acceptance receipt: $state_root/receipt-$scenario.json"

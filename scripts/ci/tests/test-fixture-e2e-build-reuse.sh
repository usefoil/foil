#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT

mkdir -p "${fixture_root}/bin"
touch "${fixture_root}/Foil.xctestrun"
log_path="${fixture_root}/xcodebuild.log"

cat >"${fixture_root}/bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${XCODEBUILD_LOG_PATH}"
if [[ "$1" == "test-without-building" ]]; then
  echo "Test skipped"
fi
EOF
chmod +x "${fixture_root}/bin/xcodebuild"

cat >"${fixture_root}/bin/PlistBuddy" <<'EOF'
#!/usr/bin/env bash
if [[ "$2" == *":TestTargets:0:BlueprintName" ]]; then
  echo "FoilUITests"
fi
EOF
chmod +x "${fixture_root}/bin/PlistBuddy"

set +e
SKIP_BUILD_FOR_TESTING=1 \
XCTESTRUN_PATH="${fixture_root}/Foil.xctestrun" \
XCTEST_RESULT_BUNDLE_PATH="${fixture_root}/fixture.xcresult" \
XCODEBUILD_LOG_PATH="${log_path}" \
PLISTBUDDY="${fixture_root}/bin/PlistBuddy" \
PATH="${fixture_root}/bin:${PATH}" \
bash "${repo_root}/scripts/run-fixture-transcription-e2e-xcuitest.sh"
status=$?
set -e

if [[ "${status}" -eq 0 ]]; then
  echo "expected the fake XCUITest to fail after reporting a skipped test" >&2
  exit 1
fi

if ! grep -qx 'test-without-building -xctestrun .* -destination .* -only-testing:FoilUITests/FoilUITests/testE2ETranscription -resultBundlePath .*' "${log_path}"; then
  echo "expected test-without-building to use the supplied xctestrun and result bundle" >&2
  cat "${log_path}" >&2
  exit 1
fi

if grep -q 'build-for-testing' "${log_path}"; then
  echo "did not expect build-for-testing when reusing a supplied xctestrun" >&2
  cat "${log_path}" >&2
  exit 1
fi

echo "fixture E2E build-reuse contract passed"

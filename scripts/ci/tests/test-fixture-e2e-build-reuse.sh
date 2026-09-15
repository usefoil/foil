#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT

mkdir -p "${fixture_root}/bin"
touch "${fixture_root}/Foil.xctestrun"
log_path="${fixture_root}/xcodebuild.log"
artifact_dir="${fixture_root}/attempt-artifacts"
base_url_path="${fixture_root}/base-url"

cat >"${fixture_root}/bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${XCODEBUILD_LOG_PATH}"
if [[ "$1" == "test-without-building" ]]; then
  curl -fsS \
    -H 'Authorization: Bearer local-fixture' \
    -F 'model=whisper-1' \
    -F 'file=@Foil/e2e-test-audio.wav;type=audio/wav' \
    "$(<"${FAKE_BASE_URL_PATH}")/audio/transcriptions" >/dev/null
  echo "Test skipped"
fi
EOF
chmod +x "${fixture_root}/bin/xcodebuild"

cat >"${fixture_root}/bin/PlistBuddy" <<'EOF'
#!/usr/bin/env bash
if [[ "$2" == *":TestTargets:0:BlueprintName" ]]; then
  echo "FoilUITests"
fi
if [[ "$2" == *":E2E_TRANSCRIPTION_BASE_URL string "* ]]; then
  printf '%s\n' "${2##* string }" >"${FAKE_BASE_URL_PATH}"
fi
EOF
chmod +x "${fixture_root}/bin/PlistBuddy"

set +e
SKIP_BUILD_FOR_TESTING=1 \
XCTESTRUN_PATH="${fixture_root}/Foil.xctestrun" \
XCTEST_RESULT_BUNDLE_PATH="${fixture_root}/fixture.xcresult" \
XCTEST_ARTIFACT_DIR="${artifact_dir}" \
XCODEBUILD_LOG_PATH="${log_path}" \
FAKE_BASE_URL_PATH="${base_url_path}" \
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

for artifact in fixture-request-receipt.json fixture-server.log xcuitest.log; do
  if [[ ! -s "${artifact_dir}/${artifact}" ]]; then
    echo "expected retained failure diagnostic: ${artifact}" >&2
    exit 1
  fi
done
if ! grep -Fqx '  "authorization": "Bearer [REDACTED]",' "${artifact_dir}/fixture-request-receipt.json" || grep -Fq 'local-fixture' "${artifact_dir}/fixture-request-receipt.json"; then
  echo "expected exported fixture receipt to redact authorization" >&2
  exit 1
fi

echo "fixture E2E build-reuse contract passed"

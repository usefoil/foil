#!/usr/bin/env bash
set -euo pipefail

repository_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repository_root"

python3 -m json.tool Foil/Resources/AgentAccessOpenAPI.json >/dev/null

result_bundle="${AGENT_ACCESS_RESULT_BUNDLE:-}"
result_arguments=()
if [[ -n "$result_bundle" ]]; then
  if [[ -e "$result_bundle" ]]; then
    echo "error: AGENT_ACCESS_RESULT_BUNDLE already exists: $result_bundle" >&2
    exit 2
  fi
  result_arguments=(-resultBundlePath "$result_bundle")
fi

RUN_LIVE_GROQ_TESTS=0 xcodebuild test \
  -scheme "${SCHEME:-Foil}" \
  -configuration "${CONFIG:-Debug}" \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-device-destinations 1 \
  -enableCodeCoverage NO \
  "${result_arguments[@]}" \
  -only-testing:FoilTests/AgentAccessContractTests \
  -only-testing:FoilTests/AgentAccessControllerTests \
  -only-testing:FoilTests/AgentAccessHTTPTests \
  -only-testing:FoilTests/AgentAccessServerTests \
  -only-testing:FoilTests/VocabularyCatalogStoreTests \
  -only-testing:FoilTests/VocabularyProposalContractTests \
  -only-testing:FoilTests/VocabularyProposalServiceTests \
  -only-testing:FoilTests/VocabularyProposalStoreTests \
  -only-testing:FoilTests/TranscriptionControllerTests/testReviewedAgentAliasesCorrectExactDictationAndHistoryKeepsOriginal

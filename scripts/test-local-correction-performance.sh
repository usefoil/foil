#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
workloads="/tmp/foil-local-correction-benchmark-workloads.json"
configuration="/tmp/foil-local-correction-benchmark-configuration.json"
report="${LOCAL_CORRECTION_BENCHMARK_REPORT:-$(mktemp -t foil-local-correction-performance).json}"
code_signing_allowed="${FOIL_PERFORMANCE_CODE_SIGNING_ALLOWED:-NO}"
derived_data_path="${FOIL_PERFORMANCE_DERIVED_DATA_PATH:-}"
commit="$(git -C "$repo_root" rev-parse HEAD)"
if [[ "$report" != /* ]]; then
    report="$repo_root/$report"
fi
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    commit="${commit}+dirty"
fi

cleanup() {
    rm -f "$workloads" "$configuration"
}
trap cleanup EXIT

if [[ "$code_signing_allowed" != YES && "$code_signing_allowed" != NO ]]; then
    echo "FOIL_PERFORMANCE_CODE_SIGNING_ALLOWED must be YES or NO" >&2
    exit 2
fi

python3 "$repo_root/tests/local_corrections_harness.py" \
    --write-benchmark-workloads "$workloads"

python3 - "$configuration" "$report" "$commit" <<'PY'
import json
import sys

path, report, commit = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({
        "report_path": report,
        "commit": commit,
        "build_configuration": "Release",
    }, handle)
PY

xcodebuild_arguments=(test \
    -quiet \
    -project "$repo_root/Foil.xcodeproj" \
    -scheme Foil \
    -configuration Release \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED="$code_signing_allowed" \
    ENABLE_TESTABILITY=YES \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG \
    -only-testing:FoilTests/TranscriptionControllerTests/testLocalCorrectionReleasePerformanceGate)
if [[ -n "$derived_data_path" ]]; then
    xcodebuild_arguments+=(-derivedDataPath "$derived_data_path")
fi
xcodebuild "${xcodebuild_arguments[@]}"

python3 "$repo_root/tests/local_corrections_harness.py" \
    --benchmark-report "$report"

echo "Performance report: $report"

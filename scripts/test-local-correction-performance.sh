#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
workloads="/tmp/foil-local-correction-benchmark-workloads.json"
configuration="/tmp/foil-local-correction-benchmark-configuration.json"
report="${LOCAL_CORRECTION_BENCHMARK_REPORT:-$(mktemp -t foil-local-correction-performance).json}"
commit="$(git -C "$repo_root" rev-parse HEAD)"
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    commit="${commit}+dirty"
fi

cleanup() {
    rm -f "$workloads" "$configuration"
}
trap cleanup EXIT

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

xcodebuild test \
    -quiet \
    -project "$repo_root/Foil.xcodeproj" \
    -scheme Foil \
    -configuration Release \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_TESTABILITY=YES \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG \
    -only-testing:FoilTests/TranscriptionControllerTests/testLocalCorrectionReleasePerformanceGate

python3 "$repo_root/tests/local_corrections_harness.py" \
    --benchmark-report "$report"

echo "Performance report: $report"

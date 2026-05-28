## T010 Worker Result

Result: done

Implemented a bounded product fix in `Foil/BackgroundPaste.swift`: direct AX selected-text insertion now reads the editable value before and after the set operation, and only returns Tier 1 `.verified` when the value changed and contains the inserted text. If an app reports AX success without mutation, Foil logs that condition and falls through to the existing choreography path.

Also updated `tests/test_queued_paste_compatibility.swift` so the Chrome verifier selects the intended test page window and checks all text controls under that window.

Verification:

- `swiftc -parse tests/test_queued_paste_compatibility.swift`: pass
- `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:FoilTests/BackgroundPasteTests`: pass, 14 tests
- `make prepare-local-permissions-qa-check`: pass with local-signing warning
- `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility`: pass
- Artifact: `/tmp/foil-queued-paste-compatibility-20260528-081907`
- xcresult: `Test-Foil-2026.05.28_08-18-35--0700.xcresult`

Smoke result:

- TextEdit queued delivery: pass, `TextEdit pid=57807`, title `FoilQueuedTextEditTarget.txt`
- Chrome queued delivery: pass, `Google Chrome pid=76811`, title `Foil Queued Chrome Target - Google Chrome - Jeremy`
- Unavailable target fallback: pass, clipboard fallback verified

Diagnostics showed `SetupHealth: accessibilityTrusted=true`. During Chrome delivery, direct AX selected-text insertion reported success but did not mutate the value, so Foil rejected Tier 1 verification, fell through to Tier 2 choreography, and delivered via `original app command posted`.

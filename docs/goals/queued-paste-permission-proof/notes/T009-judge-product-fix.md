## T009 Judge Decision

Decision: product_fix_required

The T008 harness fix made Chrome readback specific and observable. The rerun still failed with trusted Accessibility and showed the Chrome textarea value did not contain the queued transcript. Foil diagnostics simultaneously claimed `BackgroundPaste: AX insertion succeeded for Google Chrome` and `insertAsync: Tier 1 (AX) verified for Google Chrome`.

That is a product correctness bug: a successful `AXUIElementSetAttributeValue(..., AXSelectedText, ...)` call is not sufficient proof that browser text changed. The fix should make Tier 1 AX insertion verify the target editable element's value actually changed before returning `.verified`; if verification fails, Foil should fall through to the existing choreography/clipboard paste path.

Approved Worker:

- Objective: make direct AX background paste verify text mutation before claiming `.asyncBackground`, then rerun the trusted queued-paste smoke and update QA evidence.
- Allowed files:
  - `Foil/BackgroundPaste.swift`
  - `FoilTests/BackgroundPasteTests.swift`
  - `tests/test_queued_paste_compatibility.swift`
  - `docs/queued-paste-compatibility-smoke.md`
  - `docs/release-qa-log.md`
  - `docs/goals/queued-paste-permission-proof/state.yaml`
  - `docs/goals/queued-paste-permission-proof/notes/*`
- Verify:
  - `swiftc -parse tests/test_queued_paste_compatibility.swift`
  - `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:FoilTests/BackgroundPasteTests`
  - `make prepare-local-permissions-qa-check`
  - `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility`
  - `git diff --check`
  - `node /Users/jeremywatt/.codex/plugins/cache/goalbuddy/goalbuddy/0.3.7/skills/goalbuddy/scripts/check-goal-state.mjs docs/goals/queued-paste-permission-proof/state.yaml`

Stop if the product fix would require browser-specific scripting, closing tabs, a global hotkey architecture, or mutating persistent browser data.

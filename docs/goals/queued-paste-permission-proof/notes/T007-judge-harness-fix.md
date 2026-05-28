## T007 Judge Decision

Decision: harness_fix_required

`T006` produced trusted-app evidence: Foil diagnostics now show `SetupHealth: accessibilityTrusted=true`, and the Chrome queued delivery path logged AX insertion success plus `delivery=original app`. The smoke command still failed because the Chrome verifier did not observe the queued text in the target window.

The current verifier reads the first `AXTextArea` or `AXTextField` found under the Chrome window. In Chrome, that can be the wrong accessibility node or stale page field even when Foil inserted into the focused textarea. The largest safe next slice is to make the smoke harness select the intended Chrome window and verify across relevant text controls, then rerun the exact queued-paste compatibility smoke.

Approved Worker:

- Objective: make Chrome readback in `tests/test_queued_paste_compatibility.swift` robust without closing Chrome tabs or mutating browser state, then update QA evidence.
- Allowed files:
  - `tests/test_queued_paste_compatibility.swift`
  - `docs/queued-paste-compatibility-smoke.md`
  - `docs/release-qa-log.md`
  - `docs/goals/queued-paste-permission-proof/state.yaml`
  - `docs/goals/queued-paste-permission-proof/notes/*`
- Verify:
  - `swiftc -parse tests/test_queued_paste_compatibility.swift`
  - `make prepare-local-permissions-qa-check`
  - `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility`
  - `git diff --check`
  - `node /Users/jeremywatt/.codex/plugins/cache/goalbuddy/goalbuddy/0.3.7/skills/goalbuddy/scripts/check-goal-state.mjs docs/goals/queued-paste-permission-proof/state.yaml`

Stop if the rerun shows Foil diagnostics with `accessibilityTrusted=true` and product delivery failure after the harness fix, because that would require a separate product-fix Worker.

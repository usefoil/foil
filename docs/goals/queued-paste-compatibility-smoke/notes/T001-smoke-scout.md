# T001 Smoke Scout

## Summary

Queued paste stores a captured paste target, not just a screen location. `PasteTarget` carries `pid`, `appName`, optional Accessibility window element, and optional SkyLight `windowID`; `PasteTarget.captureCurrentTarget()` captures the current frontmost app/window. The existing queued-paste UI test path proves menu/state behavior with a fake Foil target, but does not prove real app/window return behavior for TextEdit or a browser.

The safest next slice is a mixed local compatibility smoke: add a repo-native runbook/matrix and, where the local desktop permissions allow it, execute the existing automation smoke path against disposable TextEdit and browser text-entry targets. Product changes should stay out of this tranche unless the smoke reveals a concrete defect.

## Evidence

- `Foil/PasteTarget.swift` records target identity as `pid`, `appName`, optional `windowElement`, and optional `windowID`; validity is currently `pid > 0`.
- `Foil/UITestingController.swift` has `runAutomationMockSuccess()`, which captures the real current target with `PasteTarget.captureCurrentTarget()`, records it in `AppState`, and sends paste through `PasteController`.
- `Foil/UITestingController.swift` also has `simulateUITestTranscription(success:)`; when queued paste is enabled, it enqueues against a synthetic `PasteTarget(appName: "Foil UI Test")`, so it is insufficient for compatibility proof.
- `FoilUITests/FoilUITests.swift` covers queued-paste settings persistence and queue count/paste-next UI behavior, but those tests do not exercise TextEdit or browser targets.
- `Makefile` already defines local OS-bound paste gates: `test-cross-app`, `test-app-smoke`, `test-paste-real`, and `qa-local`.
- `docs/release-readiness-plan.md` requires repeatable local QA for paste/focus behavior and says skips must be explicit.
- `docs/release-qa-log.md` already records prior real paste/cross-app evidence and known installed-app TextEdit AX-window skip risk.

## Recommended Matrix Dimensions

- Target app: TextEdit and one browser, with browser preference based on local availability.
- Target surface: document/window title or local test page field, plus app name, pid, and window identity when available.
- Capture moment: frontmost app/window before invoking the Foil automation path.
- Queue state: queued paste enabled, queue count after transcript, and delivery action used.
- Outcome: text landed in intended target, landed elsewhere, clipboard fallback only, or unavailable/blocked.
- Fallback: target closed/unavailable before delivery, or explicit documentation if unavailable to exercise safely.
- Evidence: command transcript, matrix row, optional screenshot/log path, and exact skip reason if blocked by permissions.

## Manual, Scripted, Or Automated

Use a mixed approach.

- Manual/runbook is required because Accessibility, browser behavior, and TCC permissions are environment-dependent.
- Scripted helpers are useful if they create disposable TextEdit/browser targets and collect repeatable observations.
- Deterministic XCUITest alone is not enough because the current queued-paste UI path uses a fake Foil target.
- Avoid product hooks unless the runbook/script cannot trigger the existing `runAutomationMockSuccess()` path against real targets.

## Candidate Worker Slice

Objective: create and execute a compatibility smoke runbook/matrix for queued paste covering TextEdit and one browser target, recording target app/window identity behavior and fallback status without adding a global hotkey or overlapping transcription architecture.

Allowed files:

- `docs/queued-paste-compatibility-smoke.md`
- `docs/release-qa-log.md`
- `scripts/run-queued-paste-compatibility-smoke.sh`
- `Makefile`
- `docs/goals/queued-paste-compatibility-smoke/state.yaml`
- `docs/goals/queued-paste-compatibility-smoke/notes/*`

Verify commands:

- `node /Users/neonwatty/.codex/plugins/cache/goalbuddy/goalbuddy/0.3.7/skills/goalbuddy/scripts/check-goal-state.mjs docs/goals/queued-paste-compatibility-smoke/state.yaml`
- `bash -n scripts/run-queued-paste-compatibility-smoke.sh` if the script is added.
- `make test-paste-real` or the new smoke command if local permissions allow it.
- `git diff --check`

Stop if:

- The slice needs product behavior changes outside the allowed files.
- Automation requires a global queued-paste hotkey.
- Automation requires overlapping recording/transcription architecture.
- Accessibility, Automation, or browser permissions block TextEdit/browser execution after one documented attempt.
- Smoke results cannot distinguish target app/window return behavior from simple clipboard contents.


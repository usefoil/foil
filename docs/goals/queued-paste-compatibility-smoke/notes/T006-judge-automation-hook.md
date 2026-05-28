# T006 Judge Automation Hook

## Decision

approved

The previous audit found the right missing evidence: real-target queued delivery, not just target mechanics. Manual execution is possible but brittle in this agent session, so approve a bounded automation-only hook to capture the real frontmost target, enqueue a mock transcript, and deliver the queued item on demand.

## Guardrails

- The hook must only respond when Foil launches with `--automation-smoke`.
- The hook must not add user-facing UI or a global queued-paste hotkey.
- The hook must not alter recording/transcription concurrency.
- The script must drive disposable TextEdit/browser targets only.
- The fallback row may be recorded as explicit evidence if the closed-window behavior produces clipboard fallback/manual-paste state, or as a concrete product follow-up if the app still cannot distinguish the unavailable target.

## Worker Objective

Add and run a local queued-paste compatibility automation that proves real-target queued delivery for TextEdit and one browser text field, and records unavailable-target fallback behavior.

## Allowed Files

- `Foil/UITestingController.swift`
- `tests/test_queued_paste_compatibility.swift`
- `scripts/run-queued-paste-compatibility-smoke.sh`
- `Makefile`
- `docs/queued-paste-compatibility-smoke.md`
- `docs/release-qa-log.md`
- `docs/goals/queued-paste-compatibility-smoke/state.yaml`
- `docs/goals/queued-paste-compatibility-smoke/notes/*`

## Verify Commands

- `bash -n scripts/run-queued-paste-compatibility-smoke.sh`
- `ALLOW_LOCAL_QA_SKIP=1 make test-queued-paste-compatibility`
- `make test`
- `node /Users/neonwatty/.codex/plugins/cache/goalbuddy/goalbuddy/0.3.7/skills/goalbuddy/scripts/check-goal-state.mjs docs/goals/queued-paste-compatibility-smoke/state.yaml`
- `git diff --check`

## Stop Conditions

- The hook needs to run outside `--automation-smoke`.
- A global queued-paste hotkey becomes necessary.
- Overlapping recording/transcription changes become necessary.
- TextEdit and browser smoke cannot run after two attempts with the same unexplained failure.


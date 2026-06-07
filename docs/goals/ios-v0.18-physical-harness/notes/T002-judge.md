# T002 Judge - Harness Slice Decision

## Decision

Approved.

## Rationale

The Scout evidence shows the existing WDA evidence helper is already the right
privacy primitive, and v0.15-v0.17 receipts prove it works across the initial
target-app rows. The next largest safe slice is an orchestration harness that
standardizes status checks, current-app WDA sessions, canonical App Group
stage/reset, sanitized summaries, and fixture self-tests.

This is preferable to another manual target-app row because the goal oracle is
repeatability and privacy safety, not one more insertion proof.

## Approved Worker Objective

Implement `scripts/ios-physical-harness.py` with:

- `status`
- `wda-command`
- `session`
- `delete-session`
- `fetch-source`
- `stage-transcript`
- `reset-transcript`
- `app-group-summary`
- `receipt`
- `self-test`

Then update `docs/ios-physical-automation-runbook.md`, record the Worker
receipt, and preserve the no-raw-private-content boundary.

## Allowed Files

- `scripts/ios-physical-harness.py`
- `scripts/ios-physical-wda-evidence.py`, only for narrow import-safe reuse or a
  helper bug discovered by the self-test
- `docs/ios-physical-automation-runbook.md`
- `docs/goals/ios-v0.18-physical-harness/**`

## Verification

- `python3 -m py_compile scripts/ios-physical-wda-evidence.py`
- `python3 -m py_compile scripts/ios-physical-harness.py`
- `scripts/ios-physical-harness.py --help`
- `scripts/ios-physical-harness.py status`
- `scripts/ios-physical-harness.py wda-command`
- `scripts/ios-physical-harness.py self-test`
- `node /Users/neonwatty/.codex/plugins/cache/goalbuddy/goalbuddy/0.3.8/skills/goalbuddy/scripts/check-goal-state.mjs docs/goals/ios-v0.18-physical-harness/state.yaml`
- `git diff --check`
- targeted secret/raw-content scan over touched files

## Stop Conditions

- The physical phone requires unlock, installation, or user action.
- A command would print credentials, host-app content, raw WDA source, or
  transcript bodies.
- Product behavior changes are needed outside the approved harness scope.
- The harness cannot prove the existing evidence helper fails closed on a bad
  expectation.

## Required Final Audit Pressure

The final audit must try to disprove two things:

1. The harness is repeatable when WDA is down.
2. The harness does not leak raw transcript or host-app content in summaries,
   self-test output, receipts, or committed files.

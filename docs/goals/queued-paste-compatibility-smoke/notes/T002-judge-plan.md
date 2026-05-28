# T002 Judge Plan

## Decision

approved

Proceed with one vertical compatibility-smoke slice: add a repo-native runbook/matrix, add a small opt-in local smoke command if it can be implemented without product changes, execute the smoke against TextEdit and one browser target when local permissions allow, and record any blocks or limitations precisely.

## Rationale

The Scout evidence shows the product model records target identity as app/window metadata, not only a screen coordinate. The existing deterministic queued-paste UI tests cover settings and queue behavior but use a synthetic Foil target, so they cannot satisfy the oracle. A local compatibility smoke is the right next proof point before hotkey delivery or overlapping recording/transcription work.

The largest safe slice is documentation plus optional local smoke harness. Product behavior changes are intentionally out of scope until a concrete compatibility defect is observed and captured as follow-up work.

## Worker Objective

Create and execute a compatibility smoke runbook/matrix for queued paste covering TextEdit and one browser text-entry target. The result must record whether queued paste returns to the intended app/window, not merely whether text appears on the clipboard or somewhere on screen.

## Acceptance Criteria

- A repo-native compatibility matrix/runbook exists and names the smoke procedure.
- TextEdit has a matrix row with target app/window identity behavior, result, and evidence or precise block reason.
- One browser text-entry target has a matrix row with target app/window identity behavior, result, and evidence or precise block reason.
- Fallback or unavailable-target behavior is exercised if practical; otherwise it is explicitly documented with a follow-up.
- Any app-specific defect or limitation is captured as a follow-up item.
- No global queued-paste hotkey is added.
- No overlapping recording/transcription architecture is added.

## Allowed Files

- `docs/queued-paste-compatibility-smoke.md`
- `docs/release-qa-log.md`
- `scripts/run-queued-paste-compatibility-smoke.sh`
- `Makefile`
- `docs/goals/queued-paste-compatibility-smoke/state.yaml`
- `docs/goals/queued-paste-compatibility-smoke/notes/*`

If the worker discovers that a product hook is required, stop and return a follow-up recommendation rather than editing product files in this slice.

## Verify Commands

- `node /Users/neonwatty/.codex/plugins/cache/goalbuddy/goalbuddy/0.3.7/skills/goalbuddy/scripts/check-goal-state.mjs docs/goals/queued-paste-compatibility-smoke/state.yaml`
- `bash -n scripts/run-queued-paste-compatibility-smoke.sh` if the script is added
- `make test-paste-real` or the new smoke command if local permissions allow
- `git diff --check`

## Stop Conditions

- Need files outside the allowed list.
- Need a global queued-paste hotkey.
- Need overlapping recording/transcription architecture.
- Accessibility, Automation, or browser permissions block execution after one documented attempt.
- The observed evidence cannot distinguish target app/window behavior from clipboard-only success.

## PM Sequencing

1. Sync the local branch/worktree to the merged PR #160 baseline before worker edits.
2. Activate T003 with the worker objective above.
3. After T003, run T004 only if the smoke exposes limitations or defects that need follow-up tracking.
4. Run T999 final audit against the oracle before calling the tranche complete.

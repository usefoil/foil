# Experimental Queued Paste MVP

## Objective

Plan and execute the first safe PR for issue 159: an experimental queued-paste MVP that queues completed transcripts for user-triggered delivery, without adding a global queue hotkey or allowing overlapping recordings/transcriptions in this tranche.

## Original Request

"Plan out each of these PRs together. Use GoalBuddy goal-prep to keep us on track and create measurable acceptance criteria."

## Intake Summary

- Input shape: `specific`
- Audience: Foil users who want original-target paste intent without Foil choosing when to switch focus
- Authority: `approved`
- Proof type: `test`
- Completion proof: PR 1 is implementation-ready and then implemented with automated tests proving queue ordering, step/drain behavior, failed target retention, settings persistence, and queue count/status UI coverage.
- Goal oracle: Automated test evidence plus a final Judge audit maps receipts back to issue 159 PR 1 scope and confirms no global delivery hotkey or overlapping recording refactor slipped into the MVP.
- Likely misfire: Building generic planning artifacts or a partial UI while missing the behavioral core of deferred queued delivery, or accidentally expanding PR 1 into the harder overlapping-transcription architecture.
- Blind spots considered: Hotkey scope, overlapping recording scope, distinction between the existing immediate `PasteQueue` serializer and a user-visible deferred queue, and whether smoke testing belongs in PR 1.
- Existing plan facts: Stage the broader issue into multiple PRs. PR 1 is safe staged MVP first. PR 1 oracle is automated proof. PR 1 explicitly excludes global queue hotkey and overlapping recordings/transcriptions.

## Goal Oracle

The oracle for this goal is:

`Automated tests pass for queue ordering, step/drain behavior, failed target retention, settings persistence, and queue count/status UI coverage; final audit confirms PR 1 excludes global queue hotkey and overlapping recording/transcription refactors.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, a passing tiny slice, or a clean-looking board is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`specific`

## Current Tranche

Complete the first experimental queued-paste MVP PR plan and implementation path for issue 159. The current largest reversible work package is a vertical local product slice: persistent experimental settings, deferred transcript queue state, manual step/drain delivery controls, queue inspection/copy/remove/retry surface, privacy-safe diagnostics, and focused automated tests.

Later PRs may add a global delivery hotkey, TextEdit/manual smoke matrix expansion, and overlapping recording/transcription support, but those are out of scope for this tranche unless a final audit explicitly creates follow-up tasks.

## Non-Negotiable Constraints

- Do not add a global queued-paste hotkey in PR 1.
- Do not restructure Foil to allow overlapping recordings or overlapping transcription jobs in PR 1.
- Preserve existing normal paste behavior by default.
- Keep the queued-paste feature under Experimental settings.
- Treat history as the safety net: completed transcripts must still be retained in history even when queue delivery fails.
- Failed or undeliverable queued items must not be silently discarded.
- Keep diagnostics privacy-safe: record route/state/metadata receipts, not full transcript text.
- Prefer a separate deferred queue/store concept over overloading the existing immediate paste serializer unless Scout/Judge evidence proves otherwise.
- Use focused automated tests as the PR 1 oracle.

## Proposed PR Roadmap

1. PR 1: Experimental queued-paste MVP
   - Adds the deferred queue setting and mode setting.
   - Queues successful transcripts instead of auto-pasting when enabled.
   - Supports manual step-through and drain controls from the menu/status surface.
   - Allows queued item inspect/copy/remove/retry.
   - Tracks pending, pasted, failed, and needs-manual-paste states with failure reasons when available.
   - Adds privacy-safe diagnostic receipts.
   - Proves queue ordering, step/drain behavior, failed target retention, settings persistence, and queue count/status UI with automated tests.
2. PR 2: Delivery hotkey
   - Adds a configurable conservative queue delivery hotkey after the MVP behavior is proven.
   - Verifies hotkey persistence, conflict behavior, and delivery invocation.
3. PR 3: Smoke and compatibility matrix
   - Adds documented local/manual TextEdit, Chrome, Terminal, and later VS Code or Slack coverage.
   - Optionally adds scripted TextEdit smoke if reliable enough.
4. PR 4: Multi-session transcription architecture
   - Investigates and, if approved, restructures recording/transcription state so users can record again while previous transcriptions are still running.

## PR 1 Acceptance Criteria

- Experimental setting exists under Settings > Experimental for queueing transcriptions for later paste.
- Queue mode setting exists with `Step through queue` as default and `Drain queue` as the alternate mode.
- Normal paste behavior remains unchanged when queued paste is disabled.
- When queued paste is enabled, completed successful transcripts are added to a deferred queue instead of being auto-pasted.
- Queued items are ordered by recording start time, not transcription completion time.
- Step-through delivery pastes exactly one queued item per invocation.
- Drain delivery attempts all queued pending items in recording-start order.
- Failed or undeliverable items remain available for retry, copy, remove, or manual paste.
- User can inspect queue count/status in the menu bar popover or status surface.
- User can inspect, copy, remove, and retry queued items from the UI.
- History still retains completed transcripts regardless of queue delivery success.
- Diagnostics record privacy-safe queue and paste-route receipts.
- Automated tests cover ordering, step/drain behavior, failure retention, settings persistence, and queue count/status UI.

## Stop Rule

Stop only when a final audit proves the full current tranche outcome is complete.

Do not stop after planning, discovery, or Judge selection if a safe Worker task can be activated.

Do not expand the current tranche into global hotkey or overlapping transcription work. If those are discovered as necessary, block the exact task with a receipt and spawn follow-up planning tasks.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good task is the largest safe useful slice. For this goal, prefer a vertical PR 1 work package over many tiny helper-only changes, but use Scout and Judge first to validate the current code shape and decide allowed files.

## Canonical Board

Machine truth lives at:

`docs/goals/queued-paste-mvp/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/queued-paste-mvp/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available and mention a newer version without blocking.
4. Re-check the intake: original request, input shape, authority, proof, blind spots, existing plan facts, and likely misfire.
5. Work only on the active board task.
6. Assign Scout, Judge, Worker, or PM according to the task.
7. Write a compact task receipt.
8. Update the board.
9. If safe local work remains, choose the next largest reversible Worker package and continue unless blocked.
10. Review at phase, risk, rejected-verification, ambiguity, or final-completion boundaries.
11. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.

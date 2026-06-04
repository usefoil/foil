# Foil iOS Keyboard Prototype Overnight Queue

## Objective

Build and verify the smallest useful iOS prototype path for Foil-style dictation: a containing iPhone app plus custom keyboard that can hand off microphone recording, transcribe with an available Groq/Grok-compatible API key for testing, and insert text into target apps on simulator and the preview iPhone.

## Original Request

The user asked to work overnight doing real tests against both the simulator and the preview iPhone, plan a queue of GoalBuddy boards to get the basic setup working, use the machine's Groq/Grok API key for testing, create a new branch for the work, and create, fix up, and merge PRs into that branch.

## Intake Summary

- Input shape: `existing_plan`
- Audience: the app owner/developer evaluating whether a Foil iOS analogue is technically viable.
- Authority: `approved`
- Proof type: `demo`
- Completion proof: a branch named `codex/ios-keyboard-prototype` containing merged prototype PRs, with receipts proving simulator and physical-iPhone behavior or explicitly blocking device-only failure modes with evidence.
- Goal oracle: repeatable evidence that a custom keyboard can trigger the containing app, return to the host app, receive transcription state, and insert text; plus physical-device evidence for microphone recording and transcription.
- Likely misfire: building attractive iOS scaffolding while failing to prove the iOS-specific hard parts: microphone handoff, background behavior, keyboard reloads, target-app insertion, and secret-safe transcription testing.
- Blind spots considered: custom keyboard microphone restrictions, App Group state reliability, secure fields and apps that reject keyboards, background audio limits, simulator/device differences, API key handling, and PRs targeting the prototype branch rather than `main`.
- Existing plan facts: create a branch; queue GoalBuddy work; use real simulator and preview iPhone tests; use available Groq/Grok API key only for local testing; create, fix, and merge PRs into the prototype branch; include proof in receipts.

## Goal Oracle

The oracle for this goal is:

`On codex/ios-keyboard-prototype, the repo contains a verified iOS prototype or a receipt-backed technical blocker, with simulator evidence, physical-iPhone evidence, transcription evidence using the local test key, and an insertion matrix across target apps.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, passing unit tests, a simulator-only demo, or a clean-looking branch is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`existing_plan`

## Current Tranche

Complete the first overnight feasibility tranche: create the integration branch, establish the prototype board queue, discover the repo/Xcode shape, implement the smallest vertical iOS keyboard prototype that can be honestly tested, run simulator and preview-iPhone tests, fix the highest-impact failures, merge successful PRs into the prototype branch, and update the GitHub issue with evidence.

## Non-Negotiable Constraints

- Do not target `main` with prototype PRs; PRs must merge into `codex/ios-keyboard-prototype`.
- Do not commit API keys, recordings with sensitive content, private screenshots, or device-specific secrets.
- Treat simulator success as insufficient for microphone/background/keyboard reliability; physical-iPhone evidence is required or the exact blocker must be recorded.
- Respect existing unrelated worktree changes and do not revert them.
- Use GoalBuddy receipts as durable evidence after each phase.
- Prefer native Swift/iOS implementation patterns and the repo's existing provider concepts where they fit.
- Keep the prototype intentionally small; prove the iOS constraints before polishing UI.

## Queued Board Phases

This parent board owns the overnight queue. Each phase may become a child PR or a child GoalBuddy board if the PM finds it needs bounded branching work:

1. iOS prototype charter and repo fit.
2. iOS app plus keyboard extension shell.
3. keyboard/App Group handoff state machine.
4. physical-device microphone recording and background handoff.
5. Groq/Grok-compatible transcription path using the local test key.
6. cross-app keyboard insertion matrix.
7. stabilization, PR merge-up, issue update, and final audit.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if a safe Worker task can be activated.

Do not stop after a single verified Worker package when the broader owner outcome still has safe local follow-up work. Advance the board to the next highest-leverage safe Worker package and continue unless a phase, risk, rejected-verification, ambiguity, or final-completion review is due.

Do not stop because the preview iPhone, API key, PR creation, or target app access is blocked. Mark that exact slice blocked with a receipt, create the smallest safe follow-up or workaround task, and continue all local, non-destructive work that can still move the goal toward the full outcome.

## Canonical Board

Machine truth lives at:

`docs/goals/ios-keyboard-prototype/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/ios-keyboard-prototype/goal.md.
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
10. If a problem, suggestion, or follow-up should become a repo artifact, create an approved issue/PR or ask the operator whether to create one.
11. Review at phase, risk, rejected-verification, ambiguity, or final-completion boundaries.
12. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.

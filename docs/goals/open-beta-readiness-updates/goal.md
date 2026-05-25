# Open Beta Readiness Updates

## Objective

Implement the open-beta readiness updates identified by the UX, setup/release, and transcription/provider critiques, then verify the app is coherent enough for a public beta path.

## Original Request

Make a detailed plan to implement all of these updates using `$goalbuddy:goal-prep`.

## Intake Summary

- Input shape: `existing_plan`
- Audience: Foil open-beta users, including nontechnical users using Groq and more technical users using local/custom transcription providers.
- Authority: `requested`
- Proof type: `test`
- Completion proof: A final Judge or PM audit maps all completed task receipts to the beta-readiness critique, with passing deterministic tests and documented local/manual beta gates for macOS permissions, signed install, provider setup, and release/install paths.
- Goal oracle: The app can be freshly installed and guided through a coherent first-run provider setup path, can configure Groq/local/custom transcription without misleading copy, has provider-neutral errors and support docs, and has release/install/update metadata that points to one canonical public route.
- Likely misfire: Completing isolated copy/docs tweaks while leaving the core first-run provider mismatch, local setup friction, release URL inconsistency, or transcription reliability risks unresolved.
- Blind spots considered: macOS permission prompts are hard to automate, Sparkle/Homebrew may need external credentials or release artifacts, local whisper.cpp validation may be environment-dependent, and open beta may need some non-code policy decisions.
- Existing plan facts:
  - Onboarding is Groq/API-key-first while Settings supports Groq, Local whisper.cpp, and custom OpenAI-compatible providers.
  - Start/record controls and final onboarding state can be disabled without enough inline explanation.
  - Release/install URLs and owner names appear inconsistent across README, appcast, scripts, and Homebrew.
  - Homebrew is advertised despite QA notes showing it is not ready.
  - README under-documents local/custom provider setup, diagnostics, reset, and beta support paths.
  - Local whisper.cpp setup is currently instructional and should become more guided.
  - Transcription errors should be provider-neutral and local/custom aware.
  - OpenAI-compatible transcription should tolerate both plain text and JSON `{ "text": ... }` responses.
  - Transcription needs explicit timeout/cancel/retry behavior for poor networks or stalled local servers.
  - Failed retry audio should move from temp storage into app-owned Application Support storage.
  - Secondary UX gaps include history empty states, custom hotkey accessibility, floating status truncation, in-app help, privacy copy at provider choice, and either an audio-file import feature or explicit microphone-only beta positioning.

## Goal Oracle

The oracle for this goal is:

`Fresh-install beta walkthrough + automated verification: the canonical install/update/docs paths are internally consistent; first-run setup supports the selected provider path; Groq/local/custom provider states show accurate privacy, setup, and recovery copy; transcription handles provider-specific errors and compatible response shapes; retry audio survives restart/system temp cleanup expectations; and beta support docs plus QA evidence are current.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, a passing tiny slice, or a clean-looking board is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`existing_plan`

## Current Tranche

Continuous execution: validate the critique, implement the largest safe verified slices in priority order, and keep advancing until the beta-readiness oracle is met or individual externally blocked items are recorded with concrete follow-up paths and local safe work is exhausted.

## Non-Negotiable Constraints

- Preserve user work and unrelated dirty changes.
- Do not claim beta readiness from planning alone.
- Keep implementation aligned with existing SwiftUI/AppKit patterns and current tests.
- Do not make destructive release, signing, Homebrew, or GitHub changes without explicit owner authority.
- Separate external release credential blockers from local code/docs work so safe local work can continue.
- Every Worker slice must include verification commands or a documented reason why the check is local/manual.
- macOS permission, paste, microphone, Sparkle, and Homebrew claims must be backed by repeatable commands, QA notes, or explicit blocker receipts.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if safe Worker implementation remains.

Do not stop after a single verified Worker package when the broader open-beta outcome still has safe local follow-up work.

Do not stop because a slice needs credentials, production access, destructive operations, or policy decisions. Mark that exact slice blocked with a receipt, create a safe follow-up or workaround task, and continue local, non-destructive work.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

Workers should implement coherent beta-facing slices, not one label or helper at a time. Repeated same-shape UI copy, docs, or tests should be grouped into one useful package when the write scope is clear.

## Canonical Board

Machine truth lives at:

`docs/goals/open-beta-readiness-updates/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/open-beta-readiness-updates/goal.md.
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
10. Ask before external release/Homebrew/GitHub mutations that require owner authority.
11. Review at phase, risk, rejected-verification, ambiguity, or final-completion boundaries.
12. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.

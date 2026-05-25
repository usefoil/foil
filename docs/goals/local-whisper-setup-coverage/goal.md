# Local whisper.cpp Setup Coverage

## Objective

Create coverage and product support for the installed-app user journey where someone chooses `Local whisper.cpp` in Settings, gets enough in-app guidance to start a compatible local server, verifies connectivity, and can run transcription through that local provider.

## Original Request

"Brainstorm an actionable plan. We can use goal buddy prep to create this coverage. I want granular tasks that can have verifiable success criteria, measurable so we can drive development quickly with /goal."

## Intake Summary

- Input shape: `specific`
- Audience: Foil users who install the app and want local transcription, plus maintainers who need fast regression confidence.
- Authority: `requested`
- Proof type: `test`
- Completion proof: A final audit maps completed receipts to passing CI-safe tests for the local provider settings journey, an opt-in live local whisper.cpp E2E path, and visible in-app setup guidance for an installed-app user.
- Goal oracle: The local-provider setup oracle is a repeatable verification bundle: targeted unit tests, targeted UI tests that exercise selecting `Local whisper.cpp` from the default installed-app state, and the opt-in live local transcription E2E harness when a whisper.cpp server is available.
- Likely misfire: Adding more seeded provider/config tests while still missing the actual user journey from default settings to local-provider selection, setup guidance, connection test, and transcription.
- Blind spots considered: CI may not be able to provision whisper.cpp cheaply; docs-only setup help is not enough for installed users; seeded UI tests can hide real picker/regression issues; local E2E may remain opt-in but must be explicitly documented and easy to run.
- Existing plan facts:
  - The app already has a `Local whisper.cpp` provider preset, default base URL/model, optional API-key behavior, and connection test UI.
  - Existing CI covers unit-level provider behavior and seeded UI provider QA.
  - Existing opt-in local E2E requires an already-running local whisper.cpp/OpenAI-compatible server and is not part of regular CI.
  - The missing coverage is the installed-app user flow: open Settings, choose `Local whisper.cpp`, receive setup guidance, test connection, then transcribe through the local provider.

## Goal Oracle

The oracle for this goal is:

`A fresh checkout can run the new targeted verification commands and prove the installed-app-style Local whisper.cpp Settings journey is covered; when a local whisper.cpp server is running, the live E2E command proves the local transcription path end to end.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, a passing tiny slice, or a clean-looking board is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`specific`

## Current Tranche

Deliver the smallest complete coverage tranche that makes the local whisper.cpp experience defensible: product guidance in the app, CI-safe tests for the Settings selection/setup flow, explicit verification for connection-state behavior, and an opt-in live E2E path that remains documented and runnable without silently depending on CI infrastructure.

## Non-Negotiable Constraints

- Do not claim regular CI runs a live whisper.cpp transcription server unless the workflow actually provisions and exercises one.
- Do not rely only on seeded state for the user-facing Settings journey.
- Preserve the existing local E2E harness if it is still useful; improve its discoverability and verification only where needed.
- Keep tests focused and fast for CI-safe coverage.
- Avoid broad UX redesign outside the local-provider setup path.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if a safe Worker task can be activated.

Do not stop after a single verified Worker package when the broader owner outcome still has safe local follow-up work. Advance the board to the next highest-leverage safe Worker package and continue unless a phase, risk, rejected-verification, ambiguity, or final-completion review is due.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good task is the largest safe useful slice.

The expected implementation slices are:

1. Scout the current local-provider UI, docs, test targets, and CI shape.
2. Judge the exact test/product gaps and choose the first safe implementation package.
3. Add in-app setup guidance plus CI-safe UI coverage for selecting `Local whisper.cpp` from default Settings.
4. Add or tighten tests for connection-test states and local provider persistence as needed.
5. Validate or improve the opt-in live E2E harness and docs so manual QA has a measurable command path.
6. Final audit against the oracle.

## Canonical Board

Machine truth lives at:

`docs/goals/local-whisper-setup-coverage/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/local-whisper-setup-coverage/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available and mention a newer version without blocking.
4. Re-check the likely misfire: seeded tests or docs-only changes are not enough.
5. Work only on the active board task.
6. Write a compact task receipt.
7. Update the board.
8. Continue until the oracle is satisfied or a specific task is blocked with a receipt.

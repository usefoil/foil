# Setup Permission Regression Proof

## Objective

Completely close the recurring onboarding/setup permission regression class by building measurable automated and manual QA coverage for stale Accessibility and Microphone state across first-run setup, running-app permission changes, and production install flows.

## Original Request

Use GoalBuddy Prep to create an atomic task list with measurable acceptance criteria that can be measured against each completed step so we can completely solve recurring setup permission regressions.

## Intake Summary

- Input shape: `specific`
- Audience: Foil maintainers and release operators
- Authority: `requested`
- Proof type: `test`
- Completion proof: A final Judge/PM audit shows every known setup-permission regression mode is covered by passing automated tests or documented manual release QA, with no remaining required Worker task queued.
- Goal oracle: The live oracle is a permission-regression coverage matrix plus passing verification commands: focused unit tests, focused UI tests, build, production install smoke documentation, and release QA checklist updates.
- Likely misfire: Creating a nice-looking test plan or a single extra UI test while stale macOS TCC state can still reappear through another setup path.
- Blind spots considered: macOS TCC cannot be fully automated in CI, production bundle identity differs from debug, Accessibility and Microphone update through different system mechanisms, provider/API-key gating can mask permission readiness, and manual release QA can rot unless it has explicit receipts.
- Existing plan facts: The desired layers are pure state tests, refresh trigger tests, fake permission integration tests, UI tests, production install smoke, real TCC manual QA, and a release gate.

## Goal Oracle

The oracle for this goal is:

`A checked-in coverage matrix and final audit receipt prove that stale Accessibility and Microphone setup state is covered across AppState reducers, setup refresh triggers, onboarding UI, app activation/polling, microphone callback, provider gating, production cask install smoke, and manual TCC reset QA. All named automated verification commands pass, and manual-only cases are recorded in release QA documentation with concrete steps and expected outcomes.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, a passing tiny slice, or a clean-looking board is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`specific`

## Current Tranche

Build the missing automated and manual safety net for Foil setup permissions. The largest safe work packages are: first map current coverage and gaps, then add a testable permission provider or equivalent seam if needed, then add automated tests for every stale-state transition, then document and verify production/manual QA gates.

## Non-Negotiable Constraints

- Do not rely on a single UI test as proof for this class of bugs.
- Do not weaken production install dogfooding by replacing the cask-installed app without explicitly recording that choice.
- Do not use destructive macOS permission resets outside documented manual QA steps unless the operator explicitly approves them.
- Preserve existing user preferences, keychain entries, and production app data unless a task explicitly calls for a fresh-machine QA path and the operator approves.
- Automated tests must be deterministic and not require real Groq credentials or live microphone input unless explicitly marked manual or live QA.
- Every completed Worker task must leave a receipt with exact files changed, commands run, and pass/fail status.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if safe Worker tasks remain.

Do not stop after one verified Worker package if the permission-regression oracle still has uncovered rows.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good Worker task should close a coherent coverage slice: for example, all AppState permission matrix tests, all onboarding fake-transition UI tests, or the full production/manual QA documentation update.

## Canonical Board

Machine truth lives at:

`docs/goals/setup-permission-regression-proof/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/setup-permission-regression-proof/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available and mention a newer version without blocking.
4. Work only on the active board task.
5. Require receipts with exact evidence.
6. Update the board after every task.
7. Keep advancing until the oracle is satisfied.
8. Finish only with a Judge/PM audit receipt that maps all coverage and verification back to the original user outcome and records `full_outcome_complete: true`.

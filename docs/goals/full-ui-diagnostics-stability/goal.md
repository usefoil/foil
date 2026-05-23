# Full UI Diagnostics Stability

## Objective

Stabilize GroqTalk's macOS Full UI Diagnostics path so it produces useful beta-readiness signal instead of timing out on XCUITest foreground/background interaction failures.

## Original Request

Plan the next work with GoalBuddy after Full UI Diagnostics still failed at the 20-minute timeout despite PRs #118 and #119.

## Intake Summary

- Input shape: `recovery`
- Audience: GroqTalk maintainers preparing the app for open beta
- Authority: `requested`
- Proof type: `test`
- Completion proof: A Full UI Diagnostics run on `main` completes without timing out, produces parseable diagnostics, and any remaining failures are real product/test assertions rather than macOS runner foreground/background or SetupAssistant interference.
- Goal oracle: GitHub Actions workflow `Full UI Diagnostics` on `main`, plus artifact review for `SetupAssistant`, `Failed to activate`, `Failed to synthesize`, timeout, and parseable summary signals.
- Likely misfire: Only increasing timeout or removing tests, making the workflow green while preserving flaky foreground UI interactions and weak beta-readiness coverage.
- Blind spots considered: GitHub-hosted macOS runner behavior, menu-bar app activation policy, SetupAssistant interruption, redundant full-suite duration, whether tests should use harness commands instead of real clicks, and preserving meaningful open-beta coverage.
- Existing plan facts: PR #118 dismissed SetupAssistant and hardened CI path detection; PR #119 reasserted foreground activation for UI-test windows; latest Full UI Diagnostics run `26335757207` still timed out with foreground/background failures in History, Settings, Onboarding, and Provider UI tests.

## Goal Oracle

The oracle for this goal is:

`Run GitHub Actions Full UI Diagnostics on main and inspect artifacts until the run completes within budget with parseable diagnostics and no SetupAssistant/foreground-background runner blockers.`

The PM must keep comparing task receipts to this oracle. Planning, discovery, a passing focused smoke suite, or a clean-looking merge queue is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`recovery`

## Current Tranche

Recover the Full UI Diagnostics signal by replacing fragile XCUITest click paths with deterministic UI-test harness commands where appropriate, preserving meaningful coverage, and only then adjusting timeout or sharding if the suite still exceeds the diagnostic budget for legitimate duration reasons.

## Non-Negotiable Constraints

- Do not weaken open-beta coverage just to make the workflow green.
- Do not remove full-suite tests from diagnostics unless a Judge task records a coverage-preserving replacement.
- Prefer app/test harness commands for flows that are already covered by view-level assertions and are failing only because the macOS runner cannot foreground a menu-bar app.
- Keep changes scoped to UI test harness, UI tests, diagnostics workflow/scripts, and focused supporting app hooks unless Judge approves wider scope.
- Preserve existing successful CI and Local macOS E2E behavior.
- Merge only through green PR checks and merge queue.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if a safe Worker task can be activated.

Do not stop after a single verified Worker package when the broader outcome still has safe local follow-up work. Advance the board to the next highest-leverage safe Worker package and continue unless a phase, risk, rejected-verification, ambiguity, or final-completion review is due.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good task is the largest safe useful slice: for this goal, likely one coherent harness-driven interaction package for History, Settings/Provider, and Onboarding failures, followed by a diagnostic workflow decision only after artifact evidence improves.

## Canonical Board

Machine truth lives at:

`docs/goals/full-ui-diagnostics-stability/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/full-ui-diagnostics-stability/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available and mention a newer version without blocking.
4. Work only on the active board task.
5. Write a compact task receipt.
6. Update the board.
7. If safe local work remains, choose the next largest reversible Worker package and continue unless blocked.
8. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.

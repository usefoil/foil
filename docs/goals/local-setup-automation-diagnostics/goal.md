# Local Setup Automation Diagnostics

## Objective

Make Foil's local setup and permission QA workflow repeatable, diagnosable, and testable for developers without bypassing macOS privacy protections.

## Original Request

Make a detailed GoalBuddy plan to add setup automation, diagnostics, and tests for setup, ideally using GoalBuddy with rigorous acceptance criteria.

## Intake Summary

- Input shape: `existing_plan`
- Audience: Foil developers and maintainers doing local macOS QA.
- Authority: `approved`
- Proof type: `test`
- Completion proof: the local setup automation path has clear terminal diagnostics, verifies signing/bundle/TCC preconditions where macOS permits, has automated script or shell-level coverage where practical, and leaves a documented manual privacy-toggle boundary.
- Likely misfire: GoalBuddy could add another helper script or checklist that still fails to explain why Accessibility/Input Monitoring setup is broken, or could drift into unsafe privacy bypasses.
- Blind spots considered: developer versus end-user setup needs, proof beyond manual QA, macOS privacy boundaries, signing/TCC identity mismatch, and avoiding accidental direct TCC database modification or MDM/PPPC profile installation.
- Existing plan facts: prioritize developer setup automation first; success proof should be script/test/output proof; no unsafe privacy bypasses; create a fresh local live GoalBuddy board.

## Goal Kind

`existing_plan`

## Current Tranche

Complete the first developer-focused tranche: validate the existing local setup automation, harden it with diagnostics and explicit success/failure checks, add safe automated coverage where practical, and verify the workflow without silently granting macOS Accessibility or Input Monitoring permissions.

## Non-Negotiable Constraints

- Do not write directly to macOS TCC databases.
- Do not install MDM or PPPC profiles.
- Do not silently grant Accessibility, Input Monitoring, Microphone, or other privacy permissions.
- It is acceptable to use `tccutil reset` for the app's bundle identifier when the operator explicitly runs the local QA workflow.
- Keep final permission toggles user-controlled and clearly explained.
- Do not touch unrelated dirty files unless a later active Worker task explicitly allows it.
- Prefer shell-level checks and deterministic output for script behavior.
- Preserve the app's real bundle identifier and installed-app path assumptions unless discovery proves they are wrong.

## Step Success Criteria

1. Discovery succeeds when Scout maps the current setup automation, signing/install path, setup-check behavior, relevant tests, and known failure modes with concrete file-path evidence.
2. Plan validation succeeds when Judge selects the largest safe Worker slice with exact files, verification commands, stop conditions, and acceptance criteria covering script behavior and safety boundaries.
3. Automation hardening succeeds when Worker improves the local setup workflow so it verifies bundle identifier/signature assumptions, emits actionable diagnostics, handles common failure cases, and clearly separates automated steps from manual privacy toggles.
4. Test coverage succeeds when Worker adds or updates safe tests or shell checks for the setup workflow without relying on real permission grants.
5. Verification succeeds when build/test/script checks pass or blocked macOS-only checks are explicitly documented with evidence and a safe manual checklist.
6. Final audit succeeds only when Judge or PM maps all receipts back to the original outcome and records `full_outcome_complete: true`; otherwise the board must continue with the next safe Worker slice.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or Judge selection if a safe Worker task can be activated.

Do not stop after a single verified Worker package when the broader owner outcome still has safe local follow-up work. Advance the board to the next highest-leverage safe Worker package and continue unless a phase, risk, rejected-verification, ambiguity, or final-completion review is due.

Do not create one Worker/Judge pair per tiny helper or assertion. Put repeated same-shape work into one Worker package and review the package as a whole.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

A good task is the largest safe useful slice.

Small is not the goal. Useful is the goal.

A Worker should finish the whole assigned slice. A Judge should judge the whole assigned slice. A PM should reorient the board when tasks are safe but not moving the outcome.

Tiny tasks are allowed when the failure is isolated, the risk is high, the scope is unknown, or the tiny task unlocks a larger slice. Tiny tasks are bad when they keep happening, do not change behavior, only add wrappers/contracts/proof files, or avoid the real milestone.

Do not stop because a slice needs owner input, credentials, production access, destructive operations, or policy decisions. Mark that exact slice blocked with a receipt, create the smallest safe follow-up or workaround task, and continue all local, non-destructive work that can still move the goal toward the full outcome.

## Canonical Board

Machine truth lives at:

`docs/goals/local-setup-automation-diagnostics/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/local-setup-automation-diagnostics/goal.md.
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
11. Review at phase, risk, rejected-verification, ambiguity, or final-completion boundaries; do not review every small Worker by habit.
12. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.

Issue and PR handoffs are supporting artifacts. `state.yaml` remains authoritative, and every external artifact decision must be recorded in a task receipt.

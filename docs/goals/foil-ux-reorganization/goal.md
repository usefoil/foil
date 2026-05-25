# Foil UX Reorganization

## Objective

Reorganize Foil's setup, menu bar, and Settings UX so first-run setup is guided and resilient, the ready-state menu bar is a lean control center, and durable preferences live in coherent Settings panes.

## Original Request

Use the approved Foil UX reorganization direction to prepare granular, measurable work packages that GoalBuddy Prep can drive with `/goal`.

## Intake Summary

- Input shape: `existing_plan`
- Audience: Foil users and maintainers.
- Authority: `approved`
- Proof type: `test`
- Completion proof: setup, menu bar, and Settings changes are implemented against the design spec; tests and visual receipts show ready, setup-needed, onboarding, and Settings states; user-facing UI no longer exposes developer repair commands.
- Likely misfire: GoalBuddy could make the UI prettier while missing the permission-order problem, duplicate menu/settings controls, or test coverage for the setup states that caused the original confusion.
- Blind spots considered: macOS TCC state cannot be fully automated; UI tests can launch duplicate menu bar apps; moving controls can hide useful settings if the migration map is incomplete; debug controls must not leak into regular setup.
- Existing plan facts: Preserve `docs/superpowers/specs/2026-05-19-foil-ux-reorganization-design.md` as the source design. Preserve the user's earlier instruction not to run XCUITests unless explicitly authorized.

## Goal Kind

`existing_plan`

## Current Tranche

Validate the design/spec against the current code, then complete successive safe verified slices until setup flow correctness, menu bar simplification, Settings reorganization, docs/copy cleanup, and final regression verification are all complete.

## Non-Negotiable Constraints

- Do not run XCUITests unless the active task explicitly authorizes them.
- Do not revert unrelated dirty worktree changes.
- Keep macOS permission granting explicit; do not attempt silent Accessibility or Microphone permission changes.
- Preserve existing user preferences and feature reachability.
- Keep developer repair commands out of primary user-facing UI.
- Use `docs/superpowers/specs/2026-05-19-foil-ux-reorganization-design.md` as the source of truth for UX direction unless the user revises it.

## Stop Rule

Stop only when a final audit proves the full UX reorganization is complete: implementation matches the approved design, moved controls are accounted for, relevant tests pass or blockers are documented, visual receipts exist for the key surfaces, and no safe local follow-up slice remains.

Do not stop after inventory, planning, one partial UI change, or a passing focused test if queued implementation work remains.

## Canonical Board

Machine truth lives at:

`docs/goals/foil-ux-reorganization/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/foil-ux-reorganization/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available and mention a newer version without blocking.
4. Re-check the intake, likely misfire, current dirty diff, and design spec.
5. Work only on the active board task.
6. Assign Scout, Judge, Worker, or PM according to the task.
7. Write a compact receipt and update the board.
8. Continue to the next largest safe local work package unless blocked.
9. Finish only with a Judge or PM audit receipt that maps verification back to the original outcome and records `full_outcome_complete: true`.

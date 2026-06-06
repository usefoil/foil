# T999 Matrix Audit

Status: partial with exact blocker.

## Fresh v0.7 Rows

| Row | Result | Evidence |
| --- | --- | --- |
| Safari/local textarea fixture | pass | WDA showed Foil Keyboard with `foil-keyboard-insert-latest`; tapping Insert latest mutated the sterile fixture text to the known phrase and reset App Group state to `idle` / `Ready` / no transcript. |
| Safari/local secure password field | expected rejection | With a transcript staged, focusing the sterile password field showed native secure keyboard controls, no Foil Keyboard root, and no `foil-keyboard-insert-latest`; App Group state remained `complete` with the transcript still staged. |
| Messages | blocked | No dedicated safe self/test thread is recorded or operator-provided. Existing runbook and prior board receipts require skipping Messages rather than inspecting private threads. |

## Referenced Prior Physical Rows

Notes and Reminders are already physically proven in earlier iPhone-preview matrix receipts, but they were not rerun in this v0.7 board:

- `docs/goals/ios-keyboard-state-and-target-matrix/notes/T005-host-app-matrix.md`
- `docs/goals/ios-keyboard-onboarding-full-access-ux/state.yaml`

The v0.7 board should therefore not claim a fresh Notes or Reminders rerun. It can safely claim that the current risk focus is narrower: sterile Safari fixture insertion, secure-field rejection, and Messages blocked pending a sterile thread.

## Strongest Failure Mode Checked

The strongest realistic failure mode is overbroad support language: treating a Safari fixture pass plus old Notes/Reminders receipts as proof that arbitrary target apps, or Messages specifically, work today.

That is ruled out here by the audit scope:

- Messages remains a blocker, not a pass.
- Secure fields are documented as expected platform rejection, not a workaround target.
- Notes/Reminders are referenced as prior evidence only, not fresh v0.7 reruns.
- The final conveyor/tester handoff must say exactly this.

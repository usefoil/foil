# Foil iOS v0.16 Reminders Matrix

## Original Request

Continue the iOS keyboard prototype conveyor after the Safari and secure-field
matrix.

## Outcome

Run a privacy-safe physical iPhone-preview Reminders row using a newly created
sterile reminder draft, then discard the draft so test content is not left on
the device.

## Oracle

The board is complete when sanitized receipts prove:

- Reminders exposes a new reminder entry surface with Foil Keyboard visible.
- Insert latest is enabled before insertion.
- After tapping Insert latest, the sterile draft contains the staged transcript,
  Insert latest is disabled, and App Group state is idle/no transcript.
- The sterile draft is dismissed afterward and the staged transcript no longer
  appears in Reminders.

## Constraints

- Do not commit raw Reminders WDA source, screenshots, reminder content, private
  list names, or private URLs.
- Use `scripts/ios-physical-wda-evidence.py` receipts as the source-controlled
  artifact shape.
- Keep Messages skipped unless a dedicated sterile self/test thread exists.
- Keep PRs targeted at `codex/ios-keyboard-prototype`.

## Proof Plan

1. Start WDA and create a Reminders-scoped WDA session.
2. Stage a sterile fake transcript using Foil diagnostics.
3. Tap `New Reminder`, verify Foil Keyboard and Insert latest.
4. Tap Insert latest, record sanitized post-insert and App Group evidence.
5. Dismiss the draft with Back and prove the staged transcript is absent.
6. Stop WDA before handoff.

## Starter Command

`/goal Follow docs/goals/ios-v0.16-reminders-matrix/goal.md.`

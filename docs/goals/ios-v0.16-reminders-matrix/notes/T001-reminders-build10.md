# T001 Reminders Build 10 Matrix

Status: pass.

## Environment

- Branch: `codex/ios-v0.16-reminders-matrix`
- Device: `iPhone-preview`
- Device identifier: `5320F5AD-2A71-50AC-94FE-207B544B6247`
- WDA URL: `http://192.168.1.40:8100`
- Installed app evidence inherited from v0.13: TestFlight `Foil iOS 0.1.0 (10)`

## Receipts

| Row | Result | Sanitized receipt |
| --- | --- | --- |
| Reminders draft before insertion | pass | `notes/receipts/reminders-before-insert.json` |
| Reminders draft after insertion | pass | `notes/receipts/reminders-after-insert.json` |
| Reminders after cleanup | pass | `notes/receipts/reminders-after-cleanup.json` |

## Findings

- The Reminders app launched with bundle id `com.apple.reminders`, and WDA needed
  a Reminders-scoped session; a Foil-scoped session continued to report Foil's
  tree after Reminders launched.
- New reminder entry showed Foil Keyboard with
  `foil-keyboard-insert-latest.enabled=true`.
- After insertion, the sanitized receipt proves Foil Keyboard remained visible,
  `foil-keyboard-insert-latest.enabled=false`, the staged text was present in
  the draft, and the App Group snapshot was `phase=idle` with
  `hasTranscript=false`.
- Tapping Back dismissed the unsaved draft. The cleanup receipt proves `New
  Reminder` was available again and the staged text was absent.

## Burden Of Proof

Strongest realistic failure mode: Reminders could appear to accept text while
Foil still had stale transcript state or while the test draft remained on the
device as persistent data.

Evidence ruling it out:

- Post-insert receipt includes App Group snapshot summary `phase=idle` and
  `hasTranscript=false`, proving the transcript was consumed.
- Cleanup receipt forbids the staged text and requires `New Reminder`, proving
  the draft was dismissed rather than left open with test content.
- WDA and the local automation process were stopped after the run.

## Residual Risk

- This row covers a newly created Reminders draft only, not editing existing
  reminders or reminder notes fields.
- Messages remains untested until a dedicated sterile self/test thread exists.

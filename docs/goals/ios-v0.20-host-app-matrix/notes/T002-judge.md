# T002 Judge - Approve Host-App Matrix Slice

## Decision

Approved.

## Rationale

The Scout proposal is aligned with the v0.20 oracle, but the Worker should
attempt four rows rather than exactly three. Mail and Calendar are valuable host
apps, but either may responsibly block if WDA cannot reach a blank draft/new
event surface without exposing private content. A four-row slice gives the board
room to record at least three receipt-backed pass/block/fail outcomes without
weakening privacy rules.

## Approved Worker Slice

Execute the following rows in order:

1. Safari local web form, single-line input.
2. Mail blank compose draft body or subject.
3. Calendar blank new-event title.
4. Foil iOS secure-field rejection harness.

For Mail and Calendar, a privacy block is acceptable if the row cannot reach a
sterile blank surface without inspecting or committing private content. Do not
turn a privacy block into navigation through account, inbox, contact, calendar,
or event lists.

## Allowed Files

- `docs/ios-keyboard-host-app-matrix.md`
- `docs/goals/ios-v0.20-host-app-matrix/**`
- `scripts/**` only for narrow harness/testability fixes

## Required Evidence

For pass insertion rows:

- Staged transcript/App Group receipt before insertion.
- Sanitized pre-insert WDA receipt proving Foil Keyboard root is visible and
  `foil-keyboard-insert-latest.enabled=true`.
- Sanitized post-insert WDA receipt proving the sterile value is in the intended
  field and `foil-keyboard-insert-latest.enabled=false`.
- App Group receipt proving `phase=idle` and no transcript after insertion.

For expected rejection rows:

- Sanitized receipt proving the focused secure field/rejection surface.
- Foil Keyboard root and Insert latest absent.
- App Group still complete/has transcript until explicit cleanup.
- Cleanup receipt proving idle/no transcript afterward.

For privacy-blocked rows:

- Sanitized note/receipt naming the exact block condition.
- No raw source, screenshots, account metadata, contacts, message bodies,
  filenames, calendar event titles, or email content committed.

## Verification

- GoalBuddy state checker.
- `scripts/ios-physical-harness.py status`.
- `scripts/ios-physical-harness.py self-test`.
- Row-specific receipts for at least three additional targets.
- `git diff --check`.
- Targeted secret scan.
- Targeted raw-content scan over touched v0.20 docs/receipts.

## Stop If

- The phone locks, disconnects, or requires operator action.
- A row would send mail, save a calendar event, send a message, or mutate
  private user data.
- A target exposes private content before a sterile blank field is focused.
- Raw WDA source, screenshots, or private content would need to be committed.

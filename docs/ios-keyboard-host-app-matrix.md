# Foil iOS Keyboard Host-App Matrix

This matrix tracks physical iPhone evidence for Foil Keyboard insertion across
sterile host-app targets. Receipts are sanitized: raw WDA source, screenshots,
private app content, contacts, account metadata, provider keys, and transcript
bodies from non-sterile contexts must not be committed.

## Current Coverage

| Row | Board | Status | Evidence | Notes |
| --- | --- | --- | --- | --- |
| Notes sterile editor, live transcript | v0.19 | Pass | `docs/goals/ios-v0.19-live-transcription-proof/notes/receipts/notes-before-insert.json`, `notes-after-insert.json`, `app-group-cleanup.json` | Proves live Foil iOS transcription into Foil Keyboard and exact-once insertion. |
| Safari local textarea | v0.15 | Pass | `docs/goals/ios-v0.15-safari-secure-matrix/notes/receipts/safari-textarea-before-insert.json`, `safari-textarea-after-insert.json` | WebKit mirrors textarea content, so row used fixture-specific evidence. |
| Safari local secure password field | v0.15 | Expected rejection | `docs/goals/ios-v0.15-safari-secure-matrix/notes/receipts/safari-secure-field-rejection.json` | Custom keyboard absent; transcript remained staged. |
| Reminders new draft | v0.16 | Pass | `docs/goals/ios-v0.16-reminders-matrix/notes/receipts/reminders-before-insert.json`, `reminders-after-insert.json`, `reminders-after-cleanup.json` | Draft dismissed after insertion. |
| Messages sterile thread draft | v0.17 | Pass | `docs/goals/ios-v0.17-messages-sterile-thread/notes/receipts/messages-before-insert.json`, `messages-after-insert.json`, `messages-after-cleanup.json` | Requires operator-opened sterile thread; do not navigate private thread lists. |

## v0.20 Expansion

| Row | Status | Receipts | Strongest Failure Mode Checked |
| --- | --- | --- | --- |
| Safari local single-line input | Pass | `docs/goals/ios-v0.20-host-app-matrix/notes/receipts/safari-single-stage.json`, `safari-single-before-insert.json`, `safari-single-after-insert.json`, `safari-single-app-group-after-insert.json`, `safari-single-cleanup.json` | A WebKit mirror could make it look inserted without proving the focused input received the text. The final receipt proves the sterile value appears exactly once in value attributes, Insert latest becomes disabled, and App Group returns idle. |
| Mail blank compose draft | Blocked | `docs/goals/ios-v0.20-host-app-matrix/notes/receipts/mail-compose-blocker.json` | A row could expose inbox/account/private message content while trying to reach compose. The run used only a sterile `mailto:` open attempt; WDA reported the Mail bundle unavailable, and no Mail source was inspected. |
| Calendar blank new-event title | Blocked | `docs/goals/ios-v0.20-host-app-matrix/notes/receipts/calendar-new-event-blocker.json` | Opening Calendar normally could expose private event titles before a blank event sheet is focused. The run stopped before fetching Calendar source or screenshots. |
| Foil iOS secure-field rejection fallback | Blocked | `docs/goals/ios-v0.20-host-app-matrix/notes/receipts/foil-secure-stage.json`, `foil-secure-blocker.json`, `foil-secure-cleanup.json` | A secure-field rejection row could falsely pass without focusing the secure field. The run records this as blocked because Diagnostics could not be expanded through WDA, and cleanup reset App Group to idle. |

## Next Useful Rows

- Mail compose after confirming Mail is installed or installing/configuring a
  sterile mail account.
- Calendar new-event title after operator setup opens a blank unsaved event
  sheet with the title field focused.
- Foil secure-field rejection after adding a first-party deep link or
  accessibility action to open Diagnostics/focus `secure-rejection-field`.
- Files or third-party chat only with an operator-provided sterile input surface.

## Release Gate

A row is not considered a pass unless it has:

- Pre-insert keyboard readiness proof when insertion is expected.
- Post-insert intended-field proof, not clipboard-only proof.
- App Group consumption or cleanup proof.
- A privacy scan confirming raw host-app source and private content were not
  committed.

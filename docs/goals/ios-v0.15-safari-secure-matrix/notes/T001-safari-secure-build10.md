# T001 Safari And Secure Field Build 10 Matrix

Status: pass.

## Environment

- Branch: `codex/ios-v0.15-safari-secure-matrix`
- Device: `iPhone-preview`
- Device identifier: `5320F5AD-2A71-50AC-94FE-207B544B6247`
- WDA URL: `http://192.168.1.40:8100`
- Fixture: `docs/goals/ios-target-app-insertion-matrix-v0.7/notes/fixture/index.html`
- Installed app evidence inherited from v0.13: TestFlight `Foil iOS 0.1.0 (10)`

## Receipts

| Row | Result | Sanitized receipt |
| --- | --- | --- |
| Safari/local textarea before insertion | pass | `notes/receipts/safari-textarea-before-insert.json` |
| Safari/local textarea after insertion | pass | `notes/receipts/safari-textarea-after-insert.json` |
| Safari/local secure password field | pass, expected rejection | `notes/receipts/safari-secure-field-rejection.json` |

## Findings

- Textarea pre-insert receipt proves Foil Keyboard was visible, Insert latest was
  present, and `foil-keyboard-insert-latest.enabled=true`.
- Textarea post-insert receipt proves Foil Keyboard stayed visible, Insert
  latest became `enabled=false`, and the sterile fixture value was present. The
  receipt intentionally uses a presence check rather than an exact count because
  the fixture echoes textarea content into an output row and WebKit exposes that
  text in multiple accessibility attributes.
- Secure-field receipt proves the password field was focused, Foil Keyboard root
  and Insert latest were absent, the fixture still reported zero secure-field
  characters, and the App Group snapshot remained `phase=complete` with
  `hasTranscript=true`.

## Burden Of Proof

Strongest realistic failure mode: the matrix could look green while the secure
field silently accepted or consumed the pending transcript.

Evidence ruling it out:

- Secure-field receipt forbids `foil-keyboard-root` and
  `foil-keyboard-insert-latest`.
- Secure-field receipt requires the hashed fixture status corresponding to
  zero secure-field characters and forbids the hashed status corresponding to
  the staged transcript length.
- App Group snapshot summary in the same receipt reports `phase=complete` and
  `hasTranscript=true`, proving the transcript remained staged rather than
  consumed by the secure-field focus.

## Residual Risk

- This row covers Safari/local textarea and password fields only.
- Reminders and Messages remain future rows. Messages still requires a dedicated
  sterile self/test thread before responsible automation.

# T002 Messages Physical Row

Status: pass.

## Environment

- Branch: `codex/ios-v0.17-messages-physical-row`
- Device: `iPhone-preview`
- Device identifier: `5320F5AD-2A71-50AC-94FE-207B544B6247`
- WDA URL: `http://192.168.1.40:8100`
- Installed app evidence inherited from v0.13: TestFlight `Foil iOS 0.1.0 (10)`
- Operator setup: a sterile Messages thread was opened and the input field was
  focused before Codex inspected the active state.

## Receipts

| Row | Result | Sanitized receipt |
| --- | --- | --- |
| Messages before insertion | pass | `notes/receipts/messages-before-insert.json` |
| Messages after insertion | pass | `notes/receipts/messages-after-insert.json` |
| Messages after draft cleanup | pass | `notes/receipts/messages-after-cleanup.json` |

## Findings

- Creating a WDA session with `bundleId=com.apple.MobileSMS` relaunched Messages
  to a list/search surface, so the safe flow is to start WDA first, let the
  operator focus the sterile thread input, and then create a current-app session
  without a bundle id.
- The initial current-app WDA source showed a focused input, Foil Keyboard root,
  and Insert latest without conversation-list hints.
- The staged transcript was written directly to Foil's App Group snapshot so
  automation did not need to leave the already-open sterile thread.
- Before insertion, the sanitized receipt proves Foil Keyboard was present and
  `foil-keyboard-insert-latest.enabled=true`.
- After insertion, the sanitized receipt proves the staged text was present in
  the draft, `foil-keyboard-insert-latest.enabled=false`, and the App Group
  snapshot was `phase=idle` with `hasTranscript=false`.
- Cleanup used WDA clear on the input element containing the staged text. The
  cleanup receipt proves the staged text was absent afterward.

## Burden Of Proof

Strongest realistic failure mode: Messages insertion could leave a sendable
draft behind or require inspecting private threads to complete the row.

Evidence ruling it out:

- The row only proceeded after the operator focused a sterile thread input.
- No raw Messages WDA source, screenshot, contact, thread name, phone number, or
  message body was committed.
- Cleanup receipt forbids the staged text, proving the unsent draft was cleared.
- Post-insert receipt includes App Group snapshot summary `phase=idle` and
  `hasTranscript=false`, proving Foil consumed the transcript exactly once.
- WDA was stopped after the run.

## Residual Risk

- This proves inserting into an already-open sterile Messages draft, not
  creating recipients or sending messages.
- The safe Messages flow depends on operator setup; automation must not navigate
  from the conversation list.

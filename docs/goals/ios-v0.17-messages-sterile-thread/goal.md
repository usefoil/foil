# Foil iOS v0.17 Messages Sterile Thread

## Original Request

Continue the iOS keyboard prototype target-app matrix after Reminders by
covering Messages only if a sterile thread exists.

## Outcome

Prepare the privacy-safe Messages row and stop before inspecting Messages until
the operator opens or creates a dedicated sterile thread on `iPhone-preview`.

## Oracle

The board is complete only when sanitized receipts prove:

- Messages is open to a dedicated sterile thread, not the conversation list.
- The message compose field is focused with Foil Keyboard visible.
- Insert latest is enabled before insertion.
- After tapping Insert latest, the sterile draft contains the staged transcript,
  Insert latest is disabled, and App Group state is idle/no transcript.
- The draft is deleted or cleared afterward, with a sanitized cleanup receipt.

If a sterile thread is not operator-provided, the board must remain blocked and
must not inspect the Messages conversation list or existing threads.

## Privacy Boundary

- Do not inspect existing Messages conversations, contacts, phone numbers,
  Apple IDs, message bodies, or thread titles.
- Do not create a recipient by searching Contacts.
- Do not send messages unless the operator explicitly asks for that exact action
  after opening a sterile thread.
- Do not commit raw Messages WDA source or screenshots.
- Commit only `scripts/ios-physical-wda-evidence.py` sanitized receipts.

## Operator Setup

Before automation can proceed, the operator should do one of these on
`iPhone-preview`:

1. Open an existing sterile self/test Messages thread and leave it visible.
2. Create a new sterile thread to a safe test recipient, type no private
   content, and leave the message input focused.

After setup, tell Codex: `Messages sterile thread is open`.

## Proof Plan After Setup

1. Start WDA and create a Messages-scoped session.
2. Verify the active screen has a compose text field and does not look like the
   conversation list using allowed identifiers only.
3. Stage a sterile fake transcript in Foil diagnostics.
4. Return to the already-open sterile Messages thread.
5. Record pre-insert receipt: Foil Keyboard root present, Insert latest enabled.
6. Tap Insert latest.
7. Record post-insert receipt: staged text present in draft, Insert latest
   disabled, App Group idle/no transcript.
8. Clear/delete the draft and record cleanup receipt.
9. Stop WDA.

## Starter Command

`/goal Follow docs/goals/ios-v0.17-messages-sterile-thread/goal.md.`

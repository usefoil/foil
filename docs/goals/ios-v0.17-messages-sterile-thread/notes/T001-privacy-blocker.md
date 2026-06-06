# T001 Messages Privacy Blocker

Status: blocked pending operator-created sterile thread.

## Decision

Messages is the remaining high-value target-app row, but it is also the first
row where automation can easily expose private contacts and conversation
content. The v0.15/v0.16 evidence pattern remains valid, but the operator must
first open or create a sterile thread.

## What Is Safe Now

- Prepare the board and proof plan.
- Start WDA only after a sterile thread is visible or after the operator gives a
  specific safe target.
- Use sanitized receipts that hash the staged text and omit raw Messages source.

## What Is Not Safe

- Opening the Messages conversation list and scanning thread names.
- Searching contacts for a recipient.
- Inferring the operator's phone number, Apple ID, or contact card.
- Sending a message without explicit operator confirmation.

## Resume Instruction

When the preview iPhone is showing a safe test thread, tell Codex:

`Messages sterile thread is open`

Codex can then run the physical row without reading or committing private
Messages content.

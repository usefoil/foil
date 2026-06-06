# Foil iOS v0.20 Host App Matrix

## Original Request

Keep pushing the iOS keyboard prototype through real insertion testing.

## Outcome

Expand from the initial Notes/Safari/Reminders/Messages rows to a small,
repeatable host-app compatibility matrix with privacy-safe fixtures and receipts.

## Oracle

This board is complete only when a committed matrix records pass/block/fail
status for at least three additional sterile targets, with:

- Pre-insert keyboard readiness proof.
- Post-insert exact-once proof.
- App Group cleanup proof.
- Expected secure-field rejection where applicable.
- No raw private source, contacts, message bodies, screenshots, or credentials.

## Candidate Rows

The Scout should choose rows based on availability and privacy safety. Likely
candidates include Mail draft, Calendar/Reminders-style text field, Files or a
web form, third-party chat only if the operator provides a sterile surface, and
another secure-field rejection row.

## Non-Goals

- Do not send emails, messages, calendar invites, or third-party chat messages.
- Do not inspect existing private app content.
- Do not add product features beyond narrow testability fixes.

## Seed Plan

1. Scout the safest target rows and required operator setup.
2. Judge a bounded matrix slice.
3. Execute rows with the v0.18 harness and v0.19 live/staged proof mode as
   appropriate.
4. Commit receipts and matrix docs.
5. Audit the strongest failure mode: matrix cells that prove clipboard/text
   presence without proving the intended host app received exact-once insertion.

## Starter Command

`/goal Follow docs/goals/ios-v0.20-host-app-matrix/goal.md.`

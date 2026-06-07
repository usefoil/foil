# T001 Scout - Host App Matrix Rows

## Result

Done.

## Environment

- Branch: `codex/ios-v0.20-host-app-matrix`
- Base: `codex/ios-keyboard-prototype` after v0.19 merge `5f79d4e`
- Device: `iPhone-preview`
- Device identifier: `5320F5AD-2A71-50AC-94FE-207B544B6247`
- Harness status: device present/available, `iproxy` present, WDA project
  present, WDA not currently running at `http://127.0.0.1:8100`
- App-list metadata probe: inconclusive. `devicectl device info apps` failed
  with CoreDevice connection reset; do not treat this as row failure.

## Prior Coverage

Already covered rows:

- Notes sterile editor: v0.19 live transcript insertion proof.
- Safari local textarea: v0.15 pass.
- Safari local secure password field: v0.15 expected rejection.
- Reminders new draft: v0.16 pass.
- Messages sterile thread draft: v0.17 pass with operator-provided sterile
  thread.

v0.20 should not spend the first slice repeating those rows unless needed as a
calibration check.

## Recommended Rows

1. **Safari local web form, single-line input**
   - Setup: serve a local sterile fixture and focus a plain text input distinct
     from the previous textarea row.
   - Proof: pre-insert Foil Keyboard root and Insert latest enabled; post-insert
     expected value count or exact input value hash; App Group idle/no
     transcript after insertion.
   - Cleanup: reset App Group and close/dismiss local fixture.
   - Risk: Safari can mirror focused text into multiple accessibility
     attributes. Prefer exact value-field count or field-specific hashed value,
     not raw occurrence count across the whole tree.

2. **Mail compose draft body or subject**
   - Setup: use a blank compose draft only. Do not send mail. Stop if Mail opens
     into a private inbox/list that cannot be bypassed without inspecting
     content.
   - Proof: pre-insert keyboard readiness; post-insert draft field contains the
     staged sterile value and Insert latest is disabled; App Group idle/no
     transcript.
   - Cleanup: discard the unsent draft and confirm staged value is absent if a
     privacy-safe receipt can be made.
   - Risk: Mail may expose account/from/inbox metadata in raw WDA source. Raw
     source must stay in `/tmp`; committed receipts must contain hashes/counts
     only.

3. **Calendar new event title**
   - Setup: create a new unsaved event, focus the title field, and do not save
     the event. Stop if the route exposes private calendar content before a
     blank event sheet is focused.
   - Proof: pre-insert keyboard readiness; post-insert title field contains the
     staged sterile value; Insert latest disabled; App Group idle/no transcript.
   - Cleanup: cancel/delete the unsaved event and confirm no staged value is
     present if privacy-safe.
   - Risk: Calendar month/list views can expose private event titles. Use a
     blank new-event sheet as the only acceptable surface.

4. **Foil iOS secure-field rejection harness**
   - Setup: stage a transcript, launch Foil iOS, focus
     `secure-rejection-field`.
   - Proof: `secure-rejection-field` present, Foil Keyboard absent, native Apple
     keyboard present if detectable, and App Group remains complete/has
     transcript until explicit cleanup.
   - Cleanup: reset App Group to idle/no transcript.
   - Risk: This is not a third-party host app, so it should be used as an
     additional rejection row rather than the only matrix expansion.

## Rows Rejected For First Slice

- **Messages new recipient or conversation navigation**: rejected. v0.17 proved
  the safe pattern only after the operator focused a sterile thread. Navigating
  Messages lists/recipients risks private contacts and messages.
- **Files browse/search**: defer. Files can expose private filenames/folders in
  raw WDA trees, and cleanup semantics are weaker than a draft/cancel surface.
- **Third-party chat**: defer unless the operator provides a sterile open input
  surface. Do not inspect account/thread lists.

## Candidate Worker Slice

Execute a bounded three-row matrix:

1. Safari local single-line input pass row.
2. Mail blank compose draft row, or record a privacy blocker if a blank compose
   surface cannot be reached without private content.
3. Calendar blank new-event title row, or record a privacy blocker if a blank
   event surface cannot be reached without private content.

If either Mail or Calendar blocks, use the Foil secure-field rejection row as
the fallback third receipt-backed row.

Allowed files:

- `docs/ios-keyboard-host-app-matrix.md`
- `docs/goals/ios-v0.20-host-app-matrix/**`
- `scripts/**` only for narrow harness fixes

Verify:

- GoalBuddy state checker.
- `scripts/ios-physical-harness.py status`.
- For each pass row: pre-insert keyboard receipt, post-insert exact field proof,
  App Group cleanup receipt.
- For each blocker row: sanitized blocker receipt/note naming the exact privacy
  or device condition.
- Targeted secret scan.
- Targeted raw-content scan for WDA XML/source, Messages/Mail/Calendar private
  values, contacts, Authorization headers, and provider keys.
- `git diff --check`.

Stop if:

- The phone locks, disconnects, or requires operator action.
- A selected app exposes private content before a sterile draft/new-item surface
  is focused.
- A row would send mail, save calendar events, send messages, or mutate private
  user data.
- Raw WDA source or screenshots would need to be committed.

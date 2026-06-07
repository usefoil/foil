# T999 Final Audit

## Full Outcome Complete

True for the v0.21 recovery slice.

The code now uses one shared insertability rule for keyboard UI enablement and
bridge consumption, and the board has both focused Swift tests and physical
sterile receipts for stale, complete, inserted, malformed, and reset states.

## Oracle Mapping

- Clear status for idle, recording/transcribing, complete, stale/error, and
  inserted states: covered by `FoilDictationLoopPresentationTests` and physical
  receipts for complete, stale, malformed, inserted, and reset states.
- Insert latest is enabled only when a usable transcript exists: covered by
  `FoilKeyboardBridgeTests`, `complete-before-insert.json`,
  `stale-keyboard.json`, and `malformed-keyboard.json`.
- Insert latest consumes the transcript exactly once: covered by
  `FoilKeyboardBridgeTests`, `after-insert.json`, and
  `after-insert-app-group.json`.
- Stale or malformed App Group state does not enable duplicate or bad insertion:
  covered by `stale-stage.json`, `stale-keyboard.json`,
  `malformed-stage.json`, and `malformed-keyboard.json`.
- Recoverable keyboard refresh path: the physical run confirms Foil Keyboard can
  be reactivated in Safari and can recover from stale/malformed state after
  App Group reset. Broader cross-app refresh ergonomics remain future matrix
  work, not a blocker for this slice.

## Strongest Realistic Failure Mode

The keyboard could appear ready from stale or corrupted App Group data and insert
bad text into the host app.

## Disproof Evidence

- Stale non-complete state with a leftover transcript was staged and read back
  with phase `processing`, transcript length, and hash only:
  `notes/receipts/stale-stage.json`.
- The physical keyboard UI then showed Foil Keyboard active, Insert latest
  disabled, and no `Transcript ready` accessible text:
  `notes/receipts/stale-keyboard.json`.
- Malformed JSON was written and read back byte-for-byte:
  `notes/receipts/malformed-stage.json`.
- The physical keyboard UI stayed disabled and did not expose ready status:
  `notes/receipts/malformed-keyboard.json`.
- A complete snapshot was enabled, inserted exactly once, and then cleared to
  idle:
  `notes/receipts/complete-before-insert.json`,
  `notes/receipts/after-insert.json`, and
  `notes/receipts/after-insert-app-group.json`.
- Focused Swift tests passed:
  `FoilKeyboardBridgeTests` and `FoilDictationLoopPresentationTests`, 17 tests
  with 0 failures.

## Residual Risk

The physical receipt uses a sterile Safari fixture. App-specific keyboard
refresh behavior in Messages, Notes, and third-party apps should remain in the
next app-matrix board, but the stale/malformed/exact-once state-safety claim is
proved for this slice.

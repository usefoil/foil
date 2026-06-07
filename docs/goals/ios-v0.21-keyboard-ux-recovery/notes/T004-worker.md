# T004 Worker Receipt: Physical Keyboard UI Proof

## Claim

Once WDA automation was unblocked, the v0.21 keyboard recovery slice behaved
correctly on the physical iPhone preview in a sterile Safari text field:

- stale non-complete App Group snapshots do not enable insertion;
- complete snapshots enable Insert latest;
- tapping Insert latest inserts the transcript exactly once and clears the App
  Group snapshot back to idle;
- malformed App Group JSON does not expose a ready transcript or an enabled
  Insert latest button.

## Environment

- Device: iPhone preview over CoreDevice tunnel.
- Sterile target: local Safari fixture at
  `docs/goals/ios-v0.21-keyboard-ux-recovery/notes/fixture/index.html`.
- UI automation: WebDriverAgent endpoint reported ready after macOS
  DevToolsSecurity was enabled.
- Raw transcript text, WDA XML, screenshots, private phone content, and
  credentials were not committed.

## Evidence

- `notes/receipts/status-wda-after-devtools.json`: physical phone visible and
  WDA ready after the operator enabled DevToolsSecurity.
- `notes/receipts/safari-ready.json`: Safari loaded the sterile fixture and the
  target text field was available.
- `notes/receipts/stale-stage.json`: staged a `processing` snapshot with a
  leftover transcript, recorded by phase, length, and hash only.
- `notes/receipts/stale-keyboard.json`: Foil Keyboard was active, Insert latest
  was disabled, and `Transcript ready` was not exposed.
- `notes/receipts/complete-stage.json`: staged a `complete` snapshot with a
  transcript, recorded by phase, length, and hash only.
- `notes/receipts/complete-before-insert.json`: Foil Keyboard was active, Insert
  latest was enabled, and `Transcript ready` was exposed.
- `notes/receipts/after-insert.json`: after tapping Insert latest, the sterile
  field contained exactly one matching transcript occurrence and Insert latest
  was disabled.
- `notes/receipts/after-insert-app-group.json`: after insertion, the App Group
  snapshot was idle with no transcript.
- `notes/receipts/malformed-stage.json`: malformed JSON was written and read
  back byte-for-byte.
- `notes/receipts/malformed-keyboard.json`: malformed state kept Insert latest
  disabled and did not expose `Transcript ready`.
- `notes/receipts/final-reset.json`: final cleanup left the App Group snapshot
  idle with no transcript.

## Commands

```bash
/usr/sbin/DevToolsSecurity -status
scripts/ios-physical-harness.py status --wda-url http://192.168.1.40:8100
python3 -m http.server 8945 --bind 0.0.0.0
scripts/ios-physical-harness.py stage-transcript --transcript '<sterile transcript>' --message 'v0.21 complete fixture'
scripts/ios-physical-harness.py reset-transcript
xcodebuild test -project FoiliOS/FoilIOS.xcodeproj -scheme FoilIOS -destination 'id=3078C4C7-E3E0-448A-B6AB-8AFE7A39F440' -only-testing:FoilIOSTests/FoilKeyboardBridgeTests -only-testing:FoilIOSTests/FoilDictationLoopPresentationTests
```

The focused Swift test run passed 17 selected tests with 0 failures.

## Strongest Realistic Failure Modes

Stale leftover transcript inserts anyway:
ruled out by `stale-stage.json` plus `stale-keyboard.json`, which prove a
non-complete snapshot with transcript bytes leaves Insert latest disabled and
does not expose ready status.

Complete transcript fails to insert, duplicates, or remains reusable:
ruled out by `complete-before-insert.json`, `after-insert.json`, and
`after-insert-app-group.json`, which prove enabled-before, exactly-one text
occurrence after tap, disabled-after, and App Group idle cleanup.

Malformed App Group JSON enables a bad insert state:
ruled out by `malformed-stage.json` and `malformed-keyboard.json`, which prove
the malformed bytes were present and the keyboard stayed disabled with no ready
status.

## Residual Risk

This proves the core state and insertability behavior on a sterile Safari field.
It does not claim that every third-party app refreshes custom keyboard extension
state identically; future boards should continue broad app-matrix testing.

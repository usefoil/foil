# T002 Judge Receipt: First Implementation Slice

## Decision

Approved. The first Worker should implement Slice A as one coherent package: make Foil's intentional other-audio policy explicit, default-unaffected, and testable without relying on Bluetooth hardware.

## Rationale

Scout found the current default is already off at the preference level, but the product still lacks the goal oracle's explicit proof boundary:

- No top-level diagnostic says Foil is leaving other audio unaffected by policy.
- The setting is under Experimental/Browser Media, while the user concern is "other audio while recording."
- Existing tests cover the controller in isolation, but not the app-facing policy language or diagnostic contract.
- Bluetooth/device behavior is real but separate and should not block the binary policy fix.

The largest safe first slice is therefore UI copy + diagnostics + tests around the existing opt-in browser pause path. It avoids unsupported universal audio control and does not require hardware-specific verification.

## Worker Objective

Implement a default-safe binary other-audio policy surface:

- Keep default behavior as "other audio unaffected."
- Keep browser-media pausing opt-in only.
- Add clear diagnostics for the selected policy on recording start.
- Clarify settings copy so users understand Foil can optionally pause supported browser media, not universally control all audio.
- Add focused tests proving disabled/default policy does not run browser control and enabled policy does.

## Allowed Files

- `Foil/BrowserMediaController.swift`
- `Foil/FoilApp.swift`
- `Foil/AppState.swift`
- `Foil/SettingsView.swift`
- `Foil/Info.plist`
- `FoilTests/BrowserMediaControllerTests.swift`
- `FoilTests/DiagnosticLogTests.swift`
- `FoilTests/AppStateTests.swift`
- `docs/goals/other-audio-recording-policy/state.yaml`
- `docs/goals/other-audio-recording-policy/notes/`

The Worker should edit only the subset needed.

## Verify

- `xcodebuild test -project Foil.xcodeproj -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/BrowserMediaControllerTests`
- `xcodebuild test -project Foil.xcodeproj -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/AppStateTests`
- Add `DiagnosticLogTests` only if diagnostics helpers are changed.
- If Xcode test execution is blocked by local environment, run Swift parse checks and record the blocker.

## Stop If

- The implementation would imply system-wide audio control.
- The implementation would use private APIs, Accessibility UI scripting, or third-party app volume manipulation.
- Persisted opt-in behavior would be silently changed without an explicit migration decision.
- The needed files exceed the allowed file list.

## Deferred Bluetooth/macOS Follow-Up

After this slice, activate the Bluetooth/input-mode Scout. It should decide whether to implement input-device warning/detection using public Core Audio transport metadata, or record docs/manual guidance if hardware or API evidence is insufficient.

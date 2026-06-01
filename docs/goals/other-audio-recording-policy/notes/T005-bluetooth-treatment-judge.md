# T005 Judge Receipt: Bluetooth/Input-Mode Treatment

## Decision

Approved for implementation.

## Rationale

The T004 evidence is strong enough for a bounded product treatment:

- The local machine is in a risky state: AirPods are the default input, transported by Bluetooth.
- Apple documents reduced audio quality/volume when a Bluetooth headphone microphone is used.
- Core Audio exposes public transport metadata through `kAudioDevicePropertyTransportType`.
- Foil already has input-device enumeration, so this can be added without private APIs or system-wide audio control.

This should be implemented as guidance/warning only. It must not block recording and must not claim Foil can prevent Bluetooth profile switching.

## Worker Objective

Add Bluetooth input awareness:

- Extend `AudioRecorder.AudioDevice` with transport metadata sufficient to identify Bluetooth and Bluetooth LE input devices.
- Add helpers for resolving the effective recording input when the user chooses either System Default or a specific input device.
- Show a warning in Recording settings when the effective input is Bluetooth/Bluetooth LE.
- Include effective input transport in diagnostics/setup reports if practical.
- Add focused unit tests for transport mapping and diagnostics.

## Allowed Files

- `Foil/AudioRecorder.swift`
- `Foil/SettingsView.swift`
- `Foil/DiagnosticLog.swift`
- `FoilTests/AudioRecorderTests.swift`
- `FoilTests/DiagnosticLogTests.swift`
- `docs/goals/other-audio-recording-policy/state.yaml`
- `docs/goals/other-audio-recording-policy/notes/`

## Verify

- `xcodebuild test -project Foil.xcodeproj -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/AudioRecorderTests`
- `xcodebuild test -project Foil.xcodeproj -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/DiagnosticLogTests`
- `git diff --check`

## Stop If

- The implementation needs private APIs.
- The warning cannot be specific to Bluetooth/Bluetooth LE input.
- It would block recording.
- It requires unavailable hardware to compile or unit-test the core mapping.

# T004 Scout Receipt: macOS/Bluetooth Input-Mode Quieting

## Summary

The Bluetooth/input-mode concern is real and locally relevant. This Mac currently reports AirPods as both the default input and default output, with the input transported over Bluetooth. Apple documents that when an app uses a Bluetooth headphones' microphone, macOS can switch Bluetooth into a speak+listen mode where audio quality and volume are reduced until the microphone is no longer in use.

Foil can safely detect Bluetooth input devices through public Core Audio metadata. The best product treatment is an in-app warning in Recording settings when the selected recording input, or the system default input, is Bluetooth/Bluetooth LE. Foil should recommend using the Mac microphone or another non-Bluetooth mic if the user wants other audio to remain unchanged. Foil should not promise to prevent the OS-level Bluetooth profile switch.

## Local Evidence

`system_profiler SPAudioDataType` on this Mac reports:

- `AirPods`
  - Default Input Device: yes
  - Input Channels: 1
  - Current SampleRate: 24000
  - Transport: Bluetooth
- `AirPods`
  - Default Output Device: yes
  - Output Channels: 2
  - Current SampleRate: 48000
  - Transport: Bluetooth
- `Mac mini Speakers`
  - Default System Output Device: yes
  - Transport: Built-in

This is exactly the risky configuration: Foil recording with system-default input will use a Bluetooth headset mic.

## Public API Evidence

The macOS SDK's `AudioHardwareBase.h` documents:

- `kAudioDevicePropertyTransportType`, a `UInt32` indicating how the audio device is connected.
- `kAudioDeviceTransportTypeBluetooth`.
- `kAudioDeviceTransportTypeBluetoothLE`.
- `kAudioDeviceTransportTypeBuiltIn`, `USB`, `Virtual`, and other transport values.

Foil already enumerates input devices in `AudioRecorder.availableInputDevices()` using Core Audio. Extending `AudioRecorder.AudioDevice` with transport metadata is a small, public-API-based change.

## Apple Behavior Evidence

Apple Support documents that if music or other audio is playing through Bluetooth headphones and an app uses the headphones' microphone, audio quality and volume are reduced. Apple describes two Bluetooth modes: one for higher-quality listening and another for simultaneous microphone + listening, with reduced quality until the microphone is no longer in use.

Source: https://support.apple.com/en-us/102217

## Recommended Product Treatment

Implement a warning, not a fake control:

- If `selectedInputDeviceUID == nil`, inspect the current system default input device.
- If `selectedInputDeviceUID` is set, resolve that device.
- If the effective input transport is Bluetooth or Bluetooth LE, show a Recording settings warning:
  - "Bluetooth microphone selected"
  - "Using a Bluetooth headset microphone can reduce other audio quality or volume while recording. To keep playback unchanged, choose the Mac microphone or another non-Bluetooth input."
- Keep recording functional; this is guidance, not a blocker.
- Add diagnostics/setup report metadata for effective input transport if feasible.

## Candidate Worker Task

Objective:

Add public Core Audio transport metadata to input-device enumeration and show a Recording settings warning when the effective recording input is Bluetooth/Bluetooth LE.

Allowed files:

- `Foil/AudioRecorder.swift`
- `Foil/SettingsView.swift`
- `Foil/DiagnosticLog.swift`
- `FoilTests/AudioRecorderTests.swift`
- `FoilTests/DiagnosticLogTests.swift`
- `docs/goals/other-audio-recording-policy/state.yaml`
- `docs/goals/other-audio-recording-policy/notes/`

Verification:

- `xcodebuild test -project Foil.xcodeproj -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/AudioRecorderTests`
- `xcodebuild test -project Foil.xcodeproj -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/DiagnosticLogTests`

Stop if:

- The implementation needs private APIs.
- The warning cannot be made specific to Bluetooth/Bluetooth LE input.
- It would block recording rather than guide the user.

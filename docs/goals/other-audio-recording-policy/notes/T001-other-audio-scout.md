# T001 Scout Receipt: Other Audio Recording Policy

## Summary

Foil has one intentional code path that can affect other apps' audio: the experimental browser media controller. It is currently scoped to Chrome/Chromium, implemented through Apple Events + fixed JavaScript, and gated by `AppState.pauseBrowserMediaWhileRecording`, which defaults to `false`.

The suspected "all other audio is silenced" behavior can also come from macOS/Bluetooth device behavior when a Bluetooth headphone microphone is used. Apple documents that Bluetooth headphones have a higher-quality listening mode and a lower-quality speak+listen mode; when an app uses the Bluetooth headphone mic, audio quality and volume can be reduced until the microphone is no longer in use.

## Current Code Paths That Can Affect Other Audio

- Intentional Foil browser pausing:
  - `Foil/FoilApp.swift` wires `BrowserMediaController` with `isEnabled: appState.pauseBrowserMediaWhileRecording == true`.
  - `recordingControllerDidStart` calls `browserMediaController.recordingDidStart()`, then asynchronously calls `pausePlayingMedia(for:)` only if a session ID is returned.
  - `Foil/BrowserMediaController.swift` returns `.disabled` and does not invoke the runner when `isEnabled()` is false.
  - `ChromeBrowserMediaScriptRunner` only checks Chrome/Chromium bundle IDs, then runs JavaScript that pauses playing `audio`/`video` elements.
  - Diagnostics are privacy-safe counts/categories: disabled, browser not running, attempted tabs/paused/failures, failed category.

- Foil recording capture:
  - `Foil/AudioRecorder.swift` uses `AVAudioEngine` input node taps and optional Core Audio input-device selection via `AudioUnitSetProperty(... kAudioOutputUnitProperty_CurrentDevice ...)`.
  - No `AVAudioSession`, audio session category, ducking option, system-wide mute, output-volume control, or third-party app volume control was found in Foil.

- Foil sound cues:
  - `Foil/SoundPlayer.swift` plays Foil's own start/end cues through `AVAudioPlayer`/`NSSound`.
  - This controls Foil-owned cue volume only; it does not mute or duck other apps.

## Defaults and Persistence

- `Foil/AppState.swift` registers `"pauseBrowserMediaWhileRecording": false`.
- `AppState.init()` loads the persisted value with `defaults.bool(forKey:)`.
- `--reset-defaults` removes `pauseBrowserMediaWhileRecording` and UI testing reset sets it to `false`.
- Existing users who manually enabled the setting can keep seeing browser pauses because the persisted value remains true. This is product-relevant: default is safe, but a user report may be caused by an old opt-in setting.

## Current UI and Copy

- The setting lives in `SettingsView.experimentalSettings` under `Section("Browser Media")`.
- Toggle label: `Pause browser media while recording`.
- Help text: `Experimental. Chrome and Chromium only. Chrome must allow JavaScript from Apple Events.`
- `Info.plist` usage description is explicit: Apple Events are used to pause browser media in Chrome/Chromium while recording when the experimental setting is enabled.

Scout read: the current copy is honest about browser scope, but the user-facing concept requested now is broader: "other audio while recording" should default to unaffected. The first implementation should probably keep the honest browser scope while adding explicit default-unaffected diagnostics/copy.

## Existing Tests and Missing Tests

Existing useful coverage:

- `FoilTests/BrowserMediaControllerTests.swift`
  - disabled state skips runner and returns `.disabled`.
  - enabled state runs the runner.
  - ending a recording prevents a late async pause.
  - Chrome AppleScript source compiles.
  - combined summaries behave correctly.

- `FoilTests/AudioRecorderTests.swift`
  - current device enumeration returns input devices with non-empty UIDs.
  - no transport-type metadata is covered yet.

Missing for the goal oracle:

- A test or app-level seam proving `AppDelegate.recordingControllerDidStart` does not attempt browser/media pausing by default.
- A diagnostics assertion for the default policy language, e.g. `otherAudio: unaffected` or equivalent.
- A migration/default test proving fresh defaults are off and persisted opt-in behavior is deliberate.
- UI/copy test coverage for the setting label/help if the setting moves or is renamed.
- Device metadata tests if Bluetooth input warnings are added.

## Manual Smoke Matrix Needed

The manual matrix should separate Foil policy from OS/device routing:

| Scenario | Expected default behavior | Evidence |
| --- | --- | --- |
| Chrome tab playing HTML media, setting off | Foil does not pause the tab | Chrome continues; diagnostics show default/unaffected or browser control disabled |
| Chrome tab playing HTML media, setting on | Foil pauses supported Chrome/Chromium media | Chrome pauses; diagnostics show attempted tabs/paused/failures |
| Music/Spotify/system audio, setting off | Foil does not intentionally affect it | Playback continues unless OS/device mic route changes |
| Built-in mic + built-in speakers/output | Other audio should continue normally | Manual recording smoke |
| Built-in mic + Bluetooth output | Other audio should continue unless system routes output strangely | Manual recording smoke |
| Bluetooth headset mic + Bluetooth output | Audio may reduce/quiet due to OS Bluetooth mode | Record device names + diagnostics; compare with Apple support behavior |

## Bluetooth / macOS Evidence

- Apple Support article "If sound quality is reduced when using Bluetooth headphones with your Mac" says that when an app uses a Bluetooth headphones' microphone, audio quality and volume are reduced; Bluetooth has one mode for higher-quality listening and another mode for speaking plus listening, with reduced quality until the microphone is no longer in use.
  - Source: https://support.apple.com/en-us/102217
- Core Audio SDK headers expose `kAudioDevicePropertyTransportType` plus transport constants including `kAudioDeviceTransportTypeBluetooth` and `kAudioDeviceTransportTypeBluetoothLE`.
  - Local evidence: `AudioHardwareBase.h` in the macOS SDK.

Safe implication: Foil can likely detect/warn about Bluetooth input devices through public Core Audio metadata, but Foil should not promise a universal fix for Bluetooth mode switching. The likely product treatment is guidance or a warning that recommends using the Mac microphone or a non-Bluetooth mic while keeping Bluetooth headphones as output.

## Candidate Worker Slices

### Slice A: Default-safe binary policy, UI copy, diagnostics, tests

Objective:

Make Foil's intentional other-audio policy explicit and verifiable: default is unaffected; supported browser pausing is opt-in.

Likely allowed files:

- `Foil/AppState.swift`
- `Foil/FoilApp.swift`
- `Foil/BrowserMediaController.swift`
- `Foil/SettingsView.swift`
- `FoilTests/BrowserMediaControllerTests.swift`
- `FoilTests/DiagnosticLogTests.swift` or a focused app-state/settings test if available
- Maybe `Foil/Info.plist` if copy changes

Verification ideas:

- `xcodebuild test -project Foil.xcodeproj -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/BrowserMediaControllerTests`
- focused tests covering defaults/diagnostics if added
- parse/build check if full Xcode test is too slow

Stop if:

- UI copy implies system-wide control.
- Implementation requires private API or controlling third-party app volume.
- Persisted opt-in migration behavior is ambiguous.

### Slice B: Bluetooth input warning/detection

Objective:

Expose Bluetooth input risk without pretending Foil can control macOS Bluetooth profile switching.

Likely allowed files:

- `Foil/AudioRecorder.swift`
- `Foil/SettingsView.swift`
- `FoilTests/AudioRecorderTests.swift`
- Maybe docs/manual smoke matrix.

Verification ideas:

- unit tests for transport metadata mapping if implemented through a testable helper
- manual inspection of available input devices if local hardware exists

Stop if:

- Detection requires private APIs.
- Local hardware is unavailable and no test seam can prove behavior.
- The design would warn too broadly without reliable signal.

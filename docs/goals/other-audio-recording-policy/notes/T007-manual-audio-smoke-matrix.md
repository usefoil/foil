# T007 Manual Audio Smoke Matrix

## Purpose

This matrix is the remaining proof for the other-audio policy oracle. Automated tests prove Foil's intentional policy path, but only a local manual smoke can prove what the user actually hears while recording.

## Precheck Evidence

- Current branch: `codex/other-audio-recording-policy`
- GoalBuddy update check: current `0.3.8`, latest `0.3.7`, no update available.
- Debug app build: `xcodebuild -project Foil.xcodeproj -scheme Foil -destination 'platform=macOS' build` passed on June 1, 2026.
- Build note: Xcode emitted the existing CoreSimulator out-of-date warning, but the macOS app build succeeded.
- Debug bundle path: `/Users/jeremywatt/Library/Developer/Xcode/DerivedData/Foil-fxfrtzwwzpscfhcbntvmjqudewab/Build/Products/Debug/Foil.app`
- Focused current-state XCTest evidence:
  - `Test-Foil-2026.06.01_11-12-54--0700.xcresult`: 6 selected tests passed for default policy, persisted opt-in, disabled browser media logging, and Bluetooth transport metadata.
  - `Test-Foil-2026.06.01_11-13-12--0700.xcresult`: 4 selected tests passed for enabled browser-media diagnostics and diagnostics/setup report policy/transport strings.
- A broader combined focused-suite rerun was interrupted after it stopped making progress and left a debug Foil test process running; the process was cleaned up, and the narrower current-state test commands above passed.
- Apple Events permission copy is bounded to the opt-in browser media setting:
  - `Foil uses Apple Events only when you enable the setting to pause supported browser media in Chrome and Chromium while recording.`
- Local audio configuration from `system_profiler SPAudioDataType`:
  - AirPods are default input, transport Bluetooth.
  - AirPods are default output, transport Bluetooth.
  - Mac mini Speakers are default system output, transport Built-in.
- This is a valid Bluetooth-risk configuration for testing the new warning.
- Later visual-only dev-app check:
  - Launched the debug app in UI-testing mode and opened Recording settings without starting a recording or changing macOS privacy settings.
  - Recording settings showed the opt-in `Pause supported browser media while recording` toggle off by default and its bounded Chrome/Chromium-only help copy.
  - By that time, `system_profiler SPAudioDataType` reported only Mac mini Speakers and no input device; a Core Audio default-input query returned device `0`.
  - Because no Bluetooth input was currently present, the Bluetooth warning row could not be visually executed; the warning was not shown in that no-Bluetooth-input state.
  - The debug Foil process was quit after inspection; no `Foil.app`, `xcodebuild`, or XCTest processes remained.
- Runtime setup report check:
  - Launched the debug app in UI-testing mode and used its `Copy Setup Report` control without starting a recording or changing permissions.
  - The copied report included `Input Device UID: System Default`, `Input Device Transport: Unknown`, and `Other Audio While Recording: unaffected`.
  - The debug Foil process was quit after inspection; no `Foil.app`, `xcodebuild`, or XCTest processes remained.
- Existing production preference precheck: `defaults read com.neonwatty.Foil pauseBrowserMediaWhileRecording` returned no value, so no production opt-in value was observed from that domain during this check.

## Auto-Verifiable App Evidence

- Default policy code path logs `otherAudio: unaffected policy=none`.
- Disabled browser media path logs `browserMediaControl: skipped disabled`.
- Opt-in policy code path logs `otherAudio: pauseBrowserMedia enabled scope=chrome+chromium`.
- Diagnostics export includes `Input Device Transport: ...` and `Other Audio While Recording: ...`.
- Setup report includes `- Input Device Transport: ...` and `- Other Audio While Recording: ...`.
- Recording settings includes the opt-in toggle `Pause supported browser media while recording`.
- Recording settings includes Bluetooth input warning accessibility id `settings.bluetoothInputWarning`.
- Diagnostics log path for the built app is `~/Library/Application Support/Foil Dev/Diagnostics/foil.log` for the dev bundle, or `~/Library/Application Support/Foil/Diagnostics/foil.log` for production.

## Matrix

| Scenario | Setup | Action | Expected Result | Evidence |
| --- | --- | --- | --- | --- |
| Browser media, setting off | Chrome/Chromium playing media; `Pause supported browser media while recording` off | Start/stop Foil recording | Browser media continues; diagnostics show `otherAudio: unaffected policy=none` | Operator audible result pending |
| Browser media, setting on | Chrome/Chromium playing media; setting on; Chrome Apple Events JS allowed | Start/stop Foil recording | Supported browser media pauses; diagnostics show `otherAudio: pauseBrowserMedia enabled scope=chrome+chromium` and browser media control attempt/result | Operator audible result pending |
| Non-browser audio, non-Bluetooth mic | Music/system audio playing; input set to built-in/non-Bluetooth mic if available | Start/stop Foil recording | Other audio continues normally | Operator audible result pending |
| Bluetooth headset mic | AirPods or another Bluetooth headset selected/default as input | Open Recording settings, start/stop recording | Warning appears; any audio quality/volume reduction is treated as OS Bluetooth mode behavior, not Foil policy | Pending; visual check attempted after Bluetooth input disappeared, so precondition was not met |

## Operator Runbook

1. Launch the dev app from `/Users/jeremywatt/Library/Developer/Xcode/DerivedData/Foil-fxfrtzwwzpscfhcbntvmjqudewab/Build/Products/Debug/Foil.app`.
2. Open Recording settings.
3. For the first row, keep `Pause supported browser media while recording` off, start Chrome/Chromium media, start and stop a Foil recording, then record whether the media audibly continued.
4. For the second row, turn the setting on, allow the Chrome/Chromium Apple Events prompt if macOS shows one, start and stop a Foil recording, then record whether browser media paused.
5. For the third row, select a non-Bluetooth input if available, play non-browser audio, start and stop a Foil recording, then record whether the audio continued normally.
6. For the fourth row, select AirPods or another Bluetooth headset input, confirm the Recording settings warning appears, start and stop a Foil recording, then record any heard audio quality/volume change as OS/device behavior.
7. Capture the matching diagnostics lines from the relevant log:
   - Dev: `~/Library/Application Support/Foil Dev/Diagnostics/foil.log`
   - Production: `~/Library/Application Support/Foil/Diagnostics/foil.log`

## Operator Notes Needed

Record the actual observed audible result for each row. The final audit should not mark this goal complete until at least the default-off rows prove Foil does not intentionally pause/silence/dampen other audio.

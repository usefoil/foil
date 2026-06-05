# T012 Live Command Mailbox Smoke Receipt

Date: 2026-06-05
Device: iPhone-preview
CoreDevice id: 5320F5AD-2A71-50AC-94FE-207B544B6247
Branch: codex/ios-live-command-mailbox

## Claim

Foil iOS now has an App Group command mailbox that lets the physical-device
automation drive the containing app's live recorder and transcription flow
without relying on offscreen SwiftUI controls or `devicectl --payload-url`
delivery. A Debug device build used the mailbox to record Mac speaker audio,
transcribe it through Groq, insert the result through Foil Keyboard into Notes,
and clear the shared transcript.

## Change

- Added `FoilIOSCommand` and `FoilIOSCommandAction` to the shared iOS bridge.
- The containing app now polls `Library/foil-ios-command.json` in the existing
  App Group and handles one command id once.
- Supported commands are:
  - `startRecording`
  - `stopRecording`
  - `transcribeLatest`
  - `resetSharedState`
  - `completeFakeTranscript`
- Bumped the iOS build number from `1` to `2` for the next TestFlight upload.
- Uploaded build `0.1.0 (2)` to App Store Connect/TestFlight.

## Physical Evidence

### Automation Surface

Strongest realistic failure mode: The mailbox file is copied to the device, but
the app does not observe it or does not execute the recorder actions.

Evidence:

- `xcodebuild -project FoiliOS/FoilIOS.xcodeproj -scheme FoilIOS -configuration Debug -destination 'id=00008030-001A0C980A33C02E' ... build`
  succeeded on the physical-device destination.
- The Debug app installed with `devicectl device install app`.
- Writing an App Group command with `action = startRecording` changed
  `Library/foil-keyboard-snapshot.json` to `phase = listening` and message
  `Recording in Foil. Stop when finished.`
- Writing `action = stopRecording` changed the snapshot to `phase = processing`
  and message `Recording saved. Tap Transcribe in Foil.`
- Writing `action = transcribeLatest` changed the snapshot to `phase = complete`
  and message `Groq transcript ready. Switch back and tap Insert latest.`

### TestFlight Upload

Strongest realistic failure mode: The mailbox works in a local Debug build, but
the archived/TestFlight artifact fails validation or never reaches App Store
Connect.

Evidence:

- Release archive succeeded at `/tmp/FoilIOS-LiveCommandMailbox.xcarchive`.
- Export succeeded to `/tmp/FoilIOS-LiveCommandMailboxExport/Foil iOS.ipa`.
- IPA metadata inspection showed app version `0.1.0`, app build `2`, and
  keyboard extension build `2`.
- `xcrun altool --validate-app ...` reported `VERIFY SUCCEEDED with no errors`.
- `xcrun altool --upload-app ...` reported `UPLOAD SUCCEEDED with no errors`.
- Delivery UUID: `9d60d9c5-45d4-42d8-9104-9d7541ddbecf`.
- `xcrun altool --build-status --delivery-id 9d60d9c5-45d4-42d8-9104-9d7541ddbecf ...`
  reported `build-status = VALID`, `import-status = VALID`,
  `is-on-app-store-connect = true`, and `uses-non-exempt-encryption = false`.

Residual risk / follow-up:

- The preview phone currently has a Debug-installed build `2` from mailbox
  validation. Install/update the TestFlight-managed build `2` before claiming
  distributed-install proof for this mailbox.

### Audio Source

Strongest realistic failure mode: Groq completes, but the recording did not
capture the intended spoken phrase.

Evidence:

- Two attempts while macOS output was routed to AirPods completed with transcript
  `"."`, proving the failure mode was real.
- `blueutil` was installed, AirPods were disconnected, and CoreAudio was
  verified with `MacBook Pro Speakers` as both default output and system output.
- After replaying the phrase through MacBook Pro Speakers, Groq returned:
  `FOIL live dictation test June 5 purple banana chords foil live dictation test June 5 purple banana chords foil live dictation test June 5 purple banana cords`
- The intended phrase was repeated three times:
  `Foil live dictation test June five. Purple banana quartz.`

Residual risk / follow-up:

- The phrase was recognized with expected microphone/provider variation
  (`quartz` as `chords`/`cords`). Product-level dictation quality remains a
  separate evaluation.

### Keyboard Insertion And Reset

Strongest realistic failure mode: The transcript is produced in shared state,
but Foil Keyboard cannot insert it into the host field or fails to clear it.

Evidence:

- Notes was launched after live transcription.
- WDA switched from the system keyboard to Foil Keyboard and observed:
  - `foil-keyboard-status = Transcript Ready`
  - `foil-keyboard-message = Groq transcript ready. Switch back and tap Insert latest.`
  - enabled `foil-keyboard-insert-latest`
- After tapping `foil-keyboard-insert-latest`, the Notes `TextView` value
  appended the live transcript after the existing sterile test text.
- Foil Keyboard reset to `Ready`, with disabled `Insert latest (no transcript)`.
- The canonical App Group snapshot copied back from the device showed
  `phase = idle`, `hasTranscript = false`, `message = Ready`, and transcript
  length `0`.
- Screenshot: ![Live speaker transcript inserted](visual/live-speaker-notes-insert-reset.png)

Residual risk / follow-up:

- The current TestFlight build still lacks the mailbox. Build `2` is required
  before this becomes a distributed-app proof.

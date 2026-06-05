# T011 TestFlight Install Keyboard Smoke Receipt

Date: 2026-06-05
Device: iPhone-preview
CoreDevice id: 5320F5AD-2A71-50AC-94FE-207B544B6247
Branch: codex/ios-testflight-smoke-receipt

## Claim

The TestFlight build can be installed on the preview iPhone, launched through
CoreDevice, configured with the local Groq key through the app UI, and used by
Foil Keyboard to insert a pending transcript into Notes once, after which the
keyboard and canonical App Group snapshot reset to no-transcript state.

## Physical Evidence

### TestFlight Install And Launch

Strongest realistic failure mode: TestFlight reports an accepted invite, but the
build is not actually installed or cannot launch on the preview iPhone.

Evidence:

- `xcrun devicectl device info apps --device 5320F5AD-2A71-50AC-94FE-207B544B6247`
  listed `Foil iOS`, bundle `com.neonwatty.FoilIOS`, version `1.0`, build `1`.
- `xcrun devicectl device process launch --device 5320F5AD-2A71-50AC-94FE-207B544B6247 com.neonwatty.FoilIOS --terminate-existing`
  returned `Launched application with com.neonwatty.FoilIOS bundle identifier`.
- WDA source after launch showed app `Foil iOS`, navigation title `Foil`,
  `Keyboard shell ready`, `Microphone allowed`, and keyboard health already
  verified with Full Access on.

Residual risk / follow-up:

- `devicectl` reports installed version `1.0` while App Store Connect metadata
  for the uploaded build was `0.1.0` build `1`. Confirm the marketing version
  mapping before the next external-facing beta.

### Provider Key Configuration

Strongest realistic failure mode: The app accepts automation input but does not
actually save a usable provider key, or the key leaks into logs or receipts.

Evidence:

- The local key was read from Keychain and only its length was printed.
- WDA typed the key into `provider-key-field` and tapped
  `save-provider-key-button`; both responses were `ok`.
- WDA source after saving showed `Groq key configured` and `Groq key saved`.
- The saved receipt includes no key value, no token, and no raw request body.
- Screenshot: ![TestFlight key configured](visual/testflight-key-configured.png)

Residual risk / follow-up:

- This proves keychain-backed UI configuration and readiness, not a fresh live
  transcription request. A live speech-to-Groq receipt remains covered by the
  prior T010 physical-device spoken phrase smoke.

### Keyboard Insertion

Strongest realistic failure mode: Foil Keyboard appears in Notes, but tapping
`Insert latest` does not change the host text field.

Evidence:

- A sterile App Group snapshot was copied to the device at
  `Library/foil-keyboard-snapshot.json` and copied back for verification. The
  readback showed `phase = complete`, `hasTranscript = true`,
  `message = Fake transcript ready`, and transcript length `19`.
- Notes was launched with `com.apple.mobilenotes`, a fresh note was opened, and
  the system keyboard switcher changed to Foil Keyboard.
- WDA source before insertion showed:
  - `foil-keyboard-root`
  - `foil-keyboard-status = Transcript Ready`
  - `foil-keyboard-message = Fake transcript ready`
  - enabled `foil-keyboard-insert-latest`
- After tapping `foil-keyboard-insert-latest`, WDA source showed the Notes
  `TextView` value exactly `Foil keyboard shell`.

Residual risk / follow-up:

- This is a sterile seeded-transcript keyboard insertion smoke. The real
  microphone/provider path was not rerun in this receipt because it needs an
  intentional audible phrase on the physical device.

### Post-Insert Reset

Strongest realistic failure mode: The keyboard UI looks reset, but stale
canonical App Group file state can still reinsert the transcript later.

Evidence:

- After insertion, WDA source showed Foil Keyboard status `Ready`, message
  `Ready`, disabled `Insert latest (no transcript)`, and disabled
  `Clear latest (ready)`.
- The canonical App Group file was copied back from
  `Library/foil-keyboard-snapshot.json`; readback showed `phase = idle`,
  `hasTranscript = false`, `message = Ready`, and transcript length `0`.
- Screenshot: ![Notes insertion and reset](visual/testflight-notes-insert-reset.png)

Residual risk / follow-up:

- Repeat this against Reminders, Messages, Safari, and secure fields only from
  privacy-safe blank targets.
- The containing app's URL seed route `foilios://complete` did not update the
  snapshot through `devicectl --payload-url`; keep using the UI diagnostic
  control or direct App Group seed for automation until that route is verified.

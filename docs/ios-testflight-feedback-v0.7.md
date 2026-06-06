# Foil iOS v0.7 TestFlight Feedback Handoff

Audience: internal TestFlight testers for Foil Dictation.

## Build To Test

- App: Foil Dictation / Foil iOS
- Bundle ID: `com.neonwatty.FoilIOS`
- Current source metadata: `0.1.0 (7)`
- Current iPhone-preview install: `0.1.0 (7)`
- App Store Connect: builds `1` through `7` are `VALID`, not expired, and have `usesNonExemptEncryption: false`.
- Internal group: `Foil Internal Testers`
- Tester state: installed

Build `7` is the v0.7 feedback target. Do not describe Messages support as proven.

## What Is Proven

- The physical iPhone-preview can launch Foil iOS build 7.
- The Foil Keyboard can read shared App Group state when Full Access is enabled.
- A sterile spoken phrase can be recorded in the containing app, transcribed through Groq, and made available to the keyboard.
- The keyboard can insert the latest transcript into a sterile Safari/local fixture and then reset shared App Group state.
- Secure password fields reject the custom keyboard as expected; the transcript remains staged and is not inserted.
- Earlier physical boards proved Notes and Reminders insertion/reset, but those rows were not freshly rerun in the v0.7 matrix.

## Known Gaps

- Messages is not tested. It needs a dedicated sterile self/test thread before automation or screenshots are allowed.
- Secure fields are not supported by design.
- Testers may need to switch away and back to the target app, or cycle keyboards, to refresh the custom keyboard.
- Full Access is required for this prototype architecture.
- This is internal prototype credential handling, not production account/server auth.

## Tester Flow

1. Install or update Foil Dictation from TestFlight.
2. Open Settings -> General -> Keyboard -> Keyboards.
3. Add Foil Keyboard, then enable Allow Full Access.
4. Open Foil Dictation once and verify the setup/health screen is not reporting a blocked state.
5. In a safe target app, place the cursor in a blank text field.
6. Switch to Foil Keyboard.
7. Use Foil to record a short non-private phrase.
8. Return to the target app and tap Insert latest once.
9. Confirm the text inserted once and the keyboard returns to no-transcript/ready state.

Use non-private phrases only, such as:

- `violet cactus number one`
- `silver compass number two`
- `green lantern number three`

## Recovery Steps

- If Foil Keyboard does not appear: cycle keyboards, then tap back into the text field.
- If Insert latest is disabled: open Foil Dictation and check setup/health.
- If Full Access is off: enable it in Keyboard settings, then reopen the target field.
- If the transcript is stale or wrong: use Reset shared state in Foil Dictation and record again.
- If recording or transcription fails: reopen Foil Dictation and retry with a short phrase.

## Feedback To Send

Please send:

- iPhone model and iOS version.
- TestFlight build number.
- Target app and field type.
- Whether keyboard switching was required.
- Whether Full Access was enabled.
- Whether recording, transcription, insertion, and reset each worked.
- Whether recovery steps helped.

Please do not send:

- private transcript text
- Messages screenshots
- contacts, phone numbers, account names, or private app content

## Claim Boundary

Safe claim: Foil iOS build 7 is ready for internal feedback on the app-to-keyboard dictation loop, with known friction around Full Access and keyboard refresh.

Unsafe claim: Foil works across arbitrary iPhone apps or in Messages. Messages remains blocked until a sterile thread exists.

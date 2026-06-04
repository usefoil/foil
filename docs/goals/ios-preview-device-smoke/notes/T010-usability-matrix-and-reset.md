# T010 Usability Matrix And Reset Receipt

Date: 2026-06-04
Device: iPhone-preview
CoreDevice id: 5320F5AD-2A71-50AC-94FE-207B544B6247
Hardware UDID: 00008030-001A0C980A33C02E
Branch: codex/ios-preview-usability-matrix

## Claim

The iOS prototype now has stronger physical-device evidence for the useful path: a spoken phrase can be recorded/transcribed in the containing app, the latest transcript can be inserted through Foil Keyboard into real host fields, the keyboard resets to a no-transcript state after insertion, and the preview UI is tighter on the preview phone's large-text settings.

## Changes

- `FoilKeyboardBridge.load()` now merges all known App Group/UserDefaults snapshot locations and chooses the newest `updatedAt` snapshot, so stale fallback files do not always win by path order.
- `FoilKeyboardBridge.reset()` removes legacy secondary file locations before saving an idle snapshot.
- `FoilKeyboardSnapshot.initial` is now computed, not a static `let`, so every reset gets a fresh timestamp.
- `KeyboardViewController` uses `UIButton.Configuration` for the Insert latest button.
- `ContentView` uses a compact status stack and two-column icon buttons so the smoke UI is less hostile on very large Dynamic Type.

## Physical Evidence

### Spoken Phrase Smoke

Claim: The containing app can record and transcribe an audible test phrase on the physical iPhone.

Strongest realistic failure mode: The UI shows a transcript from stale shared state or a silent/provider artifact, not from the current device recording.

Evidence:

- App launched with `DEVICECTL_CHILD_FOIL_IOS_GROQ_API_KEY` populated from Keychain; the command output did not print the key.
- WDA showed `Groq transcript ready`, `Transcription complete`, and transcript text containing `Foil preview test June 4th`.
- App Group snapshot copied from `Library/foil-keyboard-snapshot.json` showed `phase = complete`, `message = Groq transcript ready`, and transcript `Whatcha doing here? Foil preview test June 4th.`
- Screenshot: ![Spoken transcript](visual/usability-spoken-transcript.png)

Residual risk / follow-up:

- The transcript included environmental pre-roll (`Whatcha doing here?`) before the target phrase. Dictation quality and endpoint prompt cleanup are still separate product work.

### Insertion Matrix

Claim: The custom keyboard can insert the latest spoken transcript into real host app fields.

Strongest realistic failure mode: The keyboard appears, but host text does not change or the test only proves seeded fake text.

Evidence:

| Target | Field | Result | Evidence |
| --- | --- | --- | --- |
| Notes | Safe test note | Pass | WDA source showed the Notes `TextView` value append `Whatcha doing here? Foil preview test June 4th.` after tapping `foil-keyboard-insert-latest`. Screenshot: ![Notes insertion](visual/usability-notes-spoken-insert.png) |
| Safari | Address/search field | Pass | After clearing the address field, WDA showed the Safari URL text field value set to `Whatcha doing here? Foil preview test June 4th.` The raw Safari tree exposed private browsing context, so no screenshot or dump is preserved. |

Residual risk / follow-up:

- Reminders, Messages, and secure-field rejection rows remain intentionally open. We should only run those when the phone is in a privacy-safe blank target context.

### Keyboard Reset / Reliability Loop

Claim: After insertion, the running keyboard resets to empty state and cannot repeatedly reinsert the same transcript from visible UI.

Strongest realistic failure mode: Reset looks successful in one surface but stale transcript state survives and reappears later.

Evidence:

- Final fresh seed used transcript `Whatcha doing here? Foil preview test June 4th.` with `updatedAt = 802287798.319`.
- After tapping `foil-keyboard-insert-latest` in Notes, WDA source showed:
  - `keyboard_status=Ready`
  - `keyboard_message=Ready`
  - `insert_label=Insert latest (no transcript)`
  - `insert_enabled=false`
  - Notes value appended the seeded transcript once more.
- Screenshot: ![Post-insert reset](visual/usability-final-notes-reset.png)
- The keyboard reset/cycle path also worked after killing a running Foil Keyboard extension process: Notes/Safari could cycle through Apple's Next Keyboard control and return to Foil Keyboard.

Residual risk / follow-up:

- Copying the canonical App Group file back after keyboard reset still showed the previous complete transcript. The live keyboard reset succeeds because the newer UserDefaults snapshot wins, but the extension's file-backed write path is not yet clean. Next fix should make the keyboard reset clear or overwrite the canonical file from inside the extension, then verify file and UI agree.

### Real Interaction Design

Current working model:

- The containing app owns microphone permission, recording, and provider transcription.
- The keyboard owns two host-field actions: `Start` opens the containing app via `foilios://start`, and `Insert latest` inserts the shared transcript with `textDocumentProxy.insertText`.
- The user still has to swipe/cycle back to Foil Keyboard after recording, matching the current Whisperflow-style iOS constraint.
- Shared state is carried through App Group storage and UserDefaults snapshots.

Open design questions:

- Can we make the return-to-keyboard path less reset-prone, or is the Whisperflow-style manual cycle the platform-shaped steady state?
- Should the keyboard clear the transcript immediately after insertion, or keep an explicit one-shot undo/reinsert affordance?
- Should the containing app expose a large single record/stop/transcribe surface instead of smoke-test controls?
- How should we message secure fields and host apps that reject custom keyboards?

### Preview UI Tightening

Claim: The smoke UI is more usable on the preview phone's very large text settings.

Strongest realistic failure mode: Buttons or status text become unreachable or unreadable on the physical device.

Evidence:

- Physical-device screenshot after the compact SwiftUI changes shows the main status stack and transcript fit higher on the screen, with controls reachable by scrolling.
- Screenshot: ![Tightened preview UI](visual/usability-tightened-ui.png)

Residual risk / follow-up:

- This is still a smoke UI, not the product interaction. Large Dynamic Type remains punishing; production iPhone UI should be redesigned around one primary action and a separate transcript/status sheet.

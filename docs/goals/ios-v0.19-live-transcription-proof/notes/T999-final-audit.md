# T999 Final Audit - Live Transcription Proof

## Decision

Complete.

## Outcome

The v0.19 oracle is satisfied. The committed receipts prove that build 10 on
`iPhone-preview` recorded a sterile phrase through the Foil iOS app, produced a
provider-backed transcript through the app path, made that transcript available
to Foil Keyboard, inserted it exactly once from the keyboard into a sterile
Notes editor, and returned the App Group to idle/no transcript afterward.

## Requirement Audit

- Installed build under test identified:
  `status-live.json` identifies `iPhone-preview`, device identifier
  `5320F5AD-2A71-50AC-94FE-207B544B6247`, WDA readiness, and the build context
  used by the physical harness. T001 recorded installed Foil iOS `0.1.0 (10)`.
- Sterile dictated phrase recorded on the physical phone:
  T003 records the macOS text-to-speech phrase used for attempt 2:
  `foil audio smoke test. foil audio smoke test. foil audio smoke test.`
- Transcript produced by the app path, not direct test staging:
  `app-group-before-attempt2.json` proves the App Group started idle/no
  transcript after reset; the WDA app receipts prove record, recording, saved
  recording, transcribe, and ready-for-keyboard app states; only after the app
  Transcribe action does `attempt2-app-group-after-transcribe.json` show
  `phase=complete`, `hasTranscript=true`, `transcriptHash`, and
  `transcriptLength=68`.
- Foil Keyboard saw Insert latest enabled:
  `notes-before-insert.json` passed checks for `foil-keyboard-root`,
  `foil-keyboard-insert-latest`, and `enabled=true`.
- Insert latest inserted into a sterile target exactly once:
  `notes-after-insert.json` passed checks for `foil-keyboard-root`,
  `foil-keyboard-insert-latest enabled=false`, and expected sterile phrase count
  `3`, matching the three repetitions in the single provider transcript.
- App Group returned to idle/no transcript:
  `app-group-after-insert.json` proves post-insert `phase=idle`; the explicit
  final cleanup receipt `app-group-cleanup.json` proves reset/readback
  `phase=idle`.
- Logs and receipts avoided keys/private/raw host-app data:
  receipts contain identifiers, booleans, hashes, lengths, and counts rather
  than raw WDA source, screenshots, credentials, contacts, Messages content, or
  private Notes content.

## Strongest Realistic Failure Mode

The proof could be a false positive if a test-staged or stale App Group
transcript was mistaken for a live provider-produced transcript.

Evidence against that failure:

- The successful attempt begins with a reset/readback receipt showing idle/no
  transcript.
- The worker did not stage a complete transcript for attempt 2; it used Foil app
  controls to start recording, stop recording, and invoke Transcribe.
- The App Group complete snapshot appears only after the app Transcribe state
  receipts.
- The keyboard pre-insert receipt proves Insert latest was enabled from that
  complete snapshot, and the post-insert/cleanup receipts prove the transcript
  was consumed back to idle.

## Residual Risk

Notes already had a sterile editor with Foil Keyboard visible, so this board
does not prove creating a new Notes note. That is outside the v0.19 oracle. The
pre/post receipts still prove the sterile target editor received the live
transcript exactly once and the transcript was consumed.

## Verification

- GoalBuddy state checker passes after marking the board done.
- Receipt assertions check the required phase, transcript, keyboard, insertion,
  and cleanup invariants.
- Targeted scans check for provider keys, known private identifiers, raw WDA
  XML/source, raw host-app values, and Authorization headers.
- `git diff --check` passes.
- Physical automation process cleanup was previously verified after the run;
  the resumed sandbox denied process-list access, so no new process check could
  be performed there.

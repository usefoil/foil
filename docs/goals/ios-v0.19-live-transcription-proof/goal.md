# Foil iOS v0.19 Live Transcription Proof

## Original Request

Continue the iOS app conveyor after the keyboard insertion target-app matrix.

## Outcome

Prove the live end-to-end iPhone path: record audio through Foil iOS, transcribe
with the configured test provider, expose the transcript to Foil Keyboard, and
insert it into a sterile text target on the preview phone.

## Oracle

This board is complete only when receipts prove:

- The installed iOS build under test is identified.
- A sterile dictated phrase is recorded on the physical phone.
- The transcript is produced by the app path, not directly staged by the test.
- Foil Keyboard sees Insert latest enabled.
- Insert latest inserts the transcript exactly once into a sterile target.
- App Group state returns to idle/no transcript afterward.
- Logs and receipts avoid provider keys, private content, and raw host-app data.

## Non-Goals

- Do not broaden to many host apps in this board; one sterile target is enough.
- Do not change provider UX unless a blocker prevents live proof.
- Do not commit audio files unless they are deliberately sterile fixtures and
  approved by the Judge.

## Seed Plan

1. Scout the current command mailbox, provider setup, build number, and harness
   from v0.18.
2. Judge whether the first proof should use Notes, Safari, or another sterile
   target.
3. Run the live proof, fixing only narrowly scoped blockers.
4. Audit the strongest failure mode: a fake App Group stage being mistaken for
   a real transcription.

## Starter Command

`/goal Follow docs/goals/ios-v0.19-live-transcription-proof/goal.md.`

# Foil iOS Notes Keyboard Insertion Smoke

## Original Request

Plan the next step: prove build 8 can insert the latest transcript into a safe blank Notes note using Foil Keyboard on the preview iPhone.

## Outcome

Foil iOS build `0.1.0 (8)` is tested end-to-end on `iPhone-preview` against a sterile Notes note: record or otherwise create a safe transcript, transcribe it, switch to Foil Keyboard, tap Insert latest, and verify the expected text appears in Notes without using private content.

## Oracle

The goal is complete when physical-device evidence shows the installed app is build 8, a safe transcript is available, Foil Keyboard inserts that transcript into a blank Notes note, and the recovery/reset path is either verified or precisely blocked with the next external action.

## Constraints

- Use only sterile Notes content created for this test.
- Do not inspect or quote private notes, Messages, or third-party app content.
- Keep App Store Connect, Groq, and device credentials out of docs and logs.
- Prefer WDA/devicectl/XcodeBuildMCP evidence where available; ask the user only for device unlock, install/auth prompts, credentials, or true external blockers.
- Preserve unrelated repo changes and Xcode user data.

## Starter Command

`/goal Follow docs/goals/ios-v0.9-notes-keyboard-insertion-smoke/goal.md.`

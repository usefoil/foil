# Foil iOS Real Audio Notes Smoke

## Original Request

Prove the real audio path on the preview iPhone: record a short sterile phrase in Foil, transcribe it with Groq, then insert the resulting transcript into Notes through Foil Keyboard.

## Outcome

Foil iOS build `0.1.0 (8)` is tested end-to-end on `iPhone-preview` with real microphone capture and provider transcription: record a sterile phrase, transcribe it, switch to a fresh Notes note, tap Insert latest in Foil Keyboard, and verify the inserted note text matches or clearly corresponds to the spoken phrase.

## Oracle

The goal is complete when physical-device evidence proves the installed app is build 8, Groq/provider configuration is available without exposing secrets, real audio recording produces a transcript, Foil Keyboard inserts that transcript into a sterile Notes note, and consumed/reset state is either verified or precisely blocked.

## Constraints

- Use only the sterile phrase `foil audio smoke test`.
- Do not inspect or quote private Notes, Messages, or third-party app content.
- Do not print, commit, or record Groq keys, App Store Connect keys, JWTs, or private phone content.
- If real audio fails, identify the boundary: microphone permission, recording file, provider key/config, provider request, transcript quality, shared state, keyboard availability, or Notes insertion.
- Prefer WDA/devicectl evidence. Ask the user only for device unlock, install/auth prompts, credentials, or true external blockers.
- Preserve unrelated repo changes and Xcode user data.

## Starter Command

`/goal Follow docs/goals/ios-v0.10-real-audio-notes-smoke/goal.md.`

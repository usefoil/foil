# Diagnostics Audit

## Current Coverage

- App launch and controller setup have `DiagnosticLog` entries in `GroqTalkApp`.
- Setup health logs Accessibility, Microphone, and API-key refresh state transitions.
- Recording lifecycle logs start, stop, no-audio, cancel, and failure paths in `RecordingController` and `AppDelegate`.
- Transcription logs request metadata, provider/model validation, response status, text length, cleanup failure, and mapped API errors.
- Paste routing logs sync/async route, target app name, PID, paste byte counts, and background paste fallback paths.
- Keychain logs timeout and legacy migration failure paths without logging stored key values.

## Gaps Before Batch 1

- `DiagnosticLog` was only an append-only writer and had no read/export API.
- Logs were stored at `/tmp/groqtalk-diag.log`, which is not a durable user diagnostics location.
- Release builds only logged when `GROQTALK_DIAGNOSTICS=1`, which makes user-submitted diagnostics unreliable.
- There was no central redaction helper or test coverage for API keys, bearer tokens, or local home paths.
- Logs are plain strings, not structured events; later Batch 1 work should add stable event categories for setup, recording, transcription, paste, and export failures.
- No user-facing export UI exists yet.

## Privacy Notes

- Existing transcription logs record text length and response metadata, not transcript text.
- Existing paste logs record byte counts and route information, not pasted text.
- Some logs may include local file paths, target app names, provider/model names, PIDs, and error descriptions.
- Diagnostics export must continue to exclude API keys, transcript text, raw audio, clipboard contents, and browser/page content.

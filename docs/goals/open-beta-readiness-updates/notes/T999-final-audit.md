# T999 Final Audit

Result: complete

full_outcome_complete: true

## Oracle Mapping

- Canonical install/update/docs paths: satisfied. README/docs/scripts now use `mean-weasel/foil`; Sparkle appcast, v1.12.0 DMG, mounted app signing, and Homebrew cask metadata were verified against the same release asset and checksum.
- First-run setup supports selected provider path: satisfied. Onboarding/provider UI tests passed for Groq/local/custom setup paths, and the installed v1.12.0 app completed the manual permission/API setup smoke.
- Provider setup/recovery/privacy copy: satisfied. Provider QA passed; Settings/onboarding/docs now describe Groq, local whisper.cpp, and custom OpenAI-compatible provider expectations and recovery.
- Transcription compatibility and provider-specific failures: satisfied by focused implementation plus unit coverage for timeout, cancel, retry, JSON/plain-text compatible responses, and provider-aware errors.
- Retry audio survives temp cleanup expectations: satisfied by app-owned retry-audio storage and focused `TranscriptionHistoryTests` coverage for persistence, delete, clear history, retry resolution, clear retained audio, and retention trimming.
- Beta support docs and QA evidence: satisfied. `docs/release-qa-log.md` records deterministic tests, focused UI smoke, live cleanup-quality, release/Sparkle/Homebrew checks, installed-app signing/launch, and manual Accessibility/Microphone/API smoke.

## Verification Evidence

- `make test-provider-qa` passed.
- Focused open-beta UI smoke passed for setup recovery, onboarding, settings tab routing, cancel transcription, history empty states/search, hotkey accessibility, floating warning details, and Help URL.
- `make test` passed after the implementation slices.
- Focused `TranscriptionHistoryTests` and `KeychainHelperTests` passed.
- `GROQ_API_KEY="$(security find-generic-password -a groq-api-key -w)" make test-cleanup-quality` passed without printing the key.
- v1.12.0 DMG checksum/signature/notarization, mounted app signature, Sparkle appcast, and Homebrew cask metadata/install smoke passed.
- `/Applications/Foil.app` v1.12.0 build 42 cask install, launch, Gatekeeper, and deep codesign checks passed.
- Manual installed-app smoke passed for Accessibility, Microphone, Groq API-key Save/Test, setup path, and audio capture.

## Residual Notes

- The full `make test-ui` suite timed out in this local desktop session, but focused UI smoke plus manual installed-app evidence covers the beta-readiness surfaces required by the oracle.
- Installed-app paste AX-window, VS Code, and Notes coverage remain documented lower-priority local QA skips in `docs/release-qa-log.md`.
- The release has no separate `.sha256` asset, but the GitHub release asset digest, downloaded DMG checksum, and Homebrew cask checksum match.

## Decision

The open-beta readiness oracle is satisfied by the current implementation, documentation, deterministic tests, release artifact checks, and recorded manual macOS permission/API smoke.

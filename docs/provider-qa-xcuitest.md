# Provider QA XCUITests

GroqTalk has two provider QA paths.

## CI-Safe Provider Setup QA

Run:

```bash
make test-provider-qa
```

This covers:

- Groq default provider UI
- Local whisper.cpp preset copy and cleanup-unavailable state
- Local whisper.cpp selection from default Settings state
- Local whisper.cpp setup helper model guidance, generated commands, and copy buttons
- Local whisper.cpp selection persistence across relaunch
- Custom OpenAI-compatible invalid base URL validation
- Custom OpenAI-compatible persistence across relaunch

This target does not require network access, Groq credentials, whisper.cpp, or model files.

The setup helper assertion is
`GroqTalkUITests/GroqTalkUITests/testProviderQALocalWhisperSetupHelperShowsModelCommands`.
It checks the CI-safe Settings surface only; the real local transcription path
remains covered by the opt-in local E2E target below.

## Live Groq Provider QA

Run:

```bash
make test-provider-qa-live
```

This builds for testing, patches the generated `.xctestrun` so the UI test
process receives `RUN_LIVE_GROQ_TESTS=1`, then runs the existing live Groq
app-level transcription XCUITest. It is opt-in and requires either:

- `GROQ_API_KEY` in the environment, or
- an existing Groq API key in the macOS keychain account used by GroqTalk.

If no key is available, the target skips cleanly before launching Xcode. If a
key is present but Groq rejects it, the target fails quickly with the HTTP
status so the local keychain credential can be replaced.

The live target gives Groq up to 90 seconds by default. Override with:

```bash
E2E_TRANSCRIPTION_TIMEOUT_SECONDS=120 make test-provider-qa-live
```

## Local Transcription E2E

For the real local Whisper transcription path, run:

```bash
LOCAL_E2E_LATENCY_RUNS=10 make test-local-transcription-e2e
```

That target requires a local OpenAI-compatible Whisper server.

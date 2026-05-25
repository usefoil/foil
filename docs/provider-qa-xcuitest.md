# Provider QA XCUITests

Foil has two provider QA paths.

## CI-Safe Provider Setup QA

Run:

```bash
make test-provider-qa
```

This covers:

- Groq default provider UI
- Provider-specific privacy and endpoint copy
- Local whisper.cpp preset copy and cleanup-unavailable state
- Local whisper.cpp connection-test recovery copy
- Local whisper.cpp selection from default Settings state
- Local whisper.cpp setup helper model guidance, generated commands, and copy buttons
- Local whisper.cpp selection persistence across relaunch
- Custom OpenAI-compatible invalid base URL validation
- Custom OpenAI-compatible connection-test guidance copy
- Custom OpenAI-compatible persistence across relaunch

This target does not require network access, Groq credentials, whisper.cpp, or model files.
It is the deterministic proof for provider setup copy, privacy copy, and local
setup-helper visibility. If Xcode cannot initialize UI automation on a local
runner, record that as a provider QA blocker and use the manual checks below as
temporary evidence only.

`make test` follows the same deterministic policy for unit XTests: it skips
`FoilTests/LiveGroqIntegrationTests` even if a stale shell still exports
`RUN_LIVE_GROQ_TESTS=1` or `GROQ_API_KEY`.

The setup helper assertion is
`FoilUITests/FoilUITests/testProviderQALocalWhisperSetupHelperShowsModelCommands`.
It checks the CI-safe Settings surface only; the real local transcription path
remains covered by the opt-in local E2E target below.

## Live Groq Provider QA

For unit-level live Groq API coverage, run:

```bash
RUN_LIVE_GROQ_TESTS=1 GROQ_API_KEY=... make test-live-groq
```

This runs only `FoilTests/LiveGroqIntegrationTests`, which verifies the real
Groq Whisper API accepts the encoded WAV, M4A, and FLAC test audio. Keep the key
out of logs and replace `...` with a valid current key in your shell.

For app-level live Groq provider QA, run:

```bash
make test-provider-qa-live
```

This builds for testing, patches the generated `.xctestrun` so the UI test
process receives `RUN_LIVE_GROQ_TESTS=1`, then runs the existing live Groq
app-level transcription XCUITest. It is opt-in and requires either:

- `GROQ_API_KEY` in the environment, or
- an existing Groq API key in the macOS keychain account used by Foil.

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

## Manual Provider QA Fallback

Use this only when `make test-provider-qa` is blocked by the macOS UI automation
runner:

1. Launch a clean local build.
2. Open Settings → Transcription.
3. Confirm Groq shows provider privacy copy and cleanup options.
4. Select Local whisper.cpp and confirm:
   - Audio-stays-local copy is visible.
   - Base URL is `http://127.0.0.1:8080/v1`.
   - Model is `whisper-1`.
   - Test connection help says to start `whisper-server`.
   - Install, build, download, and start commands are copyable.
5. Select Custom OpenAI-compatible and confirm:
   - Endpoint privacy copy is visible.
   - Base URL and model fields are editable.
   - Invalid base URL test reports an actionable validation error.
6. Record screenshots or notes in `docs/release-qa-log.md`.

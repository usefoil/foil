# T001 Coverage Map

## Covered

- `Foil/TranscriptionService.swift` defines `Local whisper.cpp` as an OpenAI-compatible preset with base URL `http://127.0.0.1:8080/v1`, model `whisper-1`, optional API key, no transcript cleanup support.
- `Foil/SettingsView.swift` exposes the provider picker, local preset base URL/model, `settings.localProviderHelp`, `Test connection`, and cleanup-unavailable copy.
- `FoilTests/AppStateTests.swift` covers local preset provider construction, preset switching cleanup behavior, invalid base URL, reachable model, models endpoint missing, missing model, and unreachable server connection states.
- `FoilTests/TranscriptionServiceTests.swift` covers local preset defaults and OpenAI-compatible request construction.
- `FoilUITests/FoilUITests.swift` covers provider QA defaults, seeded local provider UI, invalid custom URL validation, custom provider persistence, and opt-in E2E transcription.
- `Makefile` exposes `make test-provider-qa` and `make test-local-transcription-e2e`.
- `.github/workflows/ci.yml` runs all unit tests and all UI tests, so CI includes the existing seeded provider QA and unit coverage.
- `docs/local-openai-compatible-transcription-e2e.md` documents whisper.cpp setup, endpoint smoke, and `make test-local-transcription-e2e`.

## Partially Covered

- Installed-user local provider selection: `testProviderQALocalWhisperPresetShowsExpectedSettings` launches with `--seed-local-provider`; it does not start from default Groq and select `Local whisper.cpp` in Settings.
- In-app setup help: Settings has one sentence explaining a local OpenAI-compatible whisper.cpp server and optional API key, but it does not tell an installed user how to install/start the compatible server or where to look next.
- Live local transcription: `make test-local-transcription-e2e` is a deterministic opt-in harness when a local server already exists, but it is not part of regular CI and does not exercise the user selecting the Local preset in Settings.

## Missing

- A CI-safe UI test for the literal journey: launch default state, open Settings, choose `Local whisper.cpp` from the provider picker, assert base URL/model/help/test-connection/cleanup states.
- UI-level assertion that the local setup guidance is visible after selection, not only when seeded.
- Local preset persistence across relaunch after selection from the UI.
- Optional: stronger discoverability from the app to setup docs or command-shaped instructions, without embedding/vendorizing whisper.cpp.

## Current Verification Commands

- `make test` covers unit-level provider and connection behavior.
- `make test-provider-qa` covers current provider QA UI tests, including seeded local provider UI.
- `make test-ui` runs all UI tests in CI.
- `make test-local-transcription-e2e` covers live local endpoint plus app-level transcription when a compatible server is already running.

## Recommended First Worker Package

Add the CI-safe installed-user Settings journey slice:

- Improve `SettingsView` local-provider guidance enough for an installed app user to know the required local server shape and the docs/setup path.
- Add a UI test that launches from default Groq, opens Settings, selects `Local whisper.cpp`, and asserts:
  - picker value or visible text is `Local whisper.cpp`;
  - base URL `http://127.0.0.1:8080/v1` is visible;
  - model `whisper-1` is visible;
  - setup/help copy is visible;
  - `Test connection` button is visible;
  - cleanup-unavailable copy is visible.
- Include the new test in `make test-provider-qa`.

Measurable success:

- The new focused UI test passes by itself.
- `make test-provider-qa` includes and passes the new test.
- The test does not require network, Groq credentials, whisper.cpp, or model files.

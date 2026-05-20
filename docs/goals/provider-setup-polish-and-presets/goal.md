# Provider Setup Polish And Presets

## Objective

Improve GroqTalk's OpenAI-compatible transcription provider setup so custom/local providers are understandable, testable, and easy to select through built-in provider presets, while preserving Groq as the unchanged default.

## Ready-To-Paste Goal

```text
/goal Implement provider setup polish and provider presets for GroqTalk.

Context:
- Project: GroqTalk is a native Swift macOS menu bar dictation app.
- Current provider state: Groq remains the default transcription provider and an OpenAI-compatible custom transcription provider exists with base URL, model, and optional API key.
- Existing local E2E path: `make test-local-transcription-e2e` runs the real `GroqTalkUITests/GroqTalkUITests/testE2ETranscription` against a local OpenAI-compatible Whisper server using `GroqTalk/e2e-test-audio.wav`.
- Important surfaces: `AppState`, `TranscriptionService`, `TranscriptionController`, `KeychainHelper`, `SettingsView`, `MenuBarView`, `ApiKeySetupView`, `GroqTalkUITests`, docs under `docs/local-openai-compatible-transcription-e2e.md`.
- User-visible failure modes: invalid custom base URL, unreachable local server, unsupported `/models`, selected model missing, optional local API key confusion, cleanup unavailable for transcription-only providers.

Scope:
- Include:
  - Add provider-aware setup polish for OpenAI-compatible custom providers.
  - Add a user-facing “Test connection” flow for custom/local transcription providers.
  - Surface clear validation status for invalid URL, unreachable server, reachable server with unsupported `/models`, selected model found, and selected model missing.
  - Add built-in provider presets for Groq, Local whisper.cpp, and Custom OpenAI-compatible.
  - Keep Groq as the default preset/provider with unchanged launch behavior.
  - Persist selected preset and custom preset fields locally.
  - Preserve provider-scoped API key storage and legacy Groq key readability.
  - Update tests and docs for provider setup and preset behavior.
- Exclude:
  - Do not embed whisper.cpp.
  - Do not vendor whisper.cpp source or model files.
  - Do not implement local model download UI.
  - Do not make cleanup/chat local.
  - Do not add provider marketplace, sync, auto-discovery, or multi-profile account management.
  - Do not redesign the full settings UI beyond the provider setup controls needed for this work.

Constraints:
- Preserve:
  - Existing users launch into Groq + `whisper-large-v3-turbo`.
  - Existing Groq API keys stored under the legacy/current Groq keychain account still work.
  - Regular CI remains free of network, Groq credentials, whisper.cpp, and model downloads.
  - `make test-ui` does not run live/local transcription by default.
- Do not:
  - Silently call Groq from a supposed local/custom transcription test.
  - Show cleanup controls as available for providers that do not support transcript processing.
  - Store API keys in UserDefaults.
  - Commit local generated `.xctestrun` files, models, or whisper.cpp checkouts.
- Pause and ask if:
  - A product decision would change privacy claims, setup semantics, or whether cleanup should be available through non-Groq chat providers.
  - Supporting a provider requires a non-OpenAI-compatible API shape.

Acceptance criteria:
- Product polish:
  - Settings/setup UI includes a provider-aware “Test connection” action for OpenAI-compatible providers.
  - Invalid base URL shows a specific invalid URL status before any network request.
  - Unreachable local/custom server shows a specific unreachable server status.
  - HTTP 200 `/models` with the selected model shows a success status naming the selected model.
  - HTTP 200 `/models` without the selected model shows a model-unavailable status naming the missing model.
  - HTTP 404 or 405 from `/models` shows a reachable-but-model-not-checked status.
  - Custom/local provider copy clearly states API key is optional when configured without a real key.
  - Cleanup controls remain hidden or disabled with provider-aware explanatory copy for transcription-only providers.
- Provider presets:
  - Default selected preset is Groq for fresh installs and existing users.
  - Groq preset builds:
    - `https://api.groq.com/openai/v1/audio/transcriptions`
    - `https://api.groq.com/openai/v1/chat/completions`
    - `https://api.groq.com/openai/v1/models`
  - Local whisper.cpp preset builds transcription requests to `http://127.0.0.1:8080/v1/audio/transcriptions` with model `whisper-1`.
  - Custom OpenAI-compatible preset persists editable base URL and model fields.
  - Groq and custom/local API keys remain provider-scoped and independent.
  - Switching presets updates visible provider name, selected transcription model, and cleanup availability.
  - Existing custom provider settings, if present, migrate or remain available as the Custom OpenAI-compatible preset without data loss.
- Tests and docs:
  - Unit tests cover validation result mapping, preset defaults, preset endpoint construction, custom persistence, and provider-scoped key behavior.
  - UI/state tests cover selected provider/preset display and cleanup availability copy.
  - `docs/local-openai-compatible-transcription-e2e.md` explains the Local whisper.cpp preset and keeps the opt-in XCUITest harness instructions.
  - `make test-local-transcription-e2e` still passes when the local tiny Whisper server is running.

Verification:
- Run:
  - `make test`
  - `make test-ui`
  - `make build-warnings-as-errors`
  - `make test-local-transcription-e2e` when a local OpenAI-compatible tiny Whisper server is running.
- Inspect:
  - Provider default and migration behavior.
  - Keychain account naming and provider-scoped key reads/writes.
  - Settings/setup copy for hardcoded or misleading Groq/local references.
  - Preset switching behavior for provider name, model, base URL, optional API key, and cleanup availability.
- Evidence to report:
  - Changed files.
  - Test command results.
  - Screens or textual evidence of each connection-test status.
  - Local endpoint transcript, word recall, and latency if local E2E is run.

Deliverables:
- Code changes implementing provider setup polish and provider presets.
- Unit/UI test updates.
- Updated local OpenAI-compatible transcription E2E docs.
- No committed model files, no vendored whisper.cpp checkout, no generated `.xctestrun` files.

Stop rule:
- Stop when deterministic tests pass, Groq default behavior is proven unchanged, provider setup statuses are covered by tests, preset switching is covered by tests, and the local XCUITest harness still passes when the tiny local Whisper server is available.
- Pause instead of guessing if cleanup semantics, privacy copy, or non-OpenAI-compatible provider support requires a product decision.
```

## Implementation Plan

### 1. Product Polish For Custom Providers

Goal: make OpenAI-compatible provider setup understandable and verifiable for a normal user without changing the provider architecture.

Implementation steps:

1. Audit hardcoded and provider-related copy in `SettingsView`, `MenuBarView`, `ApiKeySetupView`, setup check status copy, and tests.
2. Add provider validation state to `AppState`, such as `idle`, `running`, `succeeded`, `warning`, and `failed`, plus a detail string.
3. Reuse `TranscriptionService.validateProviderConfiguration(apiKey:requiredModels:)` for connection checks.
4. Add a “Test connection” action beside custom/local provider fields.
5. Map validation results to clear user-facing copy:
   - invalid URL
   - unreachable server
   - server reachable and selected model available
   - server reachable but selected model missing
   - server reachable but model availability not checked
6. Keep cleanup UI unavailable for transcription-only providers with explicit provider-aware copy.
7. Add focused unit and UI/state tests for the statuses and Groq unchanged behavior.

### 2. Provider Presets

Goal: make provider switching ergonomic without requiring users to remember endpoint/model details.

Implementation steps:

1. Define a lightweight `TranscriptionProviderPreset` model with `id`, `displayName`, `providerID`, `baseURL`, `model`, `requiresAPIKey`, `supportsTranscriptProcessing`, and `isEditable`.
2. Add built-in presets:
   - Groq: fixed Groq endpoints, `whisper-large-v3-turbo`, API key required.
   - Local whisper.cpp: `http://127.0.0.1:8080/v1`, `whisper-1`, API key optional/default local dummy key.
   - Custom OpenAI-compatible: editable base URL, model, and optional API key.
3. Persist selected preset ID and custom preset fields in `UserDefaults`.
4. Derive `AppState.selectedTranscriptionProvider` from the selected preset.
5. Update settings UI with a provider preset picker and editable fields only where appropriate.
6. Preserve legacy migration for existing Groq and custom provider state.
7. Add tests for defaults, endpoint construction, persistence, key isolation, and UI/state display.
8. Update docs to mention the Local whisper.cpp preset while preserving the opt-in local XCUITest path.

## Starter Command

```text
/goal Follow docs/goals/provider-setup-polish-and-presets/goal.md.
```

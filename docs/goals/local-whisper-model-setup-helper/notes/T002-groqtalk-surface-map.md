# T002 GroqTalk Surface Map

## Current Local Provider Behavior

- `TranscriptionProviderPreset.localWhisperCPP` is fixed and non-editable:
  - base URL: `http://127.0.0.1:8080/v1`
  - app/API model field: `whisper-1`
  - API key not required
  - transcript processing unsupported
- `AppState.selectedTranscriptionProvider` maps the Local whisper.cpp preset to an OpenAI-compatible provider with those fixed values.
- Custom OpenAI-compatible remains the editable path for arbitrary base URL/model fields.

## Current Settings Surface

- `SettingsView.transcriptionSettings` already branches by provider preset.
- The Local whisper.cpp branch currently shows:
  - base URL as `LabeledContent`
  - model as `LabeledContent`
  - one caption explaining install/download/start server
  - the existing OpenAI-compatible `Test connection` button in the Credentials section
- Best helper fit: replace or expand the Local whisper.cpp branch in the Model section with a compact setup helper subview.

## Existing Verification Surface

- Unit tests:
  - local preset defaults in `TranscriptionServiceTests`
  - local provider construction/persistence and connection states in `AppStateTests`
- UI tests:
  - seeded Local whisper.cpp settings
  - default Settings -> select Local whisper.cpp
  - local preset persistence across relaunch
- `make test-provider-qa` already runs the relevant CI-safe provider UI tests.
- `make test-local-transcription-e2e` remains opt-in and requires a live local server.

## Implementation Fit

Best first implementation shape:

1. Add a small command-generation model, likely in a new file such as `GroqTalk/LocalWhisperSetup.swift`.
2. Keep it independent of runtime transcription selection; it generates commands and explanatory metadata only.
3. Add a persisted setup-helper preference to `AppState`, such as selected local setup model ID, only for command generation.
4. Add a `LocalWhisperSetupView` or private `SettingsView` subview for:
   - model option picker
   - speed/quality/disk guidance
   - install/download/start command text
   - copy buttons
   - clear explanation that `whisper-1` is the API compatibility field and `--model` selects the real local model file
5. Extend provider QA UI tests to assert helper visibility and one generated command.

## Risks

- Settings could become crowded if all 31 verified variants are shown directly.
- SwiftUI static text may expose important copy as accessibility `value` rather than `label`; tests should use existing label-or-value helpers where needed.
- Copy-button verification may need a test-safe clipboard strategy or only assert command visibility in CI.
- Persisting setup preferences must not change actual transcription behavior unless a later tranche intentionally makes Local whisper editable.

## Suggested Verification Commands

- `xcodebuild test -scheme GroqTalk -configuration Debug -destination 'platform=macOS' -only-testing:GroqTalkTests/<new LocalWhisperSetup tests>`
- `xcodebuild test -scheme GroqTalk -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:GroqTalkUITests/GroqTalkUITests/<new helper UI test>`
- `make test-provider-qa`


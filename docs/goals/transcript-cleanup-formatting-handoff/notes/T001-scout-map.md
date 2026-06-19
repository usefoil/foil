# T001 Scout Map - Transcript Cleanup Formatting

## Implementation Seam Map

- `Foil/TranscriptProcessingMode.swift` owns the current raw/cleanup/rewrite enum and hard-coded `promptInstruction` strings. This is the right seam for default cleanup-formatting prompt metadata or for delegating prompt defaults to a new helper. Current display copy is broad (`Clean up`, `Rewrite clearly`) and does not yet match the v1 user-facing cleanup-formatting emphasis.
- `Foil/TranscriptionController.swift` already keeps cleanup after speech-to-text through `processTranscriptOrRaw(rawText:apiKey:service:context:)`. It decides whether cleanup runs, resolves the cleanup provider/key, sets `.cleaningTranscript`, calls `TranscriptionService.processTranscript`, and falls back to raw text with `cleanupFailed=true` on error. This should remain the orchestration seam; avoid moving prompt assembly into the controller.
- `Foil/TranscriptionService.swift` owns HTTP construction, response decoding, provider validation, and `buildTranscriptProcessingBody`. Today `buildTranscriptProcessingBody(transcript:mode:model:)` sends exactly two messages: system `mode.promptInstruction` and user raw transcript. This is the highest-leverage seam for a small cleanup request/prompt builder that can assemble resolved prompt, preferred terms, raw transcript, model, and provider.
- `Foil/AppState.swift` already persists cleanup mode/provider/model/base URL values and exposes `selectedTranscriptCleanupProvider`, `supportsSelectedTranscriptProcessing`, and `effectiveTranscriptProcessingMode`. It does not yet persist per-mode custom prompts or preferred terms. Add those here with reset helpers and UserDefaults migration/default coverage.
- `Foil/SettingsView.swift` already has a `Section("Cleanup")` in Transcription settings with an `After transcription` picker and provider controls shown when mode is not raw. It needs to become the v1 deliberate opt-in surface: toggle or off/cleanup-formatting choice, hide cleanup controls when off, expose provider/model/base URL/API key/test connection, prompt editor, reset button, and preferred terms editor.
- `Foil/DiagnosticLog.swift` exports provider/model/processing metadata and redacts API key, bearer token, known key prefixes, and user paths. It currently logs cleanup model and route metadata but has no prompt/preferred-term fields because those data do not exist yet. Tests must prove new prompt and preferred-term values never appear in log/export/setup report output.
- `Foil/FoilApp.swift` delegate stores and pastes only the `text` returned by `TranscriptionController.didTranscribe`, and shows cleanup fallback feedback when `cleanupFailed` is true. This supports final-text-only history if the controller returns cleaned text on success and raw text on cleanup failure.
- `Foil/TranscriptionHistory.swift` stores a single `Outcome.success(text:)` and has no raw/cleaned dual storage. Add targeted tests around the app/controller boundary rather than changing the history model unless implementation introduces extra fields.

## Test Coverage Map

- `FoilTests/TranscriptionControllerTests.swift` already covers raw mode returning raw text, unsupported/none cleanup producing no cleanup request, Groq cleanup execution, custom chat endpoint/model/key routing, cleanup failure falling back to raw with `cleanupFailed=true`, and invalid custom chat URL skipping requests. Extend this suite for cleanup-off no-request if the UI/data model changes, independent cleanup provider with non-Groq STT, and cleanup fallback warnings if needed.
- `FoilTests/TranscriptionServiceTests.swift` already covers cleanup provider endpoint construction, no-provider endpoints, request processing, API error mapping, and cleanup provider validation. Extend it for prompt body assembly: default cleanup-formatting prompt, custom prompt override, preferred terms context, hard return-only instruction, model selection, and no blind replacement.
- `FoilTests/AppStateTests.swift` already covers cleanup persistence defaults, provider switching cleanup availability, invalid custom cleanup URL disabling cleanup, and cleanup model persistence. Extend it for custom prompt per mode persistence/reset, preferred terms persistence/normalization, default mode behavior, and cleanup provider selection remaining independent from STT provider.
- `FoilTests/DiagnosticLogTests.swift` already covers redaction of API keys/bearer tokens, cleanup provider setup report metadata, and cleanup base URL secret redaction. Extend it with prompt/preferred-term sentinel strings and transcript/cleaned text sentinel strings to prove diagnostics omit sensitive cleanup content.
- `FoilTests/TranscriptionHistoryTests.swift` already proves success records store one text value. Add a small final-text-only proof if implementation changes history-facing flow, especially cleanup failure storing raw as final text and cleanup success storing cleaned as final text.
- `FoilUITests/FoilUITests.swift` currently asserts only broad cleanup/settings presence in provider QA rows. Extend or add a focused settings row that starts with cleanup off, verifies provider/prompt/preferred-term controls hidden, enables cleanup formatting, then verifies cleanup provider picker, prompt editor, reset, preferred terms editor, and routing/help copy.

## Recommended Implementation Sequence

1. Core data model and prompt assembly: add a cleanup prompt/request helper, default cleanup-formatting prompt, per-mode custom prompt storage/reset, preferred terms storage/normalization, and service request-body tests.
2. Cleanup execution and routing: pass the assembled cleanup request/context from `AppState`/controller to `TranscriptionService`, keep cleanup provider independent of STT provider, prove cleanup-off no-request and raw fallback on cleanup failure.
3. Settings UI: replace the broad mode picker surface with the v1 opt-in cleanup-formatting controls, provider controls, prompt editor/reset, preferred terms editor, and explicit routing copy.
4. Privacy, diagnostics, and history proof: add redaction/omission tests for transcript, cleaned text, custom prompt, preferred terms, API keys, and bearer tokens; prove history receives only final pasted text.
5. Final audit: run focused unit tests and the targeted UI row, then map receipts back to the approved spec and goal oracle.

## Verification Commands Without Live Provider Credentials

- `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionServiceTests`
- `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionControllerTests`
- `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/AppStateTests`
- `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/DiagnosticLogTests`
- `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionHistoryTests`
- `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:FoilUITests/FoilUITests`

## Uncertainties For Judge/Worker

- The board's T002 references `superpowers:writing-plans`; no installed Codex skill with that exact name is visible in the current session. Check the repo for plan format examples and use existing `docs/superpowers/plans/*.md` if the skill is unavailable.
- The spec allows storing "cleanup enabled or selected processing mode"; current state uses `transcriptProcessingMode`. A boolean toggle mapped to `.raw`/`.cleanUp` is likely compatible, while preserving `.rewriteClearly` in the model for compatibility.
- The current `availableCleanupProviderIDs` intentionally prevents Groq cleanup when STT provider is not Groq. The spec allows local/custom STT with cloud cleanup when explicitly selected, so Judge should decide whether v1 UI should allow Groq cleanup outside Groq STT or continue custom-only for non-Groq cloud routing.

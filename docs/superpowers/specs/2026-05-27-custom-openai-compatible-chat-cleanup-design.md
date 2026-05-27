# Custom OpenAI-Compatible Chat Cleanup Design

## Goal

Add an explicit OpenAI-compatible chat cleanup path so Foil users can pair
Groq, local whisper.cpp, or custom OpenAI-compatible transcription with a
separately configured chat endpoint for transcript cleanup and rewrite.

This closes issue #86 without adding new transcription adapters or first-class
local model presets.

## Non-Goals

- Do not add Ollama, LM Studio, llama.cpp, vLLM, OpenAI, or LocalAI as named
  provider presets in this slice.
- Do not add OpenAI transcription models such as `gpt-4o-transcribe`.
- Do not auto-detect local model servers.
- Do not silently route local/custom transcripts to Groq cleanup.
- Do not require live network or local model server access in regular CI.

## Current State

Foil already separates transcription provider selection from transcript
processing mode in the UI and app state:

- Transcription providers are Groq, Local whisper.cpp, and Custom
  OpenAI-compatible.
- `TranscriptProcessingMode` controls raw, cleanup, and rewrite behavior.
- `TranscriptionController.processTranscriptOrRaw` uses the same
  `TranscriptionService` provider for cleanup as for transcription.
- Groq supports cleanup because its provider exposes `/v1/chat/completions`.
- Local/custom OpenAI-compatible transcription providers currently report no
  transcript-processing support, so cleanup/rewrite fall back to raw text.
- `KeychainHelper` already scopes transcription credentials by provider ID, with
  legacy Groq key migration preserved.

## Product Behavior

Add a new cleanup routing concept independent of transcription routing:

- `None`: paste the raw transcript.
- `Groq`: use the existing Groq chat-completions cleanup path. This remains the
  default only for Groq transcription when cleanup/rewrite is enabled.
- `Custom OpenAI-compatible chat`: use user-configured `baseURL`, `model`, and
  optional API key for cleanup/rewrite.

Defaults:

- Groq transcription keeps current behavior.
- Local whisper.cpp defaults cleanup routing to `None`.
- Custom OpenAI-compatible transcription defaults cleanup routing to `None`.
- Users must explicitly choose custom chat cleanup for local/custom transcript
  cleanup.

If cleanup fails after transcription succeeds, Foil keeps today's graceful
fallback: paste the raw transcript, mark cleanup as failed, and avoid turning a
cleanup problem into a transcription failure.

## Settings UI

In Transcription settings, keep the current provider section first. In the
cleanup section:

- Continue showing the "After transcription" picker for Raw, Clean up, and
  Rewrite clearly.
- When Raw is selected, hide endpoint configuration.
- When Clean up or Rewrite clearly is selected:
  - If transcription provider is Groq, show a cleanup provider picker with
    `Groq` and `Custom OpenAI-compatible chat`.
  - If transcription provider is Local whisper.cpp or Custom
    OpenAI-compatible, show `None` and `Custom OpenAI-compatible chat`, with
    `None` explaining that Foil will paste raw text until a chat endpoint is
    configured.
  - For custom chat cleanup, show:
    - Base URL text field, default `http://127.0.0.1:11434/v1`
    - Model text field, default `llama3.1:8b`
    - Optional API key save/delete/test control
    - Test connection button

Copy must make routing explicit. Suggested text:

> Cleanup uses the selected chat endpoint. Foil will not send local/custom
> transcripts to Groq unless you choose Groq here.

## Data Model

Add a cleanup provider model separate from `TranscriptionProvider`:

```swift
enum TranscriptCleanupProviderID: String, CaseIterable, Identifiable {
    case none
    case groq
    case customOpenAICompatibleChat
}

struct TranscriptCleanupProvider: Equatable {
    let id: TranscriptCleanupProviderID
    let displayName: String
    let baseURL: URL?
    let model: String
    let requiresAPIKey: Bool
}
```

Persist in `AppState`:

- `transcriptCleanupProviderID`
- `customTranscriptCleanupBaseURL`
- `customTranscriptCleanupModel`

Credential storage:

- Add Keychain account scoping for cleanup credentials that does not collide
  with transcription credentials or the legacy Groq account.
- Example internal scope: `groq-api-key.cleanup.custom-openai-compatible-chat`.
- The existing Groq API key remains unchanged.

## Service Flow

Keep `TranscriptionService.transcribe` unchanged.

For cleanup:

1. `TranscriptionController` transcribes through the selected transcription
   provider.
2. If effective processing mode is raw, return raw text.
3. Resolve a cleanup provider from `AppState`.
4. If no cleanup provider is configured, return raw text and log that cleanup
   was skipped due to routing, not failure.
5. Build a `TranscriptionService` or a small `TranscriptCleanupService` pointed
   at the cleanup provider's chat-completions endpoint.
6. Send the same chat-completions body currently used by
   `processTranscript`.
7. On success, paste processed text.
8. On failure, paste raw text and set `cleanupFailed = true`.

The implementation can either generalize `TranscriptionProvider` enough to
represent a chat-only provider or introduce `TranscriptCleanupService`. Prefer
the smaller implementation that keeps transcription-specific fields from
leaking into cleanup-only configuration.

## Connection Testing

Custom chat cleanup test behavior:

- Validate the base URL is HTTP or HTTPS and has a host.
- Prefer `GET /models` when available.
- If `/models` returns 404 or 405, perform a tiny `POST /chat/completions`
  smoke using the configured model and a harmless prompt.
- Treat authentication failures as actionable key/config errors.
- Do not log API keys, response bodies containing transcript text, or prompt
  content.

## Testing

Regular CI uses mocked transports only.

Unit coverage:

- Existing Groq cleanup tests still pass.
- Local/custom transcription with cleanup mode enabled does not call Groq by
  default.
- Custom chat cleanup sends requests to the custom chat base URL, not the
  transcription base URL.
- Custom chat cleanup uses the configured cleanup model.
- Custom chat cleanup uses its scoped API key.
- Custom chat cleanup failure falls back to the raw transcript and marks
  `cleanupFailed`.
- Raw mode never calls a cleanup endpoint.
- Invalid custom cleanup URL produces a user-facing configuration failure in
  connection testing.

UI coverage:

- Transcription settings show custom chat cleanup fields only when cleanup or
  rewrite is enabled.
- Local/custom transcription copy explains raw fallback until chat cleanup is
  configured.
- Provider routing copy is visible and does not overclaim offline behavior.

Optional live smoke:

- A maintainer may provide an OpenAI-compatible chat API key for manual or
  opt-in test verification.
- The live smoke must be explicitly invoked and must not run in regular CI.
- Record only endpoint type, model name, pass/fail, and redacted diagnostics.

## Documentation

Update README provider notes:

- Local transcription remains local only when cleanup is raw/off.
- Custom chat cleanup may send transcripts to the configured endpoint.
- Foil never sends local/custom transcripts to Groq unless the user explicitly
  selects Groq cleanup.

Update troubleshooting:

- Add "Custom cleanup endpoint not reachable."
- Add "Cleanup failed but raw transcript pasted."

## Acceptance Criteria

- Users can configure Custom OpenAI-compatible chat cleanup with base URL,
  model, and optional API key.
- Clean up and Rewrite clearly work through the configured chat endpoint.
- Existing Groq cleanup behavior is preserved.
- Local/custom transcription does not call Groq cleanup unless the user
  explicitly selects Groq cleanup.
- Cleanup credentials are stored separately from transcription credentials.
- Regular CI remains deterministic and network-free.
- Documentation clearly explains transcript routing and privacy implications.

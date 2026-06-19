# Transcript Cleanup Formatting Design

## Status

Approved for planning on 2026-06-19.

## Objective

Make Foil's optional LLM transcript cleanup feel intentional, provider-neutral,
and safe by default. The first polished mode is cleanup formatting: improve the
readability of completed speech-to-text transcripts while preserving the
speaker's meaning, facts, voice, and routing choices.

The feature builds on the existing post-transcription cleanup path rather than
introducing a separate transcription architecture. It should also create the
right structure for future writing-transformation and domain-correction modes.

## Existing Context

- `TranscriptProcessingMode` currently supports `raw`, `cleanUp`, and
  `rewriteClearly`.
- `TranscriptionController` already runs speech-to-text first, then optionally
  calls `processTranscriptOrRaw`.
- `TranscriptionService` already sends cleanup requests to OpenAI-compatible
  chat-completions endpoints.
- Settings already separate transcription provider selection from cleanup
  provider selection.
- History currently stores the successful text that Foil pasted or made
  available to paste.
- Diagnostic logging should avoid transcript text, prompt text, glossary terms,
  and secrets.

## Product Shape

Foil should present this as **Transcript cleanup**, an optional post-transcription
step.

The pipeline remains:

1. Record audio.
2. Send audio to the selected speech-to-text provider.
3. Receive the raw transcript.
4. If cleanup is off, paste the raw transcript.
5. If cleanup is on, send the raw transcript to the selected cleanup LLM
   provider.
6. Paste the cleaned transcript, or paste the raw transcript with a warning if
   cleanup fails.
7. Store only the final pasted text in history.

The default mode is **Clean up formatting**. It should:

- Add punctuation and capitalization.
- Add paragraph breaks where they improve readability.
- Turn clearly enumerated spoken points into numbered or bulleted lists.
- Remove obvious filler and false starts only when doing so does not change
  meaning.
- Preserve names, numbers, technical terms, code-like strings, URLs, and intent.
- Return only the final processed transcript.

Foil should be explicit about routing:

- The transcription provider controls where audio goes.
- The cleanup provider controls where transcript text goes.
- Cleanup is off unless the user turns it on.
- Using local speech-to-text does not imply local cleanup unless the selected
  cleanup provider is also local.

## Settings And Data Model

Use the existing cleanup system as the base and make the prompt structure more
explicit.

For the first implementation pass, the user-facing cleanup choice can be:

- Off.
- Clean up transcript formatting.

`rewriteClearly` can remain in the model for compatibility and future work, but
the first user-facing pass should emphasize cleanup formatting over broader
rewriting.

Foil should store:

- Cleanup enabled or selected processing mode.
- Cleanup provider.
- Cleanup model.
- Cleanup API key and base URL when the provider needs them.
- A custom prompt per processing mode.
- A preferred terms list.

Each mode has a default prompt. The user can edit the prompt for the active
mode and reset it to Foil's default. Future modes can reuse the same structure
by supplying a different default prompt.

Preferred terms are stored separately from the prompt. In v1, this is a simple
list of terms the user wants the LLM to preserve or prefer, such as `Supabase`,
`Vercel`, `Postgres`, client names, product names, and internal project names.
Foil should send the preferred terms as structured prompt context. It should not
perform blind text replacement before or after the LLM call.

The effective system instruction is assembled from:

1. The active mode prompt, using the user's custom prompt when present.
2. Preferred terms context, when the list is non-empty.
3. A hard instruction to return only the processed transcript.

## Architecture

Keep cleanup in the current post-STT path, but avoid growing prompt assembly
inside `TranscriptionController`.

Add a small cleanup request or prompt-building helper that owns:

- Active processing mode.
- Resolved custom or default prompt.
- Preferred terms.
- Raw transcript.
- Cleanup provider and model.

`TranscriptionController` should continue to decide whether cleanup runs and
should continue to fall back to raw text if cleanup fails. `TranscriptionService`
should continue to own HTTP request construction, response decoding, and API
error mapping.

The cleanup provider remains independently configurable from the speech-to-text
provider. This preserves combinations such as:

- Groq transcription with Groq cleanup.
- OpenAI Whisper transcription with custom OpenAI-compatible cleanup.
- Local whisper.cpp transcription with local OpenAI-compatible cleanup.
- Local whisper.cpp transcription with cloud cleanup, when the user explicitly
  chooses that routing.

## UI

In Settings > Transcription, keep the existing provider and model controls, then
make Cleanup a deliberate optional section.

Suggested UI:

- Toggle: `Clean up transcript formatting`.
- When off, hide provider, prompt, and preferred-term controls.
- When on, show:
  - Cleanup provider picker.
  - Provider-specific model, base URL, API key, and test-connection controls.
  - Prompt editor prefilled from the default cleanup-formatting prompt.
  - Reset prompt button.
  - Preferred terms editor.

The preferred terms editor can be a multiline text area with one term per line.
This is enough for the first version and avoids the complexity of a glossary
table until correction pairs become necessary.

Cleanup failure should remain non-blocking. Foil should paste raw text and show
a visible warning such as:

`Cleanup failed; pasted raw transcript.`

## Error Handling And Privacy

Cleanup must not turn a successful dictation into a failed dictation. If
speech-to-text succeeds and cleanup fails, Foil pastes the raw transcript,
stores that raw transcript as the final pasted history text, and marks the run
as a cleanup fallback.

Diagnostics should log routing and operational metadata only:

- Transcription provider and model.
- Cleanup provider and model.
- Processing mode.
- Input and output lengths.
- Whether cleanup fallback happened.
- API status or mapped error category.

Diagnostics must not include:

- Raw transcript text.
- Cleaned transcript text.
- Custom prompt text.
- Preferred terms.
- API keys or bearer tokens.

Privacy copy should clearly explain that transcript text is sent to the cleanup
provider only when cleanup is enabled.

## Testing And Evidence

Implementation should include focused tests for the trust boundaries:

- Cleanup off sends no LLM cleanup request.
- Cleanup provider is independent from the transcription provider.
- Prompt body assembly includes the resolved prompt and preferred terms.
- Prompt reset restores the default cleanup-formatting prompt.
- Cleanup failure falls back to raw transcript and reports `cleanupFailed`.
- History receives only the final pasted text.
- Diagnostics do not include transcript text, custom prompt text, preferred
  terms, or API keys.
- Settings UI shows cleanup provider, prompt editor, reset, and preferred terms
  only when cleanup is enabled.

For acceptance evidence, the strongest realistic failure mode is that cleanup
secretly changes routing or leaks sensitive transcript-related content. The
implementation proof should include unit tests around request construction,
fallback behavior, and diagnostic redaction, plus direct UI inspection or UI
tests for the settings controls.

## Out Of Scope For V1

- Multiple named prompt profiles.
- Correction-pair glossary entries such as `super base -> Supabase`.
- Automatic text replacement before or after the LLM call.
- Storing raw and cleaned transcripts side by side in history.
- Making writing-transformation modes prominent in the UI.
- Streaming cleanup or partial cleanup previews.

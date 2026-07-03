# Live Audio Cleanup Quality

This opt-in QA path checks the consolidated `Cleanup profile` against generated Apple voice audio.

The harness creates WAV fixtures with macOS `say` and `afconvert`, runs dry-run semantic assertions without credentials, and can run live transcription plus cleanup when a provider key is available.

## Local Structural Check

```sh
swift tests/test_live_audio_cleanup_quality.swift --dry-run
```

This generates audio locally, validates the WAV headers, writes redacted artifacts, and checks the semantic rubric against built-in expected cleaned text. It does not call any provider.

## Generate Fixtures Only

```sh
swift tests/test_live_audio_cleanup_quality.swift --generate-fixtures-only
```

Fixtures are written below `tests/fixtures/audio-cleanup-quality/generated/` unless `E2E_ARTIFACT_DIR` is set.

## Live Check

```sh
GROQ_API_KEY=... OPENAI_API_KEY=... make test-live-audio-cleanup-quality
```

By default the runner uses Groq for transcription. For cleanup, it uses OpenAI
when `OPENAI_API_KEY` is present and falls back to Groq otherwise. The current
passing quality baseline uses OpenAI cleanup.

Useful overrides:

```sh
E2E_ARTIFACT_DIR=/tmp/foil-audio-cleanup \
E2E_TRANSCRIPTION_PROVIDER=groq \
E2E_TRANSCRIPTION_MODEL=whisper-large-v3-turbo \
E2E_CLEANUP_PROVIDER=openai \
E2E_CLEANUP_MODEL=gpt-5.4-mini \
GROQ_API_KEY=... \
OPENAI_API_KEY=... \
make test-live-audio-cleanup-quality
```

The runner records provider IDs, models, source text, audio paths, raw transcripts, cleaned transcripts, assertion results, and pass/fail status. It must not print or persist API key values.

## Rubric

Each fixture declares required terms, forbidden cleanup artifacts, and whether obvious spoken structure should become a structured output. Assertions are semantic rather than exact-string equality:

- Required facts and names must remain.
- Filler, stutters, repeated words, and explicit abandoned false starts should be removed when the fixture marks them as forbidden.
- Clearly enumerated spoken tasks should produce multiple structured lines.
- Technical vocabulary and preferred product terms should remain.
- Cleaned output must not be empty, dramatically inflated, or over-compressed.

# Local OpenAI-Compatible Transcription E2E

This opt-in check verifies Foil against a local OpenAI-compatible Whisper endpoint.
It does not require a Groq key and should not run in regular CI.

For provider setup UI automation that does not require a local server, see
`docs/provider-qa-xcuitest.md`.

In the app, select the `Local whisper.cpp` provider preset to use these defaults:

- Base URL: `http://127.0.0.1:8080/v1`
- Model: `whisper-1`
- API key: optional; use a dummy value such as `local` only if your local server expects one

The `Model` field is the OpenAI-compatible request field sent to the local
server. For `whisper.cpp`, the real model file is chosen when starting
`whisper-server` with `--model /path/to/ggml-*.bin`. The Local provider Settings
screen includes a setup helper that shows verified starter model options and
copyable install, build, download, and start commands.

Use **Test connection** in Settings after starting `whisper-server`. If the
server is not reachable, Foil reports that Local whisper.cpp could not be
reached and points back to the start-server command. A reachable server with a
`/v1/models` response confirms the `whisper-1` compatibility model is listed;
servers that do not expose model validation can still be marked reachable with a
warning.

The `Custom OpenAI-compatible` preset remains available for other local or hosted
servers that expose the same `/v1/audio/transcriptions` shape.

## Verified Starter Models

These are the source-verified model options currently exposed by the in-app
Local whisper.cpp setup helper:

| Model | File | Scope | Use when |
| --- | --- | --- | --- |
| `tiny.en` | `ggml-tiny.en.bin` | English-only | You want the fastest smoke test or lowest resource use. |
| `base.en` | `ggml-base.en.bin` | English-only | You want the recommended starter model for local setup. |
| `small.en` | `ggml-small.en.bin` | English-only | You want better quality while keeping setup practical. |
| `medium.en` | `ggml-medium.en.bin` | English-only | You can spend more disk and CPU/GPU for stronger accuracy. |
| `large-v3-turbo` | `ggml-large-v3-turbo.bin` | Multilingual | You want a modern larger model with lower latency than full large-v3. |
| `large-v3` | `ggml-large-v3.bin` | Multilingual | You want the highest-quality starter option and can tolerate heavier setup. |

Model availability was verified against the upstream `whisper.cpp`
`models/download-ggml-model.sh` script and the corresponding hosted
`ggml-*.bin` files.

## Server Setup

Keep `whisper.cpp` and models outside this repo. The in-app helper defaults to
`~/Developer/whisper.cpp`; this standalone example uses the same location:

```sh
mkdir -p ~/Developer
git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git ~/Developer/whisper.cpp
cd ~/Developer/whisper.cpp
cmake -B build -DWHISPER_BUILD_TESTS=OFF
cmake --build build -j --config Release
sh ./models/download-ggml-model.sh base.en
```

Start the local server:

```sh
~/Developer/whisper.cpp/build/bin/whisper-server \
  --host 127.0.0.1 \
  --port 8080 \
  --model ~/Developer/whisper.cpp/models/ggml-base.en.bin \
  --inference-path /v1/audio/transcriptions \
  --convert \
  --no-timestamps
```

## Endpoint Smoke Test

```sh
curl -sS http://127.0.0.1:8080/v1/audio/transcriptions \
  -H "Authorization: Bearer local" \
  -F "file=@Foil/e2e-test-audio.wav;type=audio/wav" \
  -F "model=whisper-1" \
  -F "response_format=text"
```

Expected transcript:

```text
the quick brown fox jumps over the lazy dog.
```

## XCUITest App-Level E2E

```sh
make test-local-transcription-e2e
```

The Make target:

- posts `Foil/e2e-test-audio.wav` to `/v1/audio/transcriptions`
- requires HTTP `200`
- builds for testing
- patches the generated `.xctestrun` so `FoilUITests/FoilUITests/testE2ETranscription`
  receives the local endpoint environment
- runs the real XCUITest with `xcodebuild test-without-building`
- fails if the test is skipped, `/tmp/foil-e2e-result.txt` is empty, or fewer than
  8 of 9 expected words are present

Useful overrides:

```sh
E2E_TRANSCRIPTION_BASE_URL=http://127.0.0.1:8080/v1 \
E2E_TRANSCRIPTION_MODEL=whisper-1 \
E2E_API_KEY=local \
LOCAL_E2E_LATENCY_RUNS=10 \
make test-local-transcription-e2e
```

Regular `make test-ui` intentionally remains deterministic and skips this live local
transcription path unless it is invoked through the dedicated opt-in target.

## 2026-05-14 Local Evidence

Machine: Apple Silicon Mac with Metal backend selected by `whisper.cpp`.

Clip:

- File: `Foil/e2e-test-audio.wav`
- SHA-256: `36d3a24bbaf79f805fa4ad5360feb918c7467956b5001166d741f48e4c037e04`
- Format: 16 kHz mono PCM WAV

Endpoint result:

- HTTP: `200`
- Transcript: `the quick brown fox jumps over the lazy dog.`
- Word recall: `9/9`
- 10-run median latency: `0.054s`
- 10-run p95 latency: `0.056s`

App-level E2E result:

- Command: `testE2ETranscription` with the environment above
- Result: `TEST SUCCEEDED`
- `/tmp/foil-e2e-result.txt`: `The quick brown fox jumps over the lazy dog.`

## 2026-05-15 XCUITest Harness Evidence

Command:

```sh
LOCAL_E2E_LATENCY_RUNS=10 make test-local-transcription-e2e
```

Endpoint result:

- HTTP: `200` for all 10 runs
- Transcript: `the quick brown fox jumps over the lazy dog.`
- Word recall: `9/9`
- 10-run median latency: `0.045898s`
- 10-run p95 latency: `0.060236s`

XCUITest result:

- Test: `FoilUITests/FoilUITests/testE2ETranscription`
- Runner: patched `.xctestrun` via `xcodebuild test-without-building`
- Result: `TEST EXECUTE SUCCEEDED`
- `/tmp/foil-e2e-result.txt`: `the quick brown fox jumps over the lazy dog.`
- App word recall: `9/9`

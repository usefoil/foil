# T001 Model Availability Scout

## Source Evidence

- Official download script: `https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/models/download-ggml-model.sh`
- Official model README: `https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/models/README.md`
- Official project README: `https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/README.md`
- Official server README: `https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/examples/server/README.md`

The current `download-ggml-model.sh` declares these model identifiers:

| Model identifier | Expected file | Language scope | Notes | Availability probe |
| --- | --- | --- | --- | --- |
| `tiny` | `ggml-tiny.bin` | multilingual | fastest, smallest standard model | HTTP 200 |
| `tiny.en` | `ggml-tiny.en.bin` | English-only | fastest English option | HTTP 200 |
| `tiny-q5_1` | `ggml-tiny-q5_1.bin` | multilingual | quantized | HTTP 200 |
| `tiny.en-q5_1` | `ggml-tiny.en-q5_1.bin` | English-only | quantized | HTTP 200 |
| `tiny-q8_0` | `ggml-tiny-q8_0.bin` | multilingual | quantized | HTTP 200 |
| `base` | `ggml-base.bin` | multilingual | small default candidate | HTTP 200 |
| `base.en` | `ggml-base.en.bin` | English-only | safe beginner default candidate | HTTP 200 |
| `base-q5_1` | `ggml-base-q5_1.bin` | multilingual | quantized | HTTP 200 |
| `base.en-q5_1` | `ggml-base.en-q5_1.bin` | English-only | quantized | HTTP 200 |
| `base-q8_0` | `ggml-base-q8_0.bin` | multilingual | quantized | HTTP 200 |
| `small` | `ggml-small.bin` | multilingual | better accuracy, slower | HTTP 200 |
| `small.en` | `ggml-small.en.bin` | English-only | better English accuracy, slower | HTTP 200 |
| `small.en-tdrz` | `ggml-small.en-tdrz.bin` | English-only | tinydiarize special source | HTTP 200 |
| `small-q5_1` | `ggml-small-q5_1.bin` | multilingual | quantized | HTTP 200 |
| `small.en-q5_1` | `ggml-small.en-q5_1.bin` | English-only | quantized | HTTP 200 |
| `small-q8_0` | `ggml-small-q8_0.bin` | multilingual | quantized | HTTP 200 |
| `medium` | `ggml-medium.bin` | multilingual | high accuracy, large | HTTP 200 |
| `medium.en` | `ggml-medium.en.bin` | English-only | high English accuracy, large | HTTP 200 |
| `medium-q5_0` | `ggml-medium-q5_0.bin` | multilingual | quantized | HTTP 200 |
| `medium.en-q5_0` | `ggml-medium.en-q5_0.bin` | English-only | quantized | HTTP 200 |
| `medium-q8_0` | `ggml-medium-q8_0.bin` | multilingual | quantized | HTTP 200 |
| `large-v1` | `ggml-large-v1.bin` | multilingual | older large model | HTTP 200 |
| `large-v2` | `ggml-large-v2.bin` | multilingual | older large model | HTTP 200 |
| `large-v2-q5_0` | `ggml-large-v2-q5_0.bin` | multilingual | quantized | HTTP 200 |
| `large-v2-q8_0` | `ggml-large-v2-q8_0.bin` | multilingual | quantized | HTTP 200 |
| `large-v3` | `ggml-large-v3.bin` | multilingual | highest standard quality, largest | HTTP 200 |
| `large-v3-q5_0` | `ggml-large-v3-q5_0.bin` | multilingual | quantized | HTTP 200 |
| `large-v3-turbo` | `ggml-large-v3-turbo.bin` | multilingual | faster large-v3-family option | HTTP 200 |
| `large-v3-turbo-q5_0` | `ggml-large-v3-turbo-q5_0.bin` | multilingual | quantized | HTTP 200 |
| `large-v3-turbo-q8_0` | `ggml-large-v3-turbo-q8_0.bin` | multilingual | quantized | HTTP 200 |

Probe command shape:

```sh
curl -L -s -o /dev/null -w '%{http_code}' --head \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-<model>.bin
```

For `small.en-tdrz`, the official script switches to:

```text
https://huggingface.co/akashmjn/tinydiarize-whisper.cpp/resolve/main/ggml-small.en-tdrz.bin
```

## Command Semantics

- `download-ggml-model.sh <model> [models_path]` downloads `ggml-<model>.bin` into the models path.
- `.en` means English-only.
- Quantized suffixes include `q5_0`, `q5_1`, and `q8_0`.
- `small.en-tdrz` is a tinydiarize model, and the server has a separate `--tinydiarize` flag for that mode.
- Official server help exposes:
  - `-m FNAME, --model FNAME`
  - `--host HOST`
  - `--port PORT`
  - `--inference-path PATH`
  - `--convert`
  - `--no-timestamps`
  - `-l LANG, --language LANG`

GroqTalk's OpenAI-compatible local command should keep using:

```sh
./build/bin/whisper-server \
  --host 127.0.0.1 \
  --port 8080 \
  --model ./models/ggml-<model>.bin \
  --language en \
  --inference-path /v1/audio/transcriptions \
  --convert \
  --no-timestamps
```

The app-side multipart `model=whisper-1` field is an API compatibility value. The actual local model is the file passed to `whisper-server --model`.

## Recommended Helper Model List

For the first UI helper, prefer a curated beginner-facing list rather than every supported quantized variant:

- `tiny.en`: fastest English-only smoke-test option.
- `base.en`: recommended beginner default for English.
- `small.en`: better English accuracy with still-manageable size.
- `medium.en`: higher English accuracy, larger/slower.
- `large-v3-turbo`: strong multilingual/default advanced option with smaller disk than full large-v3.
- `large-v3`: highest standard large-v3 quality, largest/slower.

Optional advanced expansion later:

- Multilingual variants: `tiny`, `base`, `small`, `medium`.
- Quantized variants: all listed `q5_0`, `q5_1`, and `q8_0`.
- Tinydiarize: `small.en-tdrz`, only if the helper also exposes `--tinydiarize` and explains speaker-turn behavior.

## Rejected Or Deferred

- Distilled models: official README says initial support exists via conversion, but they are not listed by `download-ggml-model.sh`; do not expose in the first app helper.
- Fine-tuned Hugging Face models: supported via conversion paths, but not suitable for the first helper because availability and filenames are user-specific.
- Every quantized variant in the primary Settings picker: available, but likely too noisy for the first installed-user flow. Keep advanced docs or a later advanced mode.

## Drift Risks

- The official script is on `master`; model identifiers can change.
- Hugging Face URLs returning 200 prove current availability, not future availability.
- Server flags are example-program flags, not a stable formal API; docs and tests should avoid overpromising.

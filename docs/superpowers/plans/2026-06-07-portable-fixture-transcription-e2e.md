# Portable Fixture Transcription E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a portable Mac app-level end-to-end transcription test that uses the existing pre-recorded audio fixture and requires no microphone, cloud API key, or local Whisper install.

**Architecture:** Keep the existing `--e2e-transcribe` app hook and `FoilUITests/FoilUITests/testE2ETranscription` flow. Add a small dependency-free local OpenAI-compatible fixture server that accepts the app's real multipart transcription request, verifies it contains a WAV file and expected fields, returns the known transcript, and writes a receipt. Add a Make target that starts the fixture server, patches the XCUITest environment, runs only the E2E UI test, and validates both the transcript result and the server receipt.

**Tech Stack:** Swift/XCUITest, Bash, Node.js built-in `http`, existing `Foil/e2e-test-audio.wav`, existing `xcodebuild build-for-testing` / `.xctestrun` patch pattern.

---

## Existing Context

The repo already has the app-side E2E plumbing:

- `Foil/e2e-test-audio.wav`: tracked WAV fixture, expected phrase `the quick brown fox jumps over the lazy dog`.
- `Foil/E2EAudioStub.swift`: `AudioRecording` implementation that returns a fixture audio URL instead of using the microphone.
- `Foil/UITestingController.swift:344`: `configureE2ETranscribeIfNeeded()` replaces the app recording controller with `E2EAudioStub`, then triggers start/stop.
- `FoilUITests/FoilUITests.swift:827`: `testE2ETranscription()` launches the app with `--e2e-transcribe`, waits for paste completion, and checks the transcript result file.
- `scripts/run-local-transcription-e2e-xcuitest.sh`: existing real local Whisper/OpenAI-compatible E2E harness. Keep this as the real provider proof.

This plan adds a second harness for day-to-day portability. It does not claim to prove Whisper model quality. It proves the Mac app pipeline and OpenAI-compatible request contract with real fixture audio bytes.

## File Structure

- Create `scripts/fixture-transcription-server.mjs`
  - Responsibility: local fake OpenAI-compatible server with `/v1/models` and `/v1/audio/transcriptions`.
  - Writes a JSON receipt proving the request included auth, model, response format, multipart file metadata, and WAV markers.
- Create `scripts/run-fixture-transcription-e2e-xcuitest.sh`
  - Responsibility: start the fixture server, build for testing, patch `FoilUITests` environment, run `testE2ETranscription`, validate transcript recall, validate fixture-server receipt, and stop the server.
- Modify `Makefile`
  - Add `test-fixture-transcription-e2e` to `.PHONY`.
  - Add a target that invokes the new script.
- Modify `docs/local-openai-compatible-transcription-e2e.md`
  - Add a short section explaining the portable fixture E2E versus the real local Whisper E2E.

---

## Task 1: Fixture Transcription Server

**Files:**
- Create: `scripts/fixture-transcription-server.mjs`

**Acceptance criteria:** A local process exposes OpenAI-compatible `/v1/models` and `/v1/audio/transcriptions`, returns the known transcript, and writes a receipt with enough information to prove the app sent a real WAV multipart request.

- [ ] **Step 1: Create the server file**

Create `scripts/fixture-transcription-server.mjs`:

```javascript
#!/usr/bin/env node

import http from 'node:http'
import { writeFileSync } from 'node:fs'

const host = process.env.FIXTURE_TRANSCRIPTION_HOST || '127.0.0.1'
const port = Number(process.env.FIXTURE_TRANSCRIPTION_PORT || '0')
const readyPath = process.env.FIXTURE_TRANSCRIPTION_READY_PATH || ''
const receiptPath = process.env.FIXTURE_TRANSCRIPTION_RECEIPT_PATH || ''
const expectedModel = process.env.FIXTURE_TRANSCRIPTION_MODEL || 'whisper-1'
const transcript = process.env.FIXTURE_TRANSCRIPTION_TEXT || 'the quick brown fox jumps over the lazy dog.'
const maxBodyBytes = Number(process.env.FIXTURE_TRANSCRIPTION_MAX_BODY_BYTES || `${10 * 1024 * 1024}`)

function sendJSON(response, status, value) {
  const body = JSON.stringify(value)
  response.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(body)
  })
  response.end(body)
}

function sendText(response, status, value) {
  response.writeHead(status, {
    'content-type': 'text/plain; charset=utf-8',
    'content-length': Buffer.byteLength(value)
  })
  response.end(value)
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = []
    let size = 0
    request.on('data', chunk => {
      size += chunk.length
      if (size > maxBodyBytes) {
        reject(new Error(`request body exceeded ${maxBodyBytes} bytes`))
        request.destroy()
        return
      }
      chunks.push(chunk)
    })
    request.on('end', () => resolve(Buffer.concat(chunks)))
    request.on('error', reject)
  })
}

function textContains(buffer, needle) {
  return buffer.indexOf(Buffer.from(needle)) !== -1
}

function valueForMultipartField(bodyText, fieldName) {
  const marker = `name="${fieldName}"`
  const markerIndex = bodyText.indexOf(marker)
  if (markerIndex === -1) return ''
  const valueStart = bodyText.indexOf('\r\n\r\n', markerIndex)
  if (valueStart === -1) return ''
  const nextBoundary = bodyText.indexOf('\r\n--', valueStart + 4)
  return bodyText
    .slice(valueStart + 4, nextBoundary === -1 ? undefined : nextBoundary)
    .trim()
}

function buildReceipt(request, body) {
  const bodyText = body.toString('latin1')
  return {
    method: request.method,
    url: request.url,
    authorization: request.headers.authorization || '',
    contentType: request.headers['content-type'] || '',
    contentLength: body.length,
    hasMultipartFormData: String(request.headers['content-type'] || '').includes('multipart/form-data'),
    hasFileField: textContains(body, 'name="file"'),
    hasFilename: /filename="[^"]+"/.test(bodyText),
    hasAudioContentType: /Content-Type:\s*audio\/(wav|x-wav|mpeg|mp4|flac|ogg|webm)/i.test(bodyText),
    hasRIFF: textContains(body, 'RIFF'),
    hasWAVE: textContains(body, 'WAVE'),
    model: valueForMultipartField(bodyText, 'model'),
    responseFormat: valueForMultipartField(bodyText, 'response_format'),
    language: valueForMultipartField(bodyText, 'language')
  }
}

function receiptIsValid(receipt) {
  return receipt.method === 'POST'
    && receipt.url === '/v1/audio/transcriptions'
    && receipt.authorization.startsWith('Bearer ')
    && receipt.hasMultipartFormData
    && receipt.hasFileField
    && receipt.hasFilename
    && receipt.hasAudioContentType
    && receipt.hasRIFF
    && receipt.hasWAVE
    && receipt.model === expectedModel
}

const server = http.createServer(async (request, response) => {
  if (request.method === 'GET' && request.url === '/v1/models') {
    sendJSON(response, 200, {
      object: 'list',
      data: [{ id: expectedModel, object: 'model', owned_by: 'foil-fixture' }]
    })
    return
  }

  if (request.method !== 'POST' || request.url !== '/v1/audio/transcriptions') {
    sendJSON(response, 404, { error: { message: 'not found' } })
    return
  }

  try {
    const body = await readBody(request)
    const receipt = buildReceipt(request, body)
    receipt.valid = receiptIsValid(receipt)

    if (receiptPath) {
      writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`)
    }

    if (!receipt.valid) {
      sendJSON(response, 400, {
        error: {
          message: 'fixture transcription request did not match expected multipart WAV contract',
          receipt
        }
      })
      return
    }

    if (receipt.responseFormat === 'json') {
      sendJSON(response, 200, { text: transcript })
    } else {
      sendText(response, 200, transcript)
    }
  } catch (error) {
    sendJSON(response, 500, { error: { message: String(error.message || error) } })
  }
})

server.listen(port, host, () => {
  const address = server.address()
  const baseURL = `http://${host}:${address.port}/v1`
  if (readyPath) {
    writeFileSync(readyPath, `${baseURL}\n`)
  }
  console.error(`fixture transcription server listening at ${baseURL}`)
})

process.on('SIGTERM', () => {
  server.close(() => process.exit(0))
})
```

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x scripts/fixture-transcription-server.mjs
```

Expected: no output.

- [ ] **Step 3: Start the fixture server manually**

Run:

```bash
tmpdir="$(mktemp -d)"
FIXTURE_TRANSCRIPTION_READY_PATH="$tmpdir/ready" \
FIXTURE_TRANSCRIPTION_RECEIPT_PATH="$tmpdir/receipt.json" \
node scripts/fixture-transcription-server.mjs >"$tmpdir/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 1 50); do [[ -s "$tmpdir/ready" ]] && break; sleep 0.1; done
cat "$tmpdir/ready"
kill "$server_pid"
rm -rf "$tmpdir"
```

Expected: prints a base URL like `http://127.0.0.1:xxxxx/v1`.

- [ ] **Step 4: Commit**

Run:

```bash
git add scripts/fixture-transcription-server.mjs
git commit -m "test: add fixture transcription server"
```

Expected: commit succeeds.

---

## Task 2: Portable XCUITest Runner

**Files:**
- Create: `scripts/run-fixture-transcription-e2e-xcuitest.sh`

**Acceptance criteria:** One command starts the fixture server, runs the existing app-level E2E XCUITest with the server as an OpenAI-compatible provider, verifies the transcript, verifies the server receipt, and cleans up all temporary processes/files.

- [ ] **Step 1: Create the runner script**

Create `scripts/run-fixture-transcription-e2e-xcuitest.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCHEME="${SCHEME:-Foil}"
CONFIG="${CONFIG:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
MODEL="${E2E_TRANSCRIPTION_MODEL:-whisper-1}"
API_KEY="${E2E_API_KEY:-local-fixture}"
AUDIO_PATH="${E2E_WAV_PATH:-Foil/e2e-test-audio.wav}"
RESULT_PATH="${E2E_RESULT_PATH:-/tmp/foil-fixture-e2e-result.txt}"
EXPECTED="${E2E_EXPECTED_TRANSCRIPT:-the quick brown fox jumps over the lazy dog}"
TIMEOUT_SECONDS="${E2E_TRANSCRIPTION_TIMEOUT_SECONDS:-30}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-}"
PLISTBUDDY="/usr/libexec/PlistBuddy"

if [[ ! -f "${AUDIO_PATH}" ]]; then
  echo "error: audio fixture not found: ${AUDIO_PATH}" >&2
  exit 2
fi

if ! command -v node >/dev/null 2>&1; then
  echo "error: node is required for the fixture transcription server" >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
server_pid=""
patched=""

cleanup() {
  if [[ -n "${server_pid}" ]] && kill -0 "${server_pid}" >/dev/null 2>&1; then
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" >/dev/null 2>&1 || true
  fi
  rm -rf "${tmpdir}"
  if [[ -n "${patched}" ]]; then
    rm -f "${patched}"
  fi
}
trap cleanup EXIT

transcript_words() {
  tr '[:upper:]' '[:lower:]' | tr -cs '[:alpha:]' '\n' | sed '/^$/d'
}

word_recall() {
  local transcript="$1"
  local expected_words transcript_words_file
  expected_words="${tmpdir}/expected-words"
  transcript_words_file="${tmpdir}/transcript-words"
  printf '%s' "${EXPECTED}" | transcript_words >"${expected_words}"
  printf '%s' "${transcript}" | transcript_words >"${transcript_words_file}"
  awk '
    FNR == NR { transcript[$1]++; next }
    { total++; if (transcript[$1] > 0) { transcript[$1]--; recall++ } }
    END { printf "%d/%d", recall, total }
  ' "${transcript_words_file}" "${expected_words}"
}

assert_min_recall() {
  local transcript="$1"
  local recall total
  IFS=/ read -r recall total <<<"$(word_recall "${transcript}")"
  if [[ "${recall}" -lt 8 ]]; then
    echo "error: transcript matched ${recall}/${total} expected words" >&2
    echo "transcript: ${transcript}" >&2
    echo "expected: ${EXPECTED}" >&2
    exit 1
  fi
}

assert_receipt_bool() {
  local key="$1"
  node -e '
    const fs = require("fs")
    const receipt = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
    const key = process.argv[2]
    if (receipt[key] !== true) {
      console.error(`error: receipt ${key} was ${receipt[key]}`)
      process.exit(1)
    }
  ' "${receipt_path}" "${key}"
}

ready_path="${tmpdir}/ready"
receipt_path="${tmpdir}/receipt.json"
server_log="${tmpdir}/server.log"

echo "== Fixture transcription server"
FIXTURE_TRANSCRIPTION_READY_PATH="${ready_path}" \
FIXTURE_TRANSCRIPTION_RECEIPT_PATH="${receipt_path}" \
FIXTURE_TRANSCRIPTION_MODEL="${MODEL}" \
node scripts/fixture-transcription-server.mjs >"${server_log}" 2>&1 &
server_pid=$!

for _ in $(seq 1 100); do
  if [[ -s "${ready_path}" ]]; then
    break
  fi
  if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
    echo "error: fixture server exited before becoming ready" >&2
    cat "${server_log}" >&2 || true
    exit 1
  fi
  sleep 0.1
done

if [[ ! -s "${ready_path}" ]]; then
  echo "error: fixture server did not become ready" >&2
  cat "${server_log}" >&2 || true
  exit 1
fi

BASE_URL="$(tr -d '\r\n' <"${ready_path}")"
echo "server=${BASE_URL}"

echo "== Build for testing"
build_args=(
  -scheme "${SCHEME}"
  -configuration "${CONFIG}"
  -destination "${DESTINATION}"
)
if [[ -n "${DERIVED_DATA_PATH}" ]]; then
  build_args+=( -derivedDataPath "${DERIVED_DATA_PATH}" )
fi
xcodebuild build-for-testing "${build_args[@]}"

find_root="${DERIVED_DATA_PATH:-${HOME}/Library/Developer/Xcode/DerivedData}"
xctestrun="$(find "${find_root}" -name '*.xctestrun' -path '*Foil*' -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 || true)"
if [[ -z "${xctestrun}" || ! -f "${xctestrun}" ]]; then
  echo "error: could not locate generated .xctestrun" >&2
  exit 1
fi

patched="${xctestrun%.xctestrun}.fixture-openai.xctestrun"
cp "${xctestrun}" "${patched}"

ui_target_index=""
for index in $(seq 0 20); do
  blueprint="$("${PLISTBUDDY}" -c "Print :TestConfigurations:0:TestTargets:${index}:BlueprintName" "${patched}" 2>/dev/null || true)"
  if [[ "${blueprint}" == "FoilUITests" ]]; then
    ui_target_index="${index}"
    break
  fi
  if [[ -z "${blueprint}" ]]; then
    break
  fi
done

if [[ -z "${ui_target_index}" ]]; then
  echo "error: FoilUITests target not found in ${patched}" >&2
  exit 1
fi

env_root=":TestConfigurations:0:TestTargets:${ui_target_index}:EnvironmentVariables"
for key in \
  E2E_TRANSCRIPTION_PROVIDER \
  E2E_TRANSCRIPTION_BASE_URL \
  E2E_TRANSCRIPTION_MODEL \
  E2E_API_KEY \
  E2E_WAV_PATH \
  E2E_RESULT_PATH \
  E2E_TRANSCRIPTION_TIMEOUT_SECONDS; do
  "${PLISTBUDDY}" -c "Delete ${env_root}:${key}" "${patched}" >/dev/null 2>&1 || true
done
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_PROVIDER string openai-compatible" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_BASE_URL string ${BASE_URL}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_MODEL string ${MODEL}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_API_KEY string ${API_KEY}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_RESULT_PATH string ${RESULT_PATH}" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_TIMEOUT_SECONDS string ${TIMEOUT_SECONDS}" "${patched}"
if [[ -n "${E2E_WAV_PATH:-}" ]]; then
  "${PLISTBUDDY}" -c "Add ${env_root}:E2E_WAV_PATH string ${E2E_WAV_PATH}" "${patched}"
fi

echo "== XCUITest fixture transcription"
rm -f "${RESULT_PATH}" "${receipt_path}"
test_log="${tmpdir}/xcuitest.log"
set +e
xcodebuild test-without-building \
  -xctestrun "${patched}" \
  -destination "${DESTINATION}" \
  -only-testing:FoilUITests/FoilUITests/testE2ETranscription \
  2>&1 | tee "${test_log}"
test_status="${PIPESTATUS[0]}"
set -e

if grep -qi 'Test skipped' "${test_log}"; then
  echo "error: XCUITest skipped; fixture E2E environment was not applied" >&2
  exit 1
fi

if [[ "${test_status}" -ne 0 ]]; then
  echo "error: XCUITest failed" >&2
  exit "${test_status}"
fi

if ! grep -Eq '\*\* TEST (EXECUTE )?SUCCEEDED \*\*' "${test_log}"; then
  echo "error: XCUITest did not report success" >&2
  exit 1
fi

if [[ ! -s "${RESULT_PATH}" ]]; then
  echo "error: result file missing or empty: ${RESULT_PATH}" >&2
  exit 1
fi

if [[ ! -s "${receipt_path}" ]]; then
  echo "error: fixture server receipt missing or empty: ${receipt_path}" >&2
  cat "${server_log}" >&2 || true
  exit 1
fi

app_transcript="$(tr -d '\r' <"${RESULT_PATH}" | sed 's/^ *//; s/ *$//')"
assert_min_recall "${app_transcript}"
assert_receipt_bool valid
assert_receipt_bool hasFileField
assert_receipt_bool hasRIFF
assert_receipt_bool hasWAVE

receipt_model="$(node -e 'const fs=require("fs"); const r=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); process.stdout.write(r.model || "")' "${receipt_path}")"
if [[ "${receipt_model}" != "${MODEL}" ]]; then
  echo "error: fixture receipt model ${receipt_model} did not match ${MODEL}" >&2
  exit 1
fi

printf 'app_result=%s\n' "${app_transcript}"
printf 'app_recall=%s\n' "$(word_recall "${app_transcript}")"
printf 'fixture_receipt=%s\n' "${receipt_path}"
```

- [ ] **Step 2: Make the runner executable**

Run:

```bash
chmod +x scripts/run-fixture-transcription-e2e-xcuitest.sh
```

Expected: no output.

- [ ] **Step 3: Run the runner**

Run:

```bash
scripts/run-fixture-transcription-e2e-xcuitest.sh
```

Expected:

```text
== Fixture transcription server
server=http://127.0.0.1:<port>/v1
== Build for testing
...
== XCUITest fixture transcription
...
** TEST EXECUTE SUCCEEDED **
app_result=the quick brown fox jumps over the lazy dog.
app_recall=9/9
fixture_receipt=/tmp/<...>/receipt.json
```

- [ ] **Step 4: Commit**

Run:

```bash
git add scripts/run-fixture-transcription-e2e-xcuitest.sh
git commit -m "test: add portable fixture transcription e2e runner"
```

Expected: commit succeeds.

---

## Task 3: Make Target

**Files:**
- Modify: `Makefile`

**Acceptance criteria:** `make test-fixture-transcription-e2e` runs the portable app-level E2E and is discoverable beside the existing live/local transcription targets.

- [ ] **Step 1: Add the phony target name**

In `Makefile`, add `test-fixture-transcription-e2e` to the existing `.PHONY` line near the other transcription targets.

Use this patch shape:

```diff
-.PHONY: ... test-live-transcription-e2e-cli test-local-transcription-e2e test-microphone-live ...
+.PHONY: ... test-live-transcription-e2e-cli test-local-transcription-e2e test-fixture-transcription-e2e test-microphone-live ...
```

- [ ] **Step 2: Add the Make target**

In `Makefile`, immediately after the existing `test-local-transcription-e2e` target, add:

```make
test-fixture-transcription-e2e:
	SCHEME="$(SCHEME)" CONFIG="$(CONFIG)" scripts/run-fixture-transcription-e2e-xcuitest.sh
```

- [ ] **Step 3: Run the Make target**

Run:

```bash
make test-fixture-transcription-e2e
```

Expected:

```text
== Fixture transcription server
server=http://127.0.0.1:<port>/v1
...
** TEST EXECUTE SUCCEEDED **
app_result=the quick brown fox jumps over the lazy dog.
app_recall=9/9
```

- [ ] **Step 4: Commit**

Run:

```bash
git add Makefile
git commit -m "test: expose portable fixture transcription e2e"
```

Expected: commit succeeds.

---

## Task 4: Documentation

**Files:**
- Modify: `docs/local-openai-compatible-transcription-e2e.md`

**Acceptance criteria:** The docs explain which E2E command to use for portable app regression testing and which command to use for real local Whisper/provider proof.

- [ ] **Step 1: Add a portable fixture section**

In `docs/local-openai-compatible-transcription-e2e.md`, add this section before `## Server Setup`:

````markdown
## Portable Fixture App E2E

Use this when you want a deterministic Mac app-level transcription regression
test on a fresh development machine without a microphone, cloud API key, or
local Whisper model:

```sh
make test-fixture-transcription-e2e
```

This command starts a local OpenAI-compatible fixture server, launches Foil via
XCUITest with `--e2e-transcribe`, feeds `Foil/e2e-test-audio.wav` through the
same recording-controller path used by the app E2E hook, and verifies both:

- the transcript result contains at least 8 of the 9 expected words
- the fixture server received a multipart request containing a WAV file, model,
  authorization header, and response format

This is not a Whisper accuracy test. It proves the app pipeline and request
contract are intact. Use `make test-local-transcription-e2e` when you also need
proof against a real local OpenAI-compatible Whisper server.
````

- [ ] **Step 2: Run markdown diff inspection**

Run:

```bash
git diff -- docs/local-openai-compatible-transcription-e2e.md
```

Expected: the new section references `make test-fixture-transcription-e2e` and clearly distinguishes fixture E2E from real local Whisper E2E.

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/local-openai-compatible-transcription-e2e.md
git commit -m "docs: document portable fixture transcription e2e"
```

Expected: commit succeeds.

---

## Task 5: Final Verification And Evidence Receipt

**Files:**
- Inspect: `scripts/fixture-transcription-server.mjs`
- Inspect: `scripts/run-fixture-transcription-e2e-xcuitest.sh`
- Inspect: `Makefile`
- Inspect: `docs/local-openai-compatible-transcription-e2e.md`

**Acceptance criteria:** The new portable command passes, the existing real local E2E command remains documented as the provider-quality proof, and evidence explicitly tries to disprove the strongest realistic failure modes.

- [ ] **Step 1: Run shell syntax checks**

Run:

```bash
bash -n scripts/run-fixture-transcription-e2e-xcuitest.sh
node --check scripts/fixture-transcription-server.mjs
```

Expected: no output and exit status `0`.

- [ ] **Step 2: Run the portable E2E**

Run:

```bash
make test-fixture-transcription-e2e
```

Expected:

```text
** TEST EXECUTE SUCCEEDED **
app_result=the quick brown fox jumps over the lazy dog.
app_recall=9/9
```

- [ ] **Step 3: Try to disprove that the app really uploaded audio**

Run:

```bash
tmpdir="$(mktemp -d)"
FIXTURE_TRANSCRIPTION_READY_PATH="$tmpdir/ready" \
FIXTURE_TRANSCRIPTION_RECEIPT_PATH="$tmpdir/receipt.json" \
node scripts/fixture-transcription-server.mjs >"$tmpdir/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 1 50); do [[ -s "$tmpdir/ready" ]] && break; sleep 0.1; done
base_url="$(tr -d '\r\n' <"$tmpdir/ready")"
curl -sS "${base_url}/audio/transcriptions" \
  -H "Authorization: Bearer local-fixture" \
  -F "file=@Foil/e2e-test-audio.wav;type=audio/wav" \
  -F "model=whisper-1" \
  -F "response_format=text" >/tmp/foil-fixture-curl-result.txt
kill "$server_pid"
cat "$tmpdir/receipt.json"
rm -rf "$tmpdir"
```

Expected receipt includes:

```json
"valid": true,
"hasFileField": true,
"hasRIFF": true,
"hasWAVE": true,
"model": "whisper-1"
```

- [ ] **Step 4: Run whitespace/diff hygiene**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 5: Record final evidence in the handoff**

Use this receipt shape:

```text
Claim:
Fresh Macs can run an app-level Foil transcription E2E with fixture audio and no microphone, cloud key, or local Whisper server.

Strongest realistic failure mode:
The command reports a transcript even though the app never sent real audio bytes.

Evidence:
`make test-fixture-transcription-e2e` passed and the fixture receipt recorded `valid=true`, `hasFileField=true`, `hasRIFF=true`, `hasWAVE=true`, `model=whisper-1`.

Residual risk / follow-up:
This does not prove Whisper model accuracy or local model setup. Keep using `make test-local-transcription-e2e` for real local OpenAI-compatible Whisper proof.
```

- [ ] **Step 6: Commit final adjustments**

Run:

```bash
git status --short
git add scripts/fixture-transcription-server.mjs scripts/run-fixture-transcription-e2e-xcuitest.sh Makefile docs/local-openai-compatible-transcription-e2e.md
git commit -m "test: add portable fixture transcription e2e"
```

Expected: either a final commit succeeds, or Git reports nothing to commit because Tasks 1-4 were already committed.

---

## Self-Review

**Spec coverage:** The plan covers the requested Mac app/menu-bar-version E2E by reusing the existing `--ui-testing` host for `MenuBarView` and the existing app recording/transcription/paste pipeline. It covers pre-recorded audio via `Foil/e2e-test-audio.wav`. It covers machine independence by avoiding microphone permissions, cloud keys, and local Whisper installation.

**Intentional boundary:** This is app-level E2E, not a pixel-level click on the actual macOS status item. The existing test architecture exposes the menu bar UI in a stable XCUITest window because real `NSStatusItem` automation is brittle and would add little confidence for transcription pipeline changes.

**Placeholder scan:** No task uses `TBD`, `TODO`, or vague test instructions. Each code-producing task includes exact code and commands.

**Type and command consistency:** The runner sets `E2E_TRANSCRIPTION_PROVIDER=openai-compatible`, `E2E_TRANSCRIPTION_BASE_URL=<fixture>/v1`, `E2E_TRANSCRIPTION_MODEL=whisper-1`, and `E2E_API_KEY=local-fixture`, which matches the existing `testE2ETranscription()` environment contract.

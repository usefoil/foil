# Provider QA XCUITest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an automated QA workflow for transcription provider setup that covers the manual provider preset pass, while keeping live Groq/local-server checks opt-in.

**Architecture:** Extend the existing macOS XCUITest harness with deterministic provider setup tests that run in regular CI, then add separate opt-in tests/scripts for live provider smoke checks. CI-safe tests should use UI-testing launch flags and deterministic app state; live Groq/local tests should use explicit environment variables and skip cleanly when credentials or local servers are missing.

**Tech Stack:** Swift XCTest/XCUITest, existing `GroqTalkUITests`, `UITestingController`, Makefile targets, GitHub Actions CI.

---

## File Structure

- Modify `GroqTalkUITests/GroqTalkUITests.swift`
  - Add reusable launch helpers for provider QA.
  - Add CI-safe UI tests for provider defaults, Local whisper.cpp preset UI, Custom OpenAI-compatible persistence, invalid URL validation, and switching back to Groq.
- Add opt-in live Groq provider smoke coverage using the existing real transcription XCUITest when `RUN_LIVE_GROQ_TESTS=1` and `GROQ_API_KEY` or keychain key is available.
- Modify `GroqTalk/UITestingController.swift`
  - Add narrowly scoped launch seeds for custom provider preset and invalid provider URL if direct UI picker manipulation proves too brittle.
  - Keep default `--ui-testing --reset-defaults --seed-history` behavior unchanged.
- Modify `Makefile`
  - Add a CI-safe focused target such as `test-provider-qa`.
  - Add an opt-in live target such as `test-provider-qa-live`.
- Create `scripts/run-live-groq-provider-qa-xcuitest.sh`
  - Patch the generated `.xctestrun` so `RUN_LIVE_GROQ_TESTS=1` reaches the UI test process.
- Optional: Modify `.github/workflows/ci.yml`
  - Only if the project wants the focused provider QA target as a separately named CI job. Otherwise regular `make test-ui` already covers the new CI-safe XCUITests.
- Modify `docs/local-openai-compatible-transcription-e2e.md`
  - Add a short note linking provider QA tests to local transcription E2E.
- Create `docs/provider-qa-xcuitest.md`
  - Document CI-safe and opt-in provider QA commands.

## Task 1: Add XCUITest Helpers For Provider QA

**Files:**
- Modify: `GroqTalkUITests/GroqTalkUITests.swift`

- [ ] **Step 1: Add helper methods near existing private helpers**

Add these helpers before `private var controlCenter`:

```swift
private func launchForProviderQA(extraArguments: [String] = []) {
    app.terminate()
    app = XCUIApplication()
    app.launchArguments = [
        "--ui-testing",
        "--reset-defaults",
        "--seed-history"
    ] + extraArguments
    app.launch()
    XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
}

private func openSettingsPanel() {
    app.buttons["Settings"].click()
    XCTAssertTrue(app.staticTexts["Transcription"].waitForExistence(timeout: 2), app.debugDescription)
}

private func assertProviderPickerExists() {
    XCTAssertTrue(app.popUpButtons["Provider"].waitForExistence(timeout: 2), app.debugDescription)
}
```

If `app.popUpButtons["Provider"]` is not reliable on macOS for this app, replace `assertProviderPickerExists()` with an assertion against the picker accessibility identifier once exposed:

```swift
private func assertProviderPickerExists() {
    XCTAssertTrue(app.descendants(matching: .any)["settings.transcriptionProviderPicker"].waitForExistence(timeout: 2), app.debugDescription)
}
```

- [ ] **Step 2: Run a compile check for the helper**

Run:

```bash
xcodebuild test -scheme GroqTalk -configuration Debug -destination 'platform=macOS' -only-testing:GroqTalkUITests/GroqTalkUITests/testSettingsPanelOpensInsideMenuBarPopover
```

Expected: `** TEST SUCCEEDED **`.

## Task 2: Add CI-Safe Default Groq Provider UI Test

**Files:**
- Modify: `GroqTalkUITests/GroqTalkUITests.swift`

- [ ] **Step 1: Add the failing test**

Add this test after `testSettingsPanelOpensInsideMenuBarPopover()`:

```swift
func testProviderQADefaultsToGroqPreset() {
    launchForProviderQA()
    openSettingsPanel()

    assertProviderPickerExists()
    XCTAssertTrue(app.staticTexts["Groq"].exists || app.popUpButtons["Provider"].exists, app.debugDescription)
    XCTAssertTrue(app.staticTexts["Large V3 Turbo"].exists || app.staticTexts["Whisper model"].exists, app.debugDescription)
    XCTAssertTrue(app.buttons["Change API Key"].exists)
    XCTAssertTrue(app.staticTexts["Cleanup"].exists || app.staticTexts["Transcript cleanup"].exists, app.debugDescription)
    XCTAssertFalse(app.staticTexts["Cleanup requires a Groq-compatible chat provider."].exists)
}
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
xcodebuild test -scheme GroqTalk -configuration Debug -destination 'platform=macOS' -only-testing:GroqTalkUITests/GroqTalkUITests/testProviderQADefaultsToGroqPreset
```

Expected before adjustments: either pass, or fail with a specific missing UI label. If it fails because labels differ, inspect `app.debugDescription` and update the assertions to the actual accessible labels in this app.

- [ ] **Step 3: Commit**

Run:

```bash
git add GroqTalkUITests/GroqTalkUITests.swift
git commit -m "test: cover default provider preset in ui"
```

## Task 3: Add CI-Safe Local whisper.cpp Preset UI Test

**Files:**
- Modify: `GroqTalkUITests/GroqTalkUITests.swift`

- [ ] **Step 1: Expand the existing local-provider test**

Replace `testLocalProviderSettingsShowCleanupUnavailableCopy()` with:

```swift
func testProviderQALocalWhisperPresetShowsExpectedSettings() {
    launchForProviderQA(extraArguments: ["--seed-local-provider"])
    openSettingsPanel()

    assertProviderPickerExists()
    XCTAssertTrue(app.staticTexts["http://127.0.0.1:8080/v1"].exists || app.staticTexts["127.0.0.1:8080/v1"].exists, app.debugDescription)
    XCTAssertTrue(app.staticTexts["whisper-1"].exists, app.debugDescription)
    XCTAssertTrue(app.staticTexts["API key is optional for local OpenAI-compatible transcription."].exists
                  || app.staticTexts["Uses a local OpenAI-compatible whisper.cpp server. API key is optional; use a dummy value such as local only if your server expects one."].exists,
                  app.debugDescription)
    XCTAssertTrue(app.buttons["Test connection"].exists, app.debugDescription)
    XCTAssertTrue(app.staticTexts["Cleanup requires a Groq-compatible chat provider."].waitForExistence(timeout: 2), app.debugDescription)
}
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
xcodebuild test -scheme GroqTalk -configuration Debug -destination 'platform=macOS' -only-testing:GroqTalkUITests/GroqTalkUITests/testProviderQALocalWhisperPresetShowsExpectedSettings
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**

Run:

```bash
git add GroqTalkUITests/GroqTalkUITests.swift
git commit -m "test: cover local whisper provider preset ui"
```

## Task 4: Add CI-Safe Invalid Custom URL Connection Test

**Files:**
- Modify: `GroqTalk/UITestingController.swift`
- Modify: `GroqTalkUITests/GroqTalkUITests.swift`

- [ ] **Step 1: Add a launch seed for invalid custom provider**

In `UITestingController.configureForUITesting()`, after the `--seed-local-provider` block, add:

```swift
if args.contains("--seed-invalid-custom-provider") {
    appState.selectedTranscriptionProviderPresetID = .customOpenAICompatible
    appState.customTranscriptionBaseURL = "file:///tmp/whisper"
    appState.customTranscriptionModel = "whisper-1"
}
```

- [ ] **Step 2: Add the XCUITest**

Add this test after the local provider QA test:

```swift
func testProviderQAInvalidCustomBaseURLShowsValidationStatus() {
    launchForProviderQA(extraArguments: ["--seed-invalid-custom-provider"])
    openSettingsPanel()

    XCTAssertTrue(app.buttons["Test connection"].waitForExistence(timeout: 2), app.debugDescription)
    app.buttons["Test connection"].click()

    XCTAssertTrue(
        app.staticTexts["Invalid base URL. Use an http:// or https:// URL."].waitForExistence(timeout: 2),
        app.debugDescription
    )
}
```

- [ ] **Step 3: Run the focused test**

Run:

```bash
xcodebuild test -scheme GroqTalk -configuration Debug -destination 'platform=macOS' -only-testing:GroqTalkUITests/GroqTalkUITests/testProviderQAInvalidCustomBaseURLShowsValidationStatus
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

Run:

```bash
git add GroqTalk/UITestingController.swift GroqTalkUITests/GroqTalkUITests.swift
git commit -m "test: cover invalid custom provider url in ui"
```

## Task 5: Add CI-Safe Custom Provider Persistence Test

**Files:**
- Modify: `GroqTalk/UITestingController.swift`
- Modify: `GroqTalkUITests/GroqTalkUITests.swift`

- [ ] **Step 1: Add a launch seed for valid custom provider**

In `UITestingController.configureForUITesting()`, after the invalid custom provider seed, add:

```swift
if args.contains("--seed-custom-provider") {
    appState.selectedTranscriptionProviderPresetID = .customOpenAICompatible
    appState.customTranscriptionBaseURL = "http://127.0.0.1:9090/v1"
    appState.customTranscriptionModel = "tiny-test-model"
}
```

- [ ] **Step 2: Add the XCUITest**

Add this test after the invalid URL test:

```swift
func testProviderQACustomProviderPersistsAcrossRelaunch() {
    launchForProviderQA(extraArguments: ["--seed-custom-provider"])
    openSettingsPanel()

    XCTAssertTrue(app.textFields["settings.customTranscriptionBaseURL"].waitForExistence(timeout: 2), app.debugDescription)
    XCTAssertEqual(app.textFields["settings.customTranscriptionBaseURL"].value as? String, "http://127.0.0.1:9090/v1")
    XCTAssertEqual(app.textFields["settings.customTranscriptionModel"].value as? String, "tiny-test-model")

    app.terminate()
    app = XCUIApplication()
    app.launchArguments = [
        "--ui-testing",
        "--seed-history"
    ]
    app.launch()
    XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
    openSettingsPanel()

    XCTAssertTrue(app.textFields["settings.customTranscriptionBaseURL"].waitForExistence(timeout: 2), app.debugDescription)
    XCTAssertEqual(app.textFields["settings.customTranscriptionBaseURL"].value as? String, "http://127.0.0.1:9090/v1")
    XCTAssertEqual(app.textFields["settings.customTranscriptionModel"].value as? String, "tiny-test-model")
}
```

- [ ] **Step 3: Run the focused test**

Run:

```bash
xcodebuild test -scheme GroqTalk -configuration Debug -destination 'platform=macOS' -only-testing:GroqTalkUITests/GroqTalkUITests/testProviderQACustomProviderPersistsAcrossRelaunch
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

Run:

```bash
git add GroqTalk/UITestingController.swift GroqTalkUITests/GroqTalkUITests.swift
git commit -m "test: cover custom provider persistence in ui"
```

## Task 6: Add Optional Live Groq Provider QA Target

**Files:**
- Create: `scripts/run-live-groq-provider-qa-xcuitest.sh`
- Modify: `Makefile`

- [ ] **Step 1: Add live Groq runner script**

Create `scripts/run-live-groq-provider-qa-xcuitest.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCHEME="${SCHEME:-GroqTalk}"
CONFIG="${CONFIG:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-}"
PLISTBUDDY="/usr/libexec/PlistBuddy"

patched=""
cleanup() {
  if [[ -n "${patched}" ]]; then
    rm -f "${patched}"
  fi
}
trap cleanup EXIT

api_key="${GROQ_API_KEY:-}"
if [[ -z "${api_key}" ]]; then
  api_key="$(security find-generic-password -s com.neonwatty.GroqTalk -a groq-api-key -w 2>/dev/null || true)"
fi

if [[ -z "${api_key}" ]]; then
  echo "skip: GROQ_API_KEY not found in environment or keychain"
  exit 0
fi

preflight_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  https://api.groq.com/openai/v1/models \
  -H "Authorization: Bearer ${api_key}")"
if [[ "${preflight_status}" != "200" ]]; then
  echo "error: Groq credential preflight returned HTTP ${preflight_status}" >&2
  exit 2
fi

xcodebuild build-for-testing -scheme "${SCHEME}" -configuration "${CONFIG}" -destination "${DESTINATION}"

find_root="${DERIVED_DATA_PATH:-${HOME}/Library/Developer/Xcode/DerivedData}"
xctestrun="$(find "${find_root}" -name '*.xctestrun' -path '*GroqTalk*' -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 || true)"
if [[ -z "${xctestrun}" || ! -f "${xctestrun}" ]]; then
  echo "error: could not locate generated .xctestrun" >&2
  exit 1
fi

patched="${xctestrun%.xctestrun}.live-groq-provider-qa.xctestrun"
cp "${xctestrun}" "${patched}"

ui_target_index=""
for index in $(seq 0 20); do
  blueprint="$("${PLISTBUDDY}" -c "Print :TestConfigurations:0:TestTargets:${index}:BlueprintName" "${patched}" 2>/dev/null || true)"
  if [[ "${blueprint}" == "GroqTalkUITests" ]]; then
    ui_target_index="${index}"
    break
  fi
  if [[ -z "${blueprint}" ]]; then
    break
  fi
done

if [[ -z "${ui_target_index}" ]]; then
  echo "error: GroqTalkUITests target not found in ${patched}" >&2
  exit 1
fi

env_root=":TestConfigurations:0:TestTargets:${ui_target_index}:EnvironmentVariables"
for key in RUN_LIVE_GROQ_TESTS E2E_TRANSCRIPTION_TIMEOUT_SECONDS; do
  "${PLISTBUDDY}" -c "Delete ${env_root}:${key}" "${patched}" >/dev/null 2>&1 || true
done
"${PLISTBUDDY}" -c "Add ${env_root}:RUN_LIVE_GROQ_TESTS string 1" "${patched}"
"${PLISTBUDDY}" -c "Add ${env_root}:E2E_TRANSCRIPTION_TIMEOUT_SECONDS string ${E2E_TRANSCRIPTION_TIMEOUT_SECONDS:-90}" "${patched}"

xcodebuild test-without-building \
  -xctestrun "${patched}" \
  -destination "${DESTINATION}" \
  -only-testing:GroqTalkUITests/GroqTalkUITests/testE2ETranscription
```

Run:

```bash
chmod +x scripts/run-live-groq-provider-qa-xcuitest.sh
```

- [ ] **Step 2: Add Makefile target**

Add `test-provider-qa-live` to `.PHONY`, then add:

```make
test-provider-qa-live:
	SCHEME="$(SCHEME)" CONFIG="$(CONFIG)" scripts/run-live-groq-provider-qa-xcuitest.sh
```

- [ ] **Step 3: Run with keychain or env key**

Run:

```bash
make test-provider-qa-live
```

Expected when Groq key is available: `** TEST SUCCEEDED **`.

Expected when Groq key is absent: test is skipped with `GROQ_API_KEY not found in env or keychain`.

- [ ] **Step 4: Commit**

Run:

```bash
git add Makefile scripts/run-live-groq-provider-qa-xcuitest.sh
git commit -m "test: add opt-in live groq provider qa"
```

## Task 7: Add Focused Provider QA Make Target

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add target to `.PHONY`**

Append `test-provider-qa` to the `.PHONY` line.

- [ ] **Step 2: Add focused target**

Add near `test-ui`:

```make
test-provider-qa:
	@tmp=$$(mktemp); \
	xcodebuild test -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' \
		-only-testing:GroqTalkUITests/GroqTalkUITests/testProviderQADefaultsToGroqPreset \
		-only-testing:GroqTalkUITests/GroqTalkUITests/testProviderQALocalWhisperPresetShowsExpectedSettings \
		-only-testing:GroqTalkUITests/GroqTalkUITests/testProviderQAInvalidCustomBaseURLShowsValidationStatus \
		-only-testing:GroqTalkUITests/GroqTalkUITests/testProviderQACustomProviderPersistsAcrossRelaunch >"$$tmp" 2>&1; \
	status=$$?; tail -8 "$$tmp"; \
	if ! grep -q '\*\* TEST SUCCEEDED \*\*' "$$tmp"; then status=1; fi; \
	rm -f "$$tmp"; exit $$status
```

- [ ] **Step 3: Run target**

Run:

```bash
make test-provider-qa
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

Run:

```bash
git add Makefile
git commit -m "test: add focused provider qa target"
```

## Task 8: Document Provider QA Automation

**Files:**
- Create: `docs/provider-qa-xcuitest.md`
- Modify: `docs/local-openai-compatible-transcription-e2e.md`

- [ ] **Step 1: Create provider QA docs**

Create `docs/provider-qa-xcuitest.md`:

```markdown
# Provider QA XCUITests

GroqTalk has two provider QA paths:

## CI-safe provider setup QA

Run:

```bash
make test-provider-qa
```

This covers:

- Groq default provider UI
- Local whisper.cpp preset copy and cleanup-unavailable state
- Custom OpenAI-compatible invalid base URL validation
- Custom OpenAI-compatible persistence across relaunch

This target does not require network access, Groq credentials, whisper.cpp, or model files.

## Live Groq provider QA

Run:

```bash
make test-provider-qa-live
```

This is opt-in. It requires either:

- `GROQ_API_KEY` in the environment, or
- an existing Groq API key in the macOS keychain account used by GroqTalk.

If no key is available, the XCUITest skips cleanly.

## Local transcription E2E

For the real local Whisper transcription path, run:

```bash
LOCAL_E2E_LATENCY_RUNS=10 make test-local-transcription-e2e
```

That target requires a local OpenAI-compatible Whisper server.
```

- [ ] **Step 2: Link from local E2E docs**

Add this sentence near the top of `docs/local-openai-compatible-transcription-e2e.md`:

```markdown
For provider setup UI automation that does not require a local server, see `docs/provider-qa-xcuitest.md`.
```

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/provider-qa-xcuitest.md docs/local-openai-compatible-transcription-e2e.md
git commit -m "docs: explain provider qa xcuitests"
```

## Task 9: Final Verification

**Files:**
- Inspect all changed files.

- [ ] **Step 1: Run deterministic tests**

Run:

```bash
make test-provider-qa
make test-ui
make test
make build-warnings-as-errors
git diff --check
```

Expected:

- `make test-provider-qa`: `** TEST SUCCEEDED **`
- `make test-ui`: `** TEST SUCCEEDED **`
- `make test`: `** TEST SUCCEEDED **`
- `make build-warnings-as-errors`: `** BUILD SUCCEEDED **`
- `git diff --check`: no output

- [ ] **Step 2: Run opt-in live Groq provider QA if key is available**

Run:

```bash
make test-provider-qa-live
```

Expected if key is available: `** TEST SUCCEEDED **`.

Expected if no key is available: XCUITest skip with `GROQ_API_KEY not found in env or keychain`.

- [ ] **Step 3: Run local E2E if whisper.cpp server is running**

Run:

```bash
LOCAL_E2E_LATENCY_RUNS=10 make test-local-transcription-e2e
```

Expected when local server is running:

- endpoint smoke returns HTTP 200
- transcript matches at least 8/9 expected words
- XCUITest `testE2ETranscription` passes

- [ ] **Step 4: Run code review**

Run:

```bash
/Users/neonwatty/.codex/skills/codex-review/scripts/codex-review --full-access
```

Expected: `codex-review clean: no accepted/actionable findings reported`.

## Acceptance Criteria

- `make test-provider-qa` exists and runs a focused CI-safe provider setup XCUITest workflow.
- The provider QA workflow verifies Groq default provider UI without requiring Groq network access.
- The workflow verifies Local whisper.cpp preset base URL/model/copy/cleanup-unavailable state without requiring a local server.
- The workflow verifies invalid Custom OpenAI-compatible URL status before network.
- The workflow verifies Custom OpenAI-compatible base URL/model persistence across relaunch.
- Live Groq provider QA is opt-in and skips cleanly without a key.
- Existing `make test-ui` remains free of live Groq credentials, network, whisper.cpp, and model files.
- Existing `make test-local-transcription-e2e` remains the opt-in real local transcription check.
- No API keys are stored in UserDefaults.
- No model files, whisper.cpp checkout, generated `.xctestrun`, or local build artifacts are committed.

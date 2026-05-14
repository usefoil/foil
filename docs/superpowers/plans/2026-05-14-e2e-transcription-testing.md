# E2E Transcription Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automated end-to-end test that feeds pre-recorded speech through the real Groq API via the full app pipeline (RecordingController → TranscriptionController → history → paste) without a microphone.

**Architecture:** An `E2EAudioStub` (AudioRecording conformer) returns a pre-generated WAV file from macOS `say`. UITestingController detects `--e2e-transcribe`, swaps the recording controller to use the stub, and triggers the record→stop flow. A UI test verifies the transcribed text in the history.

**Tech Stack:** Swift, XCTest, XCUITest, macOS `say` command, Groq Whisper API

---

## Phase 1: E2EAudioStub + RecordingController swap

**PR checkpoint after this phase.** Merge before proceeding to Phase 2.

### Task 1: Create E2EAudioStub

**Files:**
- Create: `GroqTalk/E2EAudioStub.swift`

**Acceptance criteria:** Builds successfully. Stub conforms to `AudioRecording`. Gated behind `#if DEBUG`.

- [ ] **Step 1: Create the stub file**

```swift
// GroqTalk/E2EAudioStub.swift
import CoreAudio
import Foundation

#if DEBUG
/// AudioRecording stub that returns a pre-generated audio file instead of recording from the mic.
/// Used by UITestingController for E2E transcription tests.
final class E2EAudioStub: AudioRecording {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func startRecording(deviceID: AudioDeviceID?) throws {
        // No-op: no microphone needed
    }

    func stopRecordingAsync(format: AudioFormat) async throws -> URL? {
        return fileURL
    }

    func cancelRecording() {
        // No-op
    }
}
#endif
```

- [ ] **Step 2: Register in Xcode project**

Add `E2EAudioStub.swift` to `GroqTalk.xcodeproj/project.pbxproj`:
- PBXFileReference entry
- PBXBuildFile entry for GroqTalk target Sources
- PBXGroup entry in the GroqTalk group (alphabetically near `DiagnosticLog.swift`)

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project GroqTalk.xcodeproj -scheme GroqTalk -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add GroqTalk/E2EAudioStub.swift GroqTalk.xcodeproj/project.pbxproj
git commit -m "feat: add E2EAudioStub for injecting pre-recorded audio in tests"
```

---

### Task 2: Expose recording controller replacement in AppDelegate

**Files:**
- Modify: `GroqTalk/GroqTalkApp.swift:80` (change `recordingController` visibility)
- Modify: `GroqTalk/GroqTalkApp.swift:176-192` (add callback to UITestingController init)
- Modify: `GroqTalk/UITestingController.swift:47-81` (accept new callback)

**Acceptance criteria:** `UITestingController` can replace AppDelegate's recording controller. Build succeeds. All existing tests pass.

- [ ] **Step 1: Add `replaceRecordingController` method to AppDelegate**

In `GroqTalk/GroqTalkApp.swift`, add a method after the existing `wireHotkeyMonitor()` method (around line 411):

```swift
    /// Replace the recording controller with one backed by a different AudioRecording.
    /// Used by UITestingController for E2E transcription tests.
    func replaceRecordingController(with newController: RecordingController) {
        recordingController.invalidateTimers()
        recordingController = newController
        recordingController.delegate = self
    }
```

- [ ] **Step 2: Add `onReplaceRecordingController` callback to UITestingController**

In `GroqTalk/UITestingController.swift`, add to the stored properties (after line 37):

```swift
    private let onReplaceRecordingController: (RecordingController) -> Void
```

Add the parameter to `init` (after `onPasteText` at line 63):

```swift
        onReplaceRecordingController: @escaping (RecordingController) -> Void
```

Assign in the init body (after line 80):

```swift
        self.onReplaceRecordingController = onReplaceRecordingController
```

- [ ] **Step 3: Pass the callback from AppDelegate**

In `GroqTalk/GroqTalkApp.swift`, in the `UITestingController(...)` init call (around line 176-192), add after `onPasteText`:

```swift
            onReplaceRecordingController: { [weak self] controller in
                self?.replaceRecordingController(with: controller)
            }
```

- [ ] **Step 4: Build and run full test suite**

Run: `xcodebuild -project GroqTalk.xcodeproj -scheme GroqTalk -destination 'platform=macOS' test -only-testing:GroqTalkTests 2>&1 | grep -E "(Test Suite.*(passed|failed)|TEST)" | tail -5`

Expected: `** TEST SUCCEEDED **` (only pre-existing failures allowed, currently zero)

- [ ] **Step 5: Commit**

```bash
git add GroqTalk/GroqTalkApp.swift GroqTalk/UITestingController.swift
git commit -m "feat: expose recording controller replacement for E2E testing"
```

---

### Task 3: PR Phase 1

**Acceptance criteria:** PR passes CI (Build, Unit Tests, UI Tests, CI Gate). Code review clean.

- [ ] **Step 1: Push and create PR**

```bash
git push -u origin <branch>
gh pr create --base feat/initial-implementation \
  --title "feat: E2E transcription test infrastructure (stub + controller swap)" \
  --body "Phase 1 of E2E transcription testing. Adds E2EAudioStub and wiring to replace the recording controller in test mode. No behavioral changes to production code."
```

- [ ] **Step 2: Monitor CI**

```bash
gh pr checks <PR_NUMBER> --watch
```

Expected: All checks pass (Build, Unit Tests, UI Tests, CI Gate).

- [ ] **Step 3: Merge**

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch
```

---

## Phase 2: UITestingController E2E transcription flow

**PR checkpoint after this phase.** Merge before proceeding to Phase 3.

### Task 4: Add `configureE2ETranscribeIfNeeded()` to UITestingController

**Files:**
- Modify: `GroqTalk/UITestingController.swift` (add E2E method after `configureAutomationSmokeIfNeeded`)
- Modify: `GroqTalk/GroqTalkApp.swift` (call new method in `applicationDidFinishLaunching`)

**Acceptance criteria:** When launched with `--e2e-transcribe --ui-testing`, the app generates a WAV file via `say`, swaps in the E2EAudioStub, triggers the recording→stop→transcribe flow, and the result appears in history. Manually verifiable before the UI test exists.

- [ ] **Step 1: Add the E2E method to UITestingController**

In `GroqTalk/UITestingController.swift`, add after `configureAutomationSmokeIfNeeded()` (around line 131):

```swift
    // MARK: - E2E transcription

    /// Generates a speech WAV file using macOS `say`, swaps the recording controller
    /// to use an E2EAudioStub, and triggers the recording→transcribe flow.
    /// Activated by the `--e2e-transcribe` launch argument.
    func configureE2ETranscribeIfNeeded() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--e2e-transcribe") else { return }

        let phrase = "the quick brown fox jumps over the lazy dog"
        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("groqtalk-e2e-\(UUID().uuidString).wav")

        // Generate speech audio via macOS say command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [phrase, "-o", wavURL.path, "--file-format=WAVE", "--data-format=LEI16@16000"]
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                DiagnosticLog.write("E2E: say command failed with status \(process.terminationStatus)")
                return
            }
        } catch {
            DiagnosticLog.write("E2E: failed to run say command: \(error)")
            return
        }

        DiagnosticLog.write("E2E: generated WAV at \(wavURL.path)")

        // Swap recording controller to use the audio stub
        let stub = E2EAudioStub(fileURL: wavURL)
        let controller = RecordingController(audioRecorder: stub, appState: appState)
        onReplaceRecordingController(controller)

        // Set audio format to WAV to match the generated file
        appState.selectedAudioFormat = .wav

        // Trigger the recording→stop→transcribe flow after a short delay
        // to let the app finish launching
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            DiagnosticLog.write("E2E: starting simulated recording")
            onStartRecording()
            try? await Task.sleep(for: .milliseconds(200))
            DiagnosticLog.write("E2E: stopping simulated recording")
            onStopRecording()
        }
        #endif
    }
```

- [ ] **Step 2: Call the method from AppDelegate**

In `GroqTalk/GroqTalkApp.swift`, in `applicationDidFinishLaunching`, add after `uiTestingCtrl.configureAutomationSmokeIfNeeded()` (line 196):

```swift
        uiTestingCtrl.configureE2ETranscribeIfNeeded()
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project GroqTalk.xcodeproj -scheme GroqTalk -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run existing test suite to verify no regressions**

Run: `xcodebuild -project GroqTalk.xcodeproj -scheme GroqTalk -destination 'platform=macOS' test -only-testing:GroqTalkTests 2>&1 | grep -E "(Test Suite.*(passed|failed)|TEST)" | tail -5`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add GroqTalk/UITestingController.swift GroqTalk/GroqTalkApp.swift
git commit -m "feat: add E2E transcription flow via say-generated audio"
```

---

### Task 5: PR Phase 2

**Acceptance criteria:** PR passes CI. The `--e2e-transcribe` path compiles and doesn't affect existing tests.

- [ ] **Step 1: Push and create PR**

```bash
git push -u origin <branch>
gh pr create --base feat/initial-implementation \
  --title "feat: E2E transcription flow via say-generated audio" \
  --body "Phase 2: UITestingController detects --e2e-transcribe, generates speech WAV via macOS say, swaps the recording controller, and triggers the real transcription pipeline."
```

- [ ] **Step 2: Monitor CI and merge**

```bash
gh pr checks <PR_NUMBER> --watch
gh pr merge <PR_NUMBER> --squash --delete-branch
```

---

## Phase 3: UI test + CI workflow

**PR checkpoint after this phase.** This is the final phase.

### Task 6: Add the E2E transcription UI test

**Files:**
- Modify: `GroqTalkUITests/GroqTalkUITests.swift` (add test method)

**Acceptance criteria:** Test launches app with `--e2e-transcribe`, waits for transcription to complete, reads the history, and asserts the transcribed text approximately matches "the quick brown fox jumps over the lazy dog". Test is skipped when `GROQ_API_KEY` is not set. Test passes locally when the key is available.

- [ ] **Step 1: Write the UI test**

Add to `GroqTalkUITests/GroqTalkUITests.swift`, before the `private var controlCenter` computed property (line 251):

```swift
    // MARK: - E2E Transcription (requires GROQ_API_KEY)

    func testE2ETranscription() throws {
        // Skip if no API key available
        guard KeychainHasGroqKey() else {
            throw XCTSkip("GROQ_API_KEY not in keychain — skipping E2E transcription test")
        }

        // Relaunch with E2E transcribe mode
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--e2e-transcribe"
        ]
        app.launch()

        let controlCenter = app.windows["GroqTalk UI Test"].exists
            ? app.windows["GroqTalk UI Test"]
            : app.staticTexts["Ready"]
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), "App should launch")

        // Wait for transcription to complete — status should return to Ready or show error
        let ready = app.staticTexts["Ready"]
        let transcribing = app.staticTexts["Transcribing"]

        // Wait for transcribing to start (up to 5s for say + app startup)
        _ = transcribing.waitForExistence(timeout: 5)

        // Wait for transcribing to finish (up to 25s for Groq API)
        if transcribing.exists {
            XCTAssertTrue(ready.waitForExistence(timeout: 25),
                          "Transcription should complete within 25 seconds")
        }

        // Check for error state
        if case let errorText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'error' OR label CONTAINS 'Error' OR label CONTAINS 'unavailable'")
        ), errorText.count > 0 {
            XCTFail("Transcription failed: \(errorText.firstMatch.label)")
            return
        }

        // Open history to find the transcribed text
        app.buttons["History"].click()
        XCTAssertTrue(app.windows["History"].waitForExistence(timeout: 3),
                      "History window should open")

        // Find the first history row's text content
        // The most recent transcript should be the E2E result
        let historyRows = app.windows["History"].staticTexts
        let expected = "the quick brown fox jumps over the lazy dog"
        let expectedWords = Set(expected.split(separator: " ").map { String($0) })

        // Search all static texts for one that contains the expected words
        var foundTranscript: String?
        for i in 0..<historyRows.count {
            let label = historyRows.element(boundBy: i).label
            let normalizedLabel = normalize(label)
            let labelWords = Set(normalizedLabel.split(separator: " ").map { String($0) })
            let matchCount = expectedWords.intersection(labelWords).count
            if matchCount >= expectedWords.count / 2 {
                foundTranscript = label
                break
            }
        }

        guard let transcript = foundTranscript else {
            XCTFail("Could not find E2E transcription in history. History texts: \(historyRows.allElementsBoundByIndex.map { $0.label })")
            return
        }

        // Assert approximate match: every expected word should appear in the transcript
        let normalizedTranscript = normalize(transcript)
        let transcriptWords = Set(normalizedTranscript.split(separator: " ").map { String($0) })
        let missingWords = expectedWords.subtracting(transcriptWords)

        XCTAssertTrue(missingWords.count <= 1,
                      "Transcript '\(transcript)' is missing words: \(missingWords.sorted()). Expected: '\(expected)'")
    }

    // MARK: - E2E Helpers

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .reduce(into: "") { $0.append(Character($1)) }
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func KeychainHasGroqKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.neonwatty.GroqTalk",
            kSecAttrAccount as String: "groq-api-key",
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project GroqTalk.xcodeproj -scheme GroqTalk -destination 'platform=macOS' build-for-testing 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run the E2E test locally**

Ensure `GROQ_API_KEY` is in the keychain (done earlier this session), then:

Run: `xcodebuild -project GroqTalk.xcodeproj -scheme GroqTalk -destination 'platform=macOS' test -only-testing:GroqTalkUITests/GroqTalkUITests/testE2ETranscription 2>&1 | grep -E "(Test Case|TEST)" | tail -5`

Expected: `Test Case '-[GroqTalkUITests.GroqTalkUITests testE2ETranscription]' passed` and `** TEST SUCCEEDED **`

- [ ] **Step 4: Run the full UI test suite to verify no regressions**

Run: `xcodebuild -project GroqTalk.xcodeproj -scheme GroqTalk -destination 'platform=macOS' test -only-testing:GroqTalkUITests 2>&1 | grep -E "(Test Case.*failed|Test Suite.*(passed|failed)|TEST)" | tail -10`

Expected: All existing UI tests still pass. `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add GroqTalkUITests/GroqTalkUITests.swift
git commit -m "test: add E2E transcription UI test with Groq API"
```

---

### Task 7: Extend CI workflow

**Files:**
- Modify: `.github/workflows/e2e.yml`

**Acceptance criteria:** The E2E UI test runs in CI when `GROQ_API_KEY` secret is set. Skipped gracefully when not set.

- [ ] **Step 1: Add E2E UI test step to the workflow**

In `.github/workflows/e2e.yml`, add after the existing "Run live Groq E2E tests" step (after line 47):

```yaml
      - name: Run E2E transcription UI test
        env:
          GROQ_API_KEY: ${{ secrets.GROQ_API_KEY }}
        run: |
          if [ -z "$GROQ_API_KEY" ]; then
            echo "::warning::GROQ_API_KEY secret not set — skipping E2E UI test"
            exit 0
          fi

          # Ensure API key is in the keychain for the test host
          security add-generic-password \
            -s "com.neonwatty.GroqTalk" \
            -a "groq-api-key" \
            -w "$GROQ_API_KEY" -U 2>/dev/null || true

          xcodebuild test \
            -scheme GroqTalk \
            -configuration Debug \
            -destination 'platform=macOS' \
            -only-testing:GroqTalkUITests/GroqTalkUITests/testE2ETranscription \
            | xcpretty --color && exit ${PIPESTATUS[0]}
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/e2e.yml
git commit -m "ci: add E2E transcription UI test to workflow"
```

---

### Task 8: PR Phase 3

**Acceptance criteria:** PR passes CI (Build, Unit Tests, UI Tests, CI Gate). E2E test runs successfully in CI (or skips gracefully if `GROQ_API_KEY` is not available on the PR check runner — it only runs on main push).

- [ ] **Step 1: Push and create PR**

```bash
git push -u origin <branch>
gh pr create --base feat/initial-implementation \
  --title "test: E2E transcription UI test with Groq API" \
  --body "## Summary
- Adds UI test that launches app with --e2e-transcribe, verifies real Groq API transcription
- Extends CI workflow to run the E2E test when GROQ_API_KEY is available
- Audio generated via macOS say command (no bundled assets)
- Assertion: normalized word-by-word match with tolerance for Whisper quirks

## Test plan
- [x] E2E test passes locally with GROQ_API_KEY in keychain
- [x] Full UI test suite passes (no regressions)
- [x] CI workflow updated
- [ ] E2E test runs in CI on merge to main"
```

- [ ] **Step 2: Monitor CI and merge**

```bash
gh pr checks <PR_NUMBER> --watch
gh pr merge <PR_NUMBER> --squash --delete-branch
```

---

### Task 9: Merge to main and verify CI E2E

**Acceptance criteria:** The E2E transcription test runs and passes in the CI workflow on main.

- [ ] **Step 1: Create PR from feat/initial-implementation to main**

Follow the same merge branch pattern used previously (resolve CHANGELOG conflicts if any).

- [ ] **Step 2: Merge to main**

```bash
gh pr merge <PR_NUMBER> --merge
```

- [ ] **Step 3: Monitor the E2E workflow on main**

```bash
gh run list --repo mean-weasel/groqtalk --branch main --workflow "E2E Groq API Tests" --limit 1
gh run watch <RUN_ID> --repo mean-weasel/groqtalk
```

Expected: Both the existing integration tests and the new E2E UI test pass.

---

## Summary

| Phase | Tasks | PR | What it delivers |
|-------|-------|----|-----------------|
| **1** | Tasks 1-3 | PR to `feat/initial-implementation` | Stub + controller swap wiring (no behavior change) |
| **2** | Tasks 4-5 | PR to `feat/initial-implementation` | E2E transcription flow triggered by `--e2e-transcribe` |
| **3** | Tasks 6-8 | PR to `feat/initial-implementation` | UI test + CI workflow |
| **Ship** | Task 9 | PR to `main` | E2E test runs in CI, triggers release |

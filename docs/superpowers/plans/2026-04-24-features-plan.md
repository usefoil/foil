# Features Implementation Plan (Language Hint + History Popover)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a language hint picker and a scrollable history popover to the GroqTalk menu bar app.

**Architecture:** A new `Language` enum follows the same pattern as `AudioFormat` — top-level, `CaseIterable`, `Codable`, used across `AppState`, `TranscriptionService`, `MenuBarView`, and `GroqTalkApp`. The history popover is a new `HistoryPopoverView` opened from the menu bar, backed by the existing `TranscriptionHistory` data layer with no schema changes.

**Tech Stack:** SwiftUI, AVFAudio, Groq Whisper API (multipart `language` field)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `GroqTalk/AudioRecorder.swift` | Modify (lines 6-20) | Add `Language` enum below `AudioFormat` |
| `GroqTalk/AppState.swift` | Modify | Add `selectedLanguage` property |
| `GroqTalk/TranscriptionService.swift` | Modify | Accept `language` param, conditionally add to multipart body |
| `GroqTalk/MenuBarView.swift` | Modify | Add Language picker, replace history menu with popover button |
| `GroqTalk/HistoryPopoverView.swift` | Create | Popover content: search, scrollable list, copy, retry |
| `GroqTalk/GroqTalkApp.swift` | Modify | Pass language to transcribe calls, wire popover retry |
| `GroqTalkTests/LanguageTests.swift` | Create | Language enum + multipart body tests |
| `GroqTalkTests/HistoryPopoverTests.swift` | Create | Popover filtering/interaction tests |

---

### Task 1: Language Enum

**Files:**
- Modify: `GroqTalk/AudioRecorder.swift` (add enum after `AudioFormat`, line 20)
- Test: `GroqTalkTests/LanguageTests.swift` (create)

- [ ] **Step 1: Write the failing tests for Language enum**

Create `GroqTalkTests/LanguageTests.swift`:

```swift
import XCTest
@testable import GroqTalk

final class LanguageTests: XCTestCase {
    func testLanguageRawValues() {
        XCTAssertEqual(Language.auto.rawValue, "auto")
        XCTAssertEqual(Language.en.rawValue, "en")
        XCTAssertEqual(Language.ja.rawValue, "ja")
    }

    func testLanguageDisplayNames() {
        XCTAssertEqual(Language.auto.displayName, "Auto-detect")
        XCTAssertEqual(Language.en.displayName, "English")
        XCTAssertEqual(Language.es.displayName, "Spanish")
        XCTAssertEqual(Language.fr.displayName, "French")
        XCTAssertEqual(Language.de.displayName, "German")
        XCTAssertEqual(Language.pt.displayName, "Portuguese")
        XCTAssertEqual(Language.it.displayName, "Italian")
        XCTAssertEqual(Language.ja.displayName, "Japanese")
        XCTAssertEqual(Language.zh.displayName, "Chinese")
        XCTAssertEqual(Language.ko.displayName, "Korean")
        XCTAssertEqual(Language.hi.displayName, "Hindi")
        XCTAssertEqual(Language.ar.displayName, "Arabic")
        XCTAssertEqual(Language.ru.displayName, "Russian")
    }

    func testLanguageCaseIterable() {
        XCTAssertEqual(Language.allCases.count, 13)
    }

    func testLanguageCodableRoundTrip() throws {
        let original = Language.ja
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Language.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme GroqTalk -destination 'platform=macOS' -only-testing:GroqTalkTests/LanguageTests 2>&1 | tail -5`
Expected: Build failure — `Language` type not found

- [ ] **Step 3: Implement Language enum**

Add to `GroqTalk/AudioRecorder.swift` after the closing brace of `AudioFormat` (after line 20), before `final class AudioRecorder`:

```swift
/// Language hint for Whisper transcription. When not `.auto`, the ISO 639-1
/// code is sent to improve accuracy for non-English audio.
enum Language: String, CaseIterable, Codable {
    case auto
    case en, es, fr, de, pt, it, ja, zh, ko, hi, ar, ru

    var displayName: String {
        switch self {
        case .auto: "Auto-detect"
        case .en:   "English"
        case .es:   "Spanish"
        case .fr:   "French"
        case .de:   "German"
        case .pt:   "Portuguese"
        case .it:   "Italian"
        case .ja:   "Japanese"
        case .zh:   "Chinese"
        case .ko:   "Korean"
        case .hi:   "Hindi"
        case .ar:   "Arabic"
        case .ru:   "Russian"
        }
    }
}
```

- [ ] **Step 4: Add test file to Xcode project**

Add `GroqTalkTests/LanguageTests.swift` to the `GroqTalkTests` target in `GroqTalk.xcodeproj/project.pbxproj` — PBXBuildFile, PBXFileReference, PBXGroup (children of GroqTalkTests), and PBXSourcesBuildPhase sections.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme GroqTalk -destination 'platform=macOS' -only-testing:GroqTalkTests/LanguageTests 2>&1 | tail -5`
Expected: 4 tests pass

- [ ] **Step 6: Commit**

```bash
git add GroqTalk/AudioRecorder.swift GroqTalkTests/LanguageTests.swift GroqTalk.xcodeproj/project.pbxproj
git commit -m "feat: add Language enum with ISO 639-1 codes and display names"
```

---

### Task 2: Language in Multipart Body

**Files:**
- Modify: `GroqTalk/TranscriptionService.swift:6,37` (add `language` param)
- Test: `GroqTalkTests/LanguageTests.swift` (add tests)
- Modify: `GroqTalkTests/TranscriptionServiceTests.swift` (update existing calls)

- [ ] **Step 1: Write the failing tests for language in multipart body**

Add to `GroqTalkTests/LanguageTests.swift`:

```swift
func testMultipartBodyOmitsLanguageWhenAuto() throws {
    let service = TranscriptionService()
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-lang.wav")
    try Data([0x00]).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let body = try service.buildMultipartBody(
        audioFileURL: tempURL, model: "m", format: .wav,
        language: .auto, boundary: "b"
    )
    let bodyString = String(data: body, encoding: .utf8)!
    XCTAssertFalse(bodyString.contains("name=\"language\""),
                   "Auto-detect should not include language field")
}

func testMultipartBodyIncludesLanguageWhenSet() throws {
    let service = TranscriptionService()
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-lang2.wav")
    try Data([0x00]).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let body = try service.buildMultipartBody(
        audioFileURL: tempURL, model: "m", format: .wav,
        language: .ja, boundary: "b"
    )
    let bodyString = String(data: body, encoding: .utf8)!
    XCTAssertTrue(bodyString.contains("name=\"language\"\r\n\r\nja"),
                  "Japanese should send language=ja")
}

func testMultipartBodyLanguageFieldPerLanguage() throws {
    let service = TranscriptionService()
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-lang3.wav")
    try Data([0x00]).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    for lang in Language.allCases where lang != .auto {
        let body = try service.buildMultipartBody(
            audioFileURL: tempURL, model: "m", format: .wav,
            language: lang, boundary: "b"
        )
        let bodyString = String(data: body, encoding: .utf8)!
        XCTAssertTrue(
            bodyString.contains("name=\"language\"\r\n\r\n\(lang.rawValue)"),
            "\(lang.displayName) should send language=\(lang.rawValue)"
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme GroqTalk -destination 'platform=macOS' -only-testing:GroqTalkTests/LanguageTests 2>&1 | tail -5`
Expected: Build failure — `buildMultipartBody` has no `language` parameter

- [ ] **Step 3: Add language parameter to buildMultipartBody**

In `GroqTalk/TranscriptionService.swift`, change the `buildMultipartBody` signature (line 37) and add the conditional language field:

```swift
func buildMultipartBody(audioFileURL: URL, model: String, format: AudioFormat, language: Language = .auto, boundary: String) throws -> Data {
    let audioData = try Data(contentsOf: audioFileURL)
    var body = Data()

    body.appendString("--\(boundary)\r\n")
    body.appendString("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
    body.appendString("\(model)\r\n")

    body.appendString("--\(boundary)\r\n")
    body.appendString("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
    body.appendString("text\r\n")

    if language != .auto {
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.appendString("\(language.rawValue)\r\n")
    }

    body.appendString("--\(boundary)\r\n")
    body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(format.filename)\"\r\n")
    body.appendString("Content-Type: \(format.contentType)\r\n\r\n")
    body.append(audioData)
    body.appendString("\r\n")

    body.appendString("--\(boundary)--\r\n")
    return body
}
```

- [ ] **Step 4: Add language parameter to transcribe method**

In `GroqTalk/TranscriptionService.swift`, update the `transcribe` signature (line 6):

```swift
func transcribe(audioFileURL: URL, apiKey: String, model: String, format: AudioFormat = .wav, language: Language = .auto) async throws -> String {
```

And update the `buildMultipartBody` call inside it (line 12-14):

```swift
request.httpBody = try buildMultipartBody(
    audioFileURL: audioFileURL, model: model, format: format, language: language, boundary: boundary
)
```

- [ ] **Step 5: Run all tests to verify they pass**

Run: `xcodebuild test -scheme GroqTalk -destination 'platform=macOS' 2>&1 | grep -E '(Executed|TEST)' | tail -3`
Expected: All tests pass (existing tests still work because `language` defaults to `.auto`)

- [ ] **Step 6: Commit**

```bash
git add GroqTalk/TranscriptionService.swift GroqTalkTests/LanguageTests.swift
git commit -m "feat: add language hint to multipart body and transcribe API"
```

---

### Task 3: Language in AppState and Menu

**Files:**
- Modify: `GroqTalk/AppState.swift` (add `selectedLanguage` property)
- Modify: `GroqTalk/MenuBarView.swift` (add Language picker)
- Modify: `GroqTalk/GroqTalkApp.swift` (pass language to transcribe calls)
- Test: `GroqTalkTests/LanguageTests.swift` (add AppState tests)

- [ ] **Step 1: Write the failing tests for AppState language property**

Add to `GroqTalkTests/LanguageTests.swift`:

```swift
@MainActor
func testAppStateDefaultLanguageIsAuto() {
    UserDefaults.standard.removeObject(forKey: "language")
    let state = AppState()
    XCTAssertEqual(state.selectedLanguage, .auto)
}

@MainActor
func testAppStateLanguagePersists() {
    UserDefaults.standard.removeObject(forKey: "language")
    let state = AppState()
    state.selectedLanguage = .ja
    XCTAssertEqual(state.selectedLanguage, .ja)

    let state2 = AppState()
    XCTAssertEqual(state2.selectedLanguage, .ja)
    UserDefaults.standard.removeObject(forKey: "language")
}

@MainActor
func testAppStateInvalidLanguageFallsBackToAuto() {
    UserDefaults.standard.set("invalid", forKey: "language")
    let state = AppState()
    XCTAssertEqual(state.selectedLanguage, .auto)
    UserDefaults.standard.removeObject(forKey: "language")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme GroqTalk -destination 'platform=macOS' -only-testing:GroqTalkTests/LanguageTests 2>&1 | tail -5`
Expected: Build failure — `selectedLanguage` property not found on `AppState`

- [ ] **Step 3: Add selectedLanguage to AppState**

In `GroqTalk/AppState.swift`, add after the `selectedAudioFormat` property (after line 36):

```swift
var selectedLanguage: Language {
    get { Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .auto }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: "language") }
}
```

And add `"language": "auto"` to the `register(defaults:)` call in `init()` (line 91):

```swift
UserDefaults.standard.register(defaults: [
    "soundEffectsEnabled": true,
    "whisperModel": "whisper-large-v3-turbo",
    "audioFormat": "m4a",
    "keepOnClipboard": false,
    "recordingMode": "hold",
    "hotkeyChoice": "rightCommand",
    "language": "auto"
])
```

- [ ] **Step 4: Add Language picker to MenuBarView**

In `GroqTalk/MenuBarView.swift`, add after the Audio Format picker (after line 31):

```swift
Picker("Language", selection: $appState.selectedLanguage) {
    ForEach(Language.allCases, id: \.self) { lang in
        Text(lang.displayName).tag(lang)
    }
}
```

- [ ] **Step 5: Pass language to transcribe calls in GroqTalkApp**

In `GroqTalk/GroqTalkApp.swift`, update the transcribe call in `onRecordingStopped` (line 199-204):

```swift
let text = try await self.transcriptionService.transcribe(
    audioFileURL: url,
    apiKey: apiKey,
    model: self.appState.selectedModel,
    format: self.appState.selectedAudioFormat,
    language: self.appState.selectedLanguage
)
```

And in `retryLast()` (line 132-136):

```swift
let text = try await transcriptionService.transcribe(
    audioFileURL: audioURL,
    apiKey: apiKey,
    model: appState.selectedModel,
    format: appState.selectedAudioFormat,
    language: appState.selectedLanguage
)
```

- [ ] **Step 6: Run all tests to verify they pass**

Run: `xcodebuild test -scheme GroqTalk -destination 'platform=macOS' 2>&1 | grep -E '(Executed|TEST)' | tail -3`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add GroqTalk/AppState.swift GroqTalk/MenuBarView.swift GroqTalk/GroqTalkApp.swift GroqTalkTests/LanguageTests.swift
git commit -m "feat: add language picker to menu with UserDefaults persistence"
```

---

### Task 4: History Popover View

**Files:**
- Create: `GroqTalk/HistoryPopoverView.swift`
- Modify: `GroqTalk/MenuBarView.swift` (replace history menu with popover trigger)
- Create: `GroqTalkTests/HistoryPopoverTests.swift`

- [ ] **Step 1: Write the failing tests for search filtering**

Create `GroqTalkTests/HistoryPopoverTests.swift`:

```swift
import XCTest
@testable import GroqTalk

@MainActor
final class HistoryPopoverTests: XCTestCase {
    private var testDir: URL!

    override func setUp() {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("groqtalk-popover-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
    }

    func testFilteredRecordsMatchesSearchText() {
        let history = TranscriptionHistory(storageDirectory: testDir)
        history.addSuccess(text: "hello world")
        history.addSuccess(text: "goodbye moon")
        history.addSuccess(text: "hello again")

        let filtered = history.records.filter { record in
            guard let text = record.text else { return false }
            return text.localizedCaseInsensitiveContains("hello")
        }
        XCTAssertEqual(filtered.count, 2)
    }

    func testFilteredRecordsEmptySearchReturnsAll() {
        let history = TranscriptionHistory(storageDirectory: testDir)
        history.addSuccess(text: "one")
        history.addSuccess(text: "two")

        let searchText = ""
        let filtered = history.records.filter { record in
            searchText.isEmpty || (record.text?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        XCTAssertEqual(filtered.count, 2)
    }

    func testFilteredRecordsExcludesFailures() {
        let history = TranscriptionHistory(storageDirectory: testDir)
        history.addSuccess(text: "hello world")
        history.addFailure(error: "timeout", audioFileURL: nil)

        let filtered = history.records.filter { record in
            guard let text = record.text else { return false }
            return text.localizedCaseInsensitiveContains("hello")
        }
        XCTAssertEqual(filtered.count, 1)
    }

    func testFilteredRecordsCaseInsensitive() {
        let history = TranscriptionHistory(storageDirectory: testDir)
        history.addSuccess(text: "Hello World")

        let filtered = history.records.filter { record in
            guard let text = record.text else { return false }
            return text.localizedCaseInsensitiveContains("hello")
        }
        XCTAssertEqual(filtered.count, 1)
    }
}
```

- [ ] **Step 2: Add test file to Xcode project and verify tests pass**

Add `GroqTalkTests/HistoryPopoverTests.swift` to the `GroqTalkTests` target in `project.pbxproj`.

Run: `xcodebuild test -scheme GroqTalk -destination 'platform=macOS' -only-testing:GroqTalkTests/HistoryPopoverTests 2>&1 | tail -5`
Expected: 4 tests pass (these test the filtering logic, not the view)

- [ ] **Step 3: Create HistoryPopoverView**

Create `GroqTalk/HistoryPopoverView.swift`:

```swift
import SwiftUI

struct HistoryPopoverView: View {
    var history: TranscriptionHistory
    var onRetry: ((TranscriptionRecord) -> Void)?
    @State private var searchText = ""

    private var filteredRecords: [TranscriptionRecord] {
        if searchText.isEmpty { return history.records }
        return history.records.filter { record in
            if let text = record.text {
                return text.localizedCaseInsensitiveContains(searchText)
            }
            if let error = record.error {
                return error.localizedCaseInsensitiveContains(searchText)
            }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if filteredRecords.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
        .frame(width: 350, height: 400)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search transcriptions...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text(searchText.isEmpty ? "No transcriptions yet" : "No matches")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var recordsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredRecords) { record in
                    recordRow(record)
                    Divider()
                }
            }
        }
    }

    private func recordRow(_ record: TranscriptionRecord) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if record.isFailure {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.text ?? record.error ?? "")
                    .lineLimit(2)
                    .font(.body)
                    .foregroundStyle(record.isFailure ? .red : .primary)
                Text(record.relativeTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let text = record.text {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }

            if record.isFailure, record.audioFileURL != nil {
                Button {
                    onRetry?(record)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Retry transcription")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 4: Add HistoryPopoverView to Xcode project**

Add `GroqTalk/HistoryPopoverView.swift` to the `GroqTalk` target in `project.pbxproj`.

- [ ] **Step 5: Replace inline history menu with popover in MenuBarView**

In `GroqTalk/MenuBarView.swift`, replace the `Menu("Recent Transcriptions")` block and the retry button (lines 90-122) with:

```swift
Button("Show History...") {
    // Popover is triggered via NSPopover in AppDelegate
    NotificationCenter.default.post(name: .showHistoryPopover, object: nil)
}

if history.retryableRecord != nil {
    Button("Retry Last") {
        onRetry?()
    }
}
```

Add at the bottom of the file, outside the struct:

```swift
extension Notification.Name {
    static let showHistoryPopover = Notification.Name("showHistoryPopover")
}
```

- [ ] **Step 6: Wire popover in GroqTalkApp's AppDelegate**

In `GroqTalk/GroqTalkApp.swift`, add popover state and wiring to `AppDelegate`.

Add properties after `private var transcribingTimer: Timer?` (after line 39):

```swift
private var historyPopover: NSPopover?
private var popoverObserver: Any?
```

Add a method after `startHotkeyMonitorWithRetry()`:

```swift
private func setupHistoryPopover() {
    popoverObserver = NotificationCenter.default.addObserver(
        forName: .showHistoryPopover, object: nil, queue: .main
    ) { [weak self] _ in
        self?.toggleHistoryPopover()
    }
}

private func toggleHistoryPopover() {
    if let popover = historyPopover, popover.isShown {
        popover.performClose(nil)
        return
    }

    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentViewController = NSHostingController(
        rootView: HistoryPopoverView(
            history: history,
            onRetry: { [weak self] record in
                self?.retryRecord(record)
            }
        )
    )

    // Find the menu bar button to anchor the popover
    if let button = NSApp.windows
        .compactMap({ $0.contentView?.subviews.first as? NSStatusBarButton })
        .first ?? NSStatusBar.system.statusItem(withLength: 0).button {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    self.historyPopover = popover
}

private func retryRecord(_ record: TranscriptionRecord) {
    guard let audioURL = record.audioFileURL else { return }
    historyPopover?.performClose(nil)

    appState.clearError()
    appState.setStatus(.transcribing)
    startTranscribingAnimation()

    Task {
        guard let apiKey = KeychainHelper.readApiKey() else {
            stopTranscribingAnimation()
            appState.showError("No API key")
            return
        }

        do {
            let text = try await transcriptionService.transcribe(
                audioFileURL: audioURL,
                apiKey: apiKey,
                model: appState.selectedModel,
                format: appState.selectedAudioFormat,
                language: appState.selectedLanguage
            )
            stopTranscribingAnimation()
            history.resolveRetry(id: record.id, text: text)
            await textInserter.insert(text: text, keepOnClipboard: appState.keepOnClipboard)
            appState.setStatus(.idle)
        } catch {
            stopTranscribingAnimation()
            let errorMsg = errorMessage(from: error)
            history.resolveRetryFailure(id: record.id, error: errorMsg)
            appState.showError(errorMsg)
        }
    }
}
```

Add `setupHistoryPopover()` call in `applicationDidFinishLaunching` (after line 64):

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    wireHotkeyMonitor()
    applyHotkeyConfig()
    startHotkeyMonitorWithRetry()
    setupHistoryPopover()
}
```

- [ ] **Step 7: Run all tests to verify they pass**

Run: `xcodebuild test -scheme GroqTalk -destination 'platform=macOS' 2>&1 | grep -E '(Executed|TEST)' | tail -3`
Expected: All tests pass

- [ ] **Step 8: Build and verify the app launches**

Run: `xcodebuild build -scheme GroqTalk -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add GroqTalk/HistoryPopoverView.swift GroqTalk/MenuBarView.swift GroqTalk/GroqTalkApp.swift GroqTalkTests/HistoryPopoverTests.swift GroqTalk.xcodeproj/project.pbxproj
git commit -m "feat: add history popover with search, copy, and retry"
```

---

### Task 5: Add language to AppState tearDown and integration tests

**Files:**
- Modify: `GroqTalkTests/AppStateTests.swift` (add `language` to tearDown)
- Modify: `GroqTalkTests/IntegrationTests.swift` (add language parameter test)

- [ ] **Step 1: Add language cleanup to AppStateTests tearDown**

In `GroqTalkTests/AppStateTests.swift`, add to `tearDown()` (after line 10):

```swift
UserDefaults.standard.removeObject(forKey: "language")
```

- [ ] **Step 2: Add integration test for language parameter**

Add to `GroqTalkTests/IntegrationTests.swift`, after `testMultipartBodyMatchesEncodedFile`:

```swift
func testMultipartBodyIncludesLanguageField() throws {
    let buffer = makeSineBuffer()
    let url = track(try recorder.writeWAV(buffers: [buffer]))

    let service = TranscriptionService()
    let body = try service.buildMultipartBody(
        audioFileURL: url, model: "whisper-large-v3-turbo",
        format: .wav, language: .es, boundary: "test-boundary"
    )
    let bodyString = String(data: body, encoding: .isoLatin1)!

    XCTAssertTrue(
        bodyString.contains("name=\"language\"\r\n\r\nes"),
        "Spanish language hint should be in multipart body"
    )
}

func testMultipartBodyOmitsLanguageForAuto() throws {
    let buffer = makeSineBuffer()
    let url = track(try recorder.writeWAV(buffers: [buffer]))

    let service = TranscriptionService()
    let body = try service.buildMultipartBody(
        audioFileURL: url, model: "whisper-large-v3-turbo",
        format: .wav, language: .auto, boundary: "test-boundary"
    )
    let bodyString = String(data: body, encoding: .isoLatin1)!

    XCTAssertFalse(
        bodyString.contains("name=\"language\""),
        "Auto-detect should not include language field"
    )
}
```

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -scheme GroqTalk -destination 'platform=macOS' 2>&1 | grep -E '(Executed|TEST)' | tail -3`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add GroqTalkTests/AppStateTests.swift GroqTalkTests/IntegrationTests.swift
git commit -m "test: add language parameter tests to integration and AppState suites"
```

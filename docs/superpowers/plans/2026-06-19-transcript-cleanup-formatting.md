# Transcript Cleanup Formatting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement optional transcript cleanup formatting so Foil can send completed speech-to-text transcripts through an independently configured cleanup LLM provider, paste the cleaned result, and fall back to the raw transcript with a warning if cleanup fails.

**Architecture:** Keep cleanup in the existing post-STT path. `TranscriptionController` decides whether cleanup runs and preserves raw fallback behavior. A small request/prompt helper owns prompt resolution, preferred-term context, and return-only instructions. `TranscriptionService` owns chat request encoding and response/error handling. `AppState` owns persisted cleanup preferences. `SettingsView` exposes a deliberate v1 cleanup-formatting surface while keeping `rewriteClearly` in the model for compatibility.

**Tech Stack:** Swift, SwiftUI, XCTest, XCUITest, UserDefaults, Keychain Services, URLRequest/URLSession.

---

## File Structure

- Modify `Foil/TranscriptProcessingMode.swift`: add cleanup-formatting copy/default prompt helpers while keeping raw and rewrite compatibility.
- Modify `Foil/TranscriptionService.swift`: add cleanup request/prompt builder and encode preferred terms in chat-completion request bodies.
- Modify `Foil/AppState.swift`: persist per-mode custom prompts and preferred terms, add reset helpers, and keep cleanup provider selection independent from STT provider selection.
- Modify `Foil/TranscriptionController.swift`: pass cleanup request configuration into `TranscriptionService`, preserve raw fallback, and resolve cleanup provider API keys independently.
- Modify `Foil/SettingsView.swift`: expose cleanup-formatting toggle/controls, prompt editor/reset, preferred terms editor, independent cleanup provider controls, and explicit routing copy.
- Modify `Foil/DiagnosticLog.swift`: include safe cleanup routing metadata and prove custom prompts, preferred terms, transcripts, and secrets are omitted or redacted.
- Modify `Foil/FoilApp.swift`: keep final-text-only history and visible cleanup fallback warning behavior aligned with the new cleanup path.
- Modify `Foil/UITestingController.swift`: add UI-test seed/command support for cleanup settings if direct XCUITest interaction is not stable enough.
- Modify `FoilTests/TranscriptionServiceTests.swift`: cover prompt/default/custom/preferred-term request assembly and cleanup request encoding.
- Modify `FoilTests/AppStateTests.swift`: cover persistence, reset, preferred-term normalization, and provider independence.
- Modify `FoilTests/TranscriptionControllerTests.swift`: cover cleanup-off no-request, independent routing, cleanup key resolution, and raw fallback.
- Modify `FoilTests/DiagnosticLogTests.swift`: cover diagnostic omission/redaction for sensitive cleanup content.
- Modify `FoilTests/TranscriptionHistoryTests.swift`: cover final-text-only history behavior if a history-facing helper changes.
- Modify `FoilUITests/FoilUITests.swift`: cover cleanup settings controls hidden/off and visible/on.

---

### Task 1: Add Cleanup Prompt Model And AppState Persistence

**Files:**
- Modify: `Foil/TranscriptProcessingMode.swift`
- Modify: `Foil/TranscriptionService.swift`
- Modify: `Foil/AppState.swift`
- Test: `FoilTests/TranscriptionServiceTests.swift`
- Test: `FoilTests/AppStateTests.swift`

- [ ] **Step 1: Write failing service tests for prompt assembly**

Add tests near the existing transcript-processing tests in `FoilTests/TranscriptionServiceTests.swift`:

```swift
func testCleanupFormattingRequestUsesDefaultPromptPreferredTermsAndReturnOnlyInstruction() throws {
    let request = TranscriptCleanupRequest(
        rawTranscript: "first item supa base second item",
        mode: .cleanUp,
        customPrompt: nil,
        preferredTerms: ["Supabase", "Vercel"],
        provider: .customOpenAICompatibleChat(
            baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
            model: "qwen2.5:7b"
        )
    )

    let body = try TranscriptionService.buildTranscriptProcessingBody(request: request)
    let bodyString = String(data: body, encoding: .utf8)!

    XCTAssertTrue(bodyString.contains(#""model":"qwen2.5:7b""#), bodyString)
    XCTAssertTrue(bodyString.contains("Add punctuation and capitalization"), bodyString)
    XCTAssertTrue(bodyString.contains("Preferred terms"), bodyString)
    XCTAssertTrue(bodyString.contains("Supabase"), bodyString)
    XCTAssertTrue(bodyString.contains("Vercel"), bodyString)
    XCTAssertTrue(bodyString.contains("Return only the final processed transcript"), bodyString)
    XCTAssertTrue(bodyString.contains("first item supa base second item"), bodyString)
}

func testCleanupFormattingRequestUsesCustomPromptForMode() throws {
    let request = TranscriptCleanupRequest(
        rawTranscript: "raw words",
        mode: .cleanUp,
        customPrompt: "Use short paragraphs and preserve product names.",
        preferredTerms: [],
        provider: .groq(model: "llama-3.3-70b-versatile")
    )

    let body = try TranscriptionService.buildTranscriptProcessingBody(request: request)
    let bodyString = String(data: body, encoding: .utf8)!

    XCTAssertTrue(bodyString.contains("Use short paragraphs and preserve product names."), bodyString)
    XCTAssertFalse(bodyString.contains("Preferred terms"), bodyString)
    XCTAssertTrue(bodyString.contains("Return only the final processed transcript"), bodyString)
}
```

- [ ] **Step 2: Write failing AppState tests for prompt and terms persistence**

Add tests near the cleanup AppState tests in `FoilTests/AppStateTests.swift`:

```swift
func testCleanupPromptDefaultsAndReset() {
    let state = AppState()

    XCTAssertEqual(state.customPrompt(for: .cleanUp), nil)
    XCTAssertEqual(state.resolvedPrompt(for: .cleanUp), TranscriptProcessingMode.cleanUp.defaultPrompt)

    state.setCustomPrompt("Custom cleanup instructions", for: .cleanUp)
    XCTAssertEqual(state.customPrompt(for: .cleanUp), "Custom cleanup instructions")
    XCTAssertEqual(state.resolvedPrompt(for: .cleanUp), "Custom cleanup instructions")

    state.resetCustomPrompt(for: .cleanUp)
    XCTAssertEqual(state.customPrompt(for: .cleanUp), nil)
    XCTAssertEqual(state.resolvedPrompt(for: .cleanUp), TranscriptProcessingMode.cleanUp.defaultPrompt)
}

func testPreferredTermsNormalizePersistAndReload() {
    let state = AppState()
    state.preferredTermsText = " Supabase \n\nVercel\nSupabase "

    XCTAssertEqual(state.preferredTerms, ["Supabase", "Vercel"])

    let reloaded = AppState()
    XCTAssertEqual(reloaded.preferredTerms, ["Supabase", "Vercel"])
    XCTAssertEqual(reloaded.preferredTermsText, "Supabase\nVercel")
}
```

- [ ] **Step 3: Run focused tests and verify failure**

Run:

```sh
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionServiceTests/testCleanupFormattingRequestUsesDefaultPromptPreferredTermsAndReturnOnlyInstruction -only-testing:FoilTests/TranscriptionServiceTests/testCleanupFormattingRequestUsesCustomPromptForMode -only-testing:FoilTests/AppStateTests/testCleanupPromptDefaultsAndReset -only-testing:FoilTests/AppStateTests/testPreferredTermsNormalizePersistAndReload
```

Expected: FAIL because `TranscriptCleanupRequest`, prompt helpers, and preferred-term AppState APIs do not exist.

- [ ] **Step 4: Add prompt defaults to `TranscriptProcessingMode`**

In `Foil/TranscriptProcessingMode.swift`, replace `promptInstruction` with a compatibility wrapper over a clearer default prompt:

```swift
var displayName: String {
    switch self {
    case .raw:
        "Raw transcript"
    case .cleanUp:
        "Clean up transcript formatting"
    case .rewriteClearly:
        "Rewrite clearly"
    }
}

var defaultPrompt: String {
    switch self {
    case .raw:
        ""
    case .cleanUp:
        """
        Clean up transcript formatting while preserving the speaker's meaning, facts, voice, and intent.
        Add punctuation and capitalization.
        Add paragraph breaks where they improve readability.
        Turn clearly enumerated spoken points into numbered or bulleted lists.
        Remove obvious filler and false starts only when doing so does not change meaning.
        Preserve names, numbers, technical terms, code-like strings, URLs, and intent.
        """
    case .rewriteClearly:
        "Rewrite the transcript into clear, concise prose. Preserve all concrete facts, names, numbers, and intent. Do not add new information."
    }
}

var promptInstruction: String {
    defaultPrompt + "\nReturn only the final processed transcript."
}
```

- [ ] **Step 5: Add cleanup request builder**

In `Foil/TranscriptionService.swift`, add a small request value near the cleanup provider types:

```swift
struct TranscriptCleanupRequest: Equatable {
    let rawTranscript: String
    let mode: TranscriptProcessingMode
    let customPrompt: String?
    let preferredTerms: [String]
    let provider: TranscriptCleanupProvider

    var resolvedPrompt: String {
        let trimmed = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? mode.defaultPrompt : trimmed
    }

    var systemInstruction: String {
        var parts = [resolvedPrompt]
        if !preferredTerms.isEmpty {
            parts.append("Preferred terms to preserve or prefer when appropriate:\n" + preferredTerms.map { "- \($0)" }.joined(separator: "\n"))
        }
        parts.append("Return only the final processed transcript.")
        return parts.joined(separator: "\n\n")
    }
}
```

Add a static helper while keeping the existing instance helper as a compatibility wrapper:

```swift
static func buildTranscriptProcessingBody(request cleanupRequest: TranscriptCleanupRequest) throws -> Data {
    let request = ChatCompletionRequest(
        model: cleanupRequest.provider.model,
        messages: [
            .init(role: "system", content: cleanupRequest.systemInstruction),
            .init(role: "user", content: cleanupRequest.rawTranscript)
        ],
        temperature: 0.2,
        maxCompletionTokens: 1024
    )
    return try JSONEncoder().encode(request)
}
```

- [ ] **Step 6: Add AppState prompt and preferred-term persistence**

In `Foil/AppState.swift`, add stored preferences near existing cleanup preferences:

```swift
var customCleanupPrompt: String = "" {
    didSet { Self.defaults.set(customCleanupPrompt, forKey: "customCleanupPrompt.cleanUp") }
}

var customRewritePrompt: String = "" {
    didSet { Self.defaults.set(customRewritePrompt, forKey: "customCleanupPrompt.rewriteClearly") }
}

var preferredTermsText: String = "" {
    didSet {
        let normalized = Self.normalizedPreferredTerms(from: preferredTermsText).joined(separator: "\n")
        if preferredTermsText != normalized {
            preferredTermsText = normalized
            return
        }
        Self.defaults.set(preferredTermsText, forKey: "transcriptCleanupPreferredTerms")
    }
}
```

Add helpers:

```swift
var preferredTerms: [String] {
    Self.normalizedPreferredTerms(from: preferredTermsText)
}

func customPrompt(for mode: TranscriptProcessingMode) -> String? {
    let value: String
    switch mode {
    case .raw:
        return nil
    case .cleanUp:
        value = customCleanupPrompt
    case .rewriteClearly:
        value = customRewritePrompt
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func resolvedPrompt(for mode: TranscriptProcessingMode) -> String {
    customPrompt(for: mode) ?? mode.defaultPrompt
}

func setCustomPrompt(_ prompt: String, for mode: TranscriptProcessingMode) {
    switch mode {
    case .raw:
        return
    case .cleanUp:
        customCleanupPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    case .rewriteClearly:
        customRewritePrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func resetCustomPrompt(for mode: TranscriptProcessingMode) {
    setCustomPrompt("", for: mode)
}

private static func normalizedPreferredTerms(from text: String) -> [String] {
    var seen = Set<String>()
    return text
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter { term in
            let key = term.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
}
```

Register, reset, and load the new keys in the same AppState sections that handle `transcriptProcessingMode`, `transcriptCleanupModel`, and `customTranscriptCleanupModel`.

- [ ] **Step 7: Run focused tests and verify pass**

Run the command from Step 3 again.

Expected: PASS.

---

### Task 2: Wire Cleanup Request Through Controller And Service

**Files:**
- Modify: `Foil/TranscriptionController.swift`
- Modify: `Foil/TranscriptionService.swift`
- Modify: `Foil/AppState.swift`
- Modify: `Foil/SettingsView.swift`
- Test: `FoilTests/TranscriptionControllerTests.swift`
- Test: `FoilTests/TranscriptionServiceTests.swift`
- Test: `FoilTests/AppStateTests.swift`

- [ ] **Step 1: Write failing cleanup-off and routing/key tests**

Add to `FoilTests/TranscriptionControllerTests.swift`:

```swift
func testCleanupOffDoesNotSendCleanupRequest() async {
    appState.transcriptProcessingMode = .raw
    let transport = ControllerStubTransport { request in
        XCTFail("Unexpected cleanup request to \(request.url?.absoluteString ?? "<nil>")")
        throw URLError(.badURL)
    }

    let result = await controller.processTranscriptOrRaw(
        rawText: "raw text",
        apiKey: nil,
        service: TranscriptionService(transport: transport),
        context: "test"
    )

    XCTAssertEqual(result.text, "raw text")
    XCTAssertFalse(result.cleanupFailed)
    XCTAssertEqual(transport.requests.count, 0)
}

func testGroqCleanupUsesGroqKeyEvenWhenTranscriptionProviderIsOpenAI() async throws {
    appState.selectedTranscriptionProviderPresetID = .openAIWhisper
    appState.transcriptProcessingMode = .cleanUp
    appState.transcriptCleanupProviderID = .groq
    try KeychainHelper.save(apiKey: "groq-cleanup-key", for: .groq)

    let transport = ControllerStubTransport { request in
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer groq-cleanup-key")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(#"{"choices":[{"message":{"content":"clean text"}}]}"#.utf8), response)
    }

    let result = await controller.processTranscriptOrRaw(
        rawText: "raw text",
        apiKey: "openai-stt-key",
        service: TranscriptionService(transport: transport),
        context: "test"
    )

    XCTAssertEqual(result.text, "clean text")
    XCTAssertFalse(result.cleanupFailed)
}

func testCleanupRequestIncludesCustomPromptAndPreferredTermsFromAppState() async {
    appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
    appState.transcriptProcessingMode = .cleanUp
    appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
    appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
    appState.customTranscriptCleanupModel = "qwen2.5:7b"
    appState.setCustomPrompt("Preserve the speaker style.", for: .cleanUp)
    appState.preferredTermsText = "Supabase\nVercel"

    let transport = ControllerStubTransport { request in
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("Preserve the speaker style."), body)
        XCTAssertTrue(body.contains("Supabase"), body)
        XCTAssertTrue(body.contains("Vercel"), body)
        XCTAssertTrue(body.contains("Return only the final processed transcript"), body)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(#"{"choices":[{"message":{"content":"clean text"}}]}"#.utf8), response)
    }

    let result = await controller.processTranscriptOrRaw(
        rawText: "raw text",
        apiKey: nil,
        service: TranscriptionService(transport: transport),
        context: "test"
    )

    XCTAssertEqual(result.text, "clean text")
    XCTAssertFalse(result.cleanupFailed)
}
```

- [ ] **Step 2: Run routing tests and verify failure**

Run:

```sh
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionControllerTests/testCleanupOffDoesNotSendCleanupRequest -only-testing:FoilTests/TranscriptionControllerTests/testGroqCleanupUsesGroqKeyEvenWhenTranscriptionProviderIsOpenAI -only-testing:FoilTests/TranscriptionControllerTests/testCleanupRequestIncludesCustomPromptAndPreferredTermsFromAppState
```

Expected: FAIL for the new cleanup-request context and Groq cleanup key assertions. The cleanup-off no-request test should PASS immediately if the existing raw-mode guard remains intact; keep it in the suite to protect the opt-in trust boundary.

- [ ] **Step 3: Update service processing entry point**

In `Foil/TranscriptionService.swift`, change the cleanup-provider overload to accept a request:

```swift
func processTranscript(
    request cleanupRequest: TranscriptCleanupRequest,
    apiKey: String?
) async throws -> String
```

Inside it, use `cleanupRequest.provider.chatCompletionsEndpoint`, call `Self.buildTranscriptProcessingBody(request:)`, and log only provider id, mode, model, input length, response status, response bytes, output length, and mapped error category. Keep the old overload as a wrapper if needed by existing tests:

```swift
func processTranscript(
    _ transcript: String,
    apiKey: String?,
    mode: TranscriptProcessingMode,
    provider cleanupProvider: TranscriptCleanupProvider
) async throws -> String {
    try await processTranscript(
        request: TranscriptCleanupRequest(
            rawTranscript: transcript,
            mode: mode,
            customPrompt: nil,
            preferredTerms: [],
            provider: cleanupProvider
        ),
        apiKey: apiKey
    )
}
```

- [ ] **Step 4: Update controller request construction and key resolution**

In `Foil/TranscriptionController.swift`, build `TranscriptCleanupRequest` inside `processTranscriptOrRaw`:

```swift
let cleanupRequest = TranscriptCleanupRequest(
    rawTranscript: rawText,
    mode: processingMode,
    customPrompt: appState.customPrompt(for: processingMode),
    preferredTerms: appState.preferredTerms,
    provider: cleanupProvider
)
```

Resolve keys by cleanup provider, not by STT provider:

```swift
switch cleanupProvider.id {
case .none:
    cleanupApiKey = nil
case .groq:
    cleanupApiKey = KeychainHelper.readApiKey(for: .groq)
case .customOpenAICompatibleChat:
    cleanupApiKey = KeychainHelper.readCleanupApiKey(for: .customOpenAICompatibleChat)
}
```

Then call:

```swift
let text = try await service.processTranscript(request: cleanupRequest, apiKey: cleanupApiKey)
```

- [ ] **Step 5: Allow explicit Groq cleanup selection outside Groq STT**

In `Foil/SettingsView.swift` and `Foil/AppState.swift`, keep cleanup provider state independent. Do not force `transcriptCleanupProviderID = .none` when the STT provider changes away from Groq. Update `availableCleanupProviderIDs` to include `.groq`, `.none`, and `.customOpenAICompatibleChat` for every STT preset. The routing copy must make cloud cleanup explicit when STT is local or custom.

- [ ] **Step 6: Run focused tests and verify pass**

Run:

```sh
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionControllerTests
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionServiceTests
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/AppStateTests
```

Expected: PASS.

---

### Task 3: Build The Settings Cleanup Formatting UI

**Files:**
- Modify: `Foil/SettingsView.swift`
- Modify: `Foil/AppState.swift`
- Modify: `Foil/UITestingController.swift`
- Test: `FoilUITests/FoilUITests.swift`
- Test: `FoilTests/AppStateTests.swift`

- [ ] **Step 1: Write failing UI coverage**

Add a focused test to `FoilUITests/FoilUITests.swift`:

```swift
func testTranscriptCleanupFormattingSettingsAreHiddenUntilEnabled() {
    relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-transcription"])
    openSettingsPanel()

    XCTAssertTrue(elementExists(id: "settings.cleanupFormattingToggle", timeout: 4), app.debugDescription)
    XCTAssertFalse(elementExists(id: "settings.cleanupProviderPicker", timeout: 1), app.debugDescription)
    XCTAssertFalse(elementExists(id: "settings.cleanupPromptEditor", timeout: 1), app.debugDescription)
    XCTAssertFalse(elementExists(id: "settings.preferredTermsEditor", timeout: 1), app.debugDescription)

    postUITestCommand(appCommandNotification, userInfo: ["command": "enableCleanupFormatting"])

    XCTAssertTrue(elementExists(id: "settings.cleanupProviderPicker", timeout: 4), app.debugDescription)
    XCTAssertTrue(elementExists(id: "settings.cleanupPromptEditor", timeout: 4), app.debugDescription)
    XCTAssertTrue(elementExists(id: "settings.resetCleanupPromptButton", timeout: 4), app.debugDescription)
    XCTAssertTrue(elementExists(id: "settings.preferredTermsEditor", timeout: 4), app.debugDescription)
    XCTAssertTrue(staticTextLabelOrValueContaining("transcript text is sent to the cleanup provider").waitForExistence(timeout: 2), app.debugDescription)
}
```

- [ ] **Step 2: Run the UI test and verify failure**

Run:

```sh
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:FoilUITests/FoilUITests/testTranscriptCleanupFormattingSettingsAreHiddenUntilEnabled
```

Expected: FAIL because the toggle, prompt editor, reset button, preferred terms editor, and UI-test command are missing.

- [ ] **Step 3: Add a cleanup enabled binding**

In `Foil/SettingsView.swift`, replace the broad `Picker("After transcription"...` UI with a toggle bound to `.raw` versus `.cleanUp`:

```swift
private var cleanupFormattingEnabled: Binding<Bool> {
    Binding(
        get: { appState.transcriptProcessingMode != .raw },
        set: { enabled in
            appState.transcriptProcessingMode = enabled ? .cleanUp : .raw
        }
    )
}
```

Use it in `Section("Transcript cleanup")`:

```swift
Toggle("Clean up transcript formatting", isOn: cleanupFormattingEnabled)
    .accessibilityIdentifier("settings.cleanupFormattingToggle")

Text("Cleanup is off unless enabled. When enabled, transcript text is sent to the cleanup provider selected below; audio still follows the transcription provider above.")
    .font(.caption)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityIdentifier("settings.cleanupRoutingSummary")

if cleanupFormattingEnabled.wrappedValue {
    cleanupProviderSettings
    cleanupPromptSettings
}
```

- [ ] **Step 4: Add prompt and preferred-term controls**

Add `cleanupPromptSettings` in `Foil/SettingsView.swift`:

```swift
private var cleanupPromptBinding: Binding<String> {
    Binding(
        get: { appState.resolvedPrompt(for: .cleanUp) },
        set: { appState.setCustomPrompt($0, for: .cleanUp) }
    )
}

private var cleanupPromptSettings: some View {
    Section("Cleanup instructions") {
        TextEditor(text: cleanupPromptBinding)
            .font(.body)
            .frame(minHeight: 90)
            .accessibilityIdentifier("settings.cleanupPromptEditor")

        Button("Reset prompt") {
            appState.resetCustomPrompt(for: .cleanUp)
        }
        .accessibilityIdentifier("settings.resetCleanupPromptButton")

        TextEditor(text: $appState.preferredTermsText)
            .font(.body)
            .frame(minHeight: 70)
            .accessibilityIdentifier("settings.preferredTermsEditor")

        Text("Add one preferred term per line. Foil sends these as context to the cleanup provider and does not perform automatic replacement.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("settings.preferredTermsHelp")
    }
}
```

- [ ] **Step 5: Keep provider controls and routing copy explicit**

Update `cleanupProviderSettings` copy:

```swift
Text("The transcription provider controls where audio goes. The cleanup provider controls where transcript text goes. Local transcription does not imply local cleanup unless the cleanup provider is local too.")
    .font(.caption)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityIdentifier("settings.cleanupRoutingHelp")
```

Keep provider-specific model/base URL/key/test controls visible only when cleanup is enabled.

- [ ] **Step 6: Add UI-test command support if direct toggle is unreliable**

In `Foil/UITestingController.swift`, handle `enableCleanupFormatting` in the existing app command switch:

```swift
case "enableCleanupFormatting":
    appState.transcriptProcessingMode = .cleanUp
    appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
```

Use this only as a test control path; production UI still needs the real toggle.

- [ ] **Step 7: Run focused UI and AppState tests**

Run:

```sh
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/AppStateTests
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:FoilUITests/FoilUITests/testTranscriptCleanupFormattingSettingsAreHiddenUntilEnabled
```

Expected: PASS.

---

### Task 4: Prove Privacy, Diagnostics, Fallback Warning, And Final History Text

**Files:**
- Modify: `Foil/DiagnosticLog.swift`
- Modify: `Foil/FoilApp.swift`
- Modify: `Foil/TranscriptionHistory.swift`
- Test: `FoilTests/DiagnosticLogTests.swift`
- Test: `FoilTests/TranscriptionHistoryTests.swift`
- Test: `FoilTests/TranscriptionControllerTests.swift`
- Test: `FoilUITests/FoilUITests.swift`

- [ ] **Step 1: Add failing diagnostic omission tests**

Add to `FoilTests/DiagnosticLogTests.swift`:

```swift
@MainActor
func testDiagnosticsDoNotIncludeCleanupPromptPreferredTermsOrTranscriptText() {
    let appState = AppState()
    appState.transcriptProcessingMode = .cleanUp
    appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
    appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
    appState.customTranscriptCleanupModel = "qwen2.5:7b"
    appState.setCustomPrompt("SECRET PROMPT SENTINEL", for: .cleanUp)
    appState.preferredTermsText = "SECRET TERM SENTINEL"

    DiagnosticLog.write("processTranscript: sending cleanupProvider=custom-openai-compatible-chat mode=cleanUp model=qwen2.5:7b inputLength=29")

    let export = DiagnosticLog.exportText(appState: appState, recentLineLimit: 20)
    let setup = DiagnosticLog.setupReportText(appState: appState, recentLineLimit: 20)
    let combined = export + "\n" + setup

    XCTAssertTrue(combined.contains("Transcript Processing: cleanUp"))
    XCTAssertTrue(combined.contains("Cleanup Model: qwen2.5:7b"))
    XCTAssertFalse(combined.contains("SECRET PROMPT SENTINEL"))
    XCTAssertFalse(combined.contains("SECRET TERM SENTINEL"))
    XCTAssertFalse(combined.contains("raw transcript sentinel"))
    XCTAssertFalse(combined.contains("cleaned transcript sentinel"))
}
```

- [ ] **Step 2: Add final-text-only history tests**

Add tests that document the single-final-text history boundary in `FoilTests/TranscriptionHistoryTests.swift`:

```swift
func testCleanupSuccessStoresOnlyFinalCleanedText() throws {
    history.addSuccess(text: "Cleaned final text")

    XCTAssertEqual(history.records.first?.text, "Cleaned final text")
    let json = try history.exportJSON()
    XCTAssertFalse(json.contains("Raw transcript before cleanup"))
}

func testCleanupFallbackStoresOnlyRawFinalText() throws {
    history.addSuccess(text: "Raw fallback text")

    XCTAssertEqual(history.records.first?.text, "Raw fallback text")
    let json = try history.exportJSON()
    XCTAssertFalse(json.contains("Failed cleaned text"))
}
```

- [ ] **Step 3: Add fallback warning proof**

In `FoilTests/TranscriptionControllerTests.swift`, keep or extend `testCustomChatCleanupFailureFallsBackToRaw` so it asserts both the raw text and cleanup-fallback flag:

```swift
XCTAssertEqual(result.text, "raw survives")
XCTAssertTrue(result.cleanupFailed)
```

In `Foil/UITestingController.swift`, add an app command that seeds the production warning copy without performing a live transcription:

```swift
case "seedCleanupFallbackWarning":
    appState.feedbackMessage = "Cleanup failed; pasted raw transcript."
    appState.floatingStatusTransientVisible = true
    appState.setStatus(.idle)
```

In `FoilUITests/FoilUITests.swift`, add a focused warning visibility test:

```swift
func testCleanupFallbackWarningIsVisible() {
    relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-floating-status-enabled"])
    postUITestCommand(appCommandNotification, userInfo: ["command": "seedCleanupFallbackWarning"])

    XCTAssertTrue(staticTextLabelOrValueContaining("Cleanup failed; pasted raw transcript.").waitForExistence(timeout: 2), app.debugDescription)
}
```

Update `Foil/FoilApp.swift` to use the same product copy in both retry and normal transcription paths when `cleanupFailed` is true.

- [ ] **Step 4: Keep diagnostics operational and content-safe**

In `Foil/DiagnosticLog.swift`, include only safe cleanup metadata:

- processing mode
- cleanup provider id/display name
- cleanup model
- input/output lengths
- cleanup fallback flag
- HTTP status or mapped error category

Do not add custom prompt, preferred terms, raw transcript text, or cleaned transcript text to export or setup report summaries.

- [ ] **Step 5: Run focused privacy/history/fallback tests**

Run:

```sh
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/DiagnosticLogTests
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionHistoryTests
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionControllerTests
```

Expected: PASS.

---

### Task 5: Final Verification And Spec Audit

**Files:**
- Modify: `docs/goals/transcript-cleanup-formatting-handoff/state.yaml`
- Read: `docs/superpowers/specs/2026-06-19-transcript-cleanup-formatting-design.md`
- Read: `docs/superpowers/plans/2026-06-19-transcript-cleanup-formatting.md`

- [ ] **Step 1: Run the targeted unit bundle**

Run:

```sh
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionControllerTests -only-testing:FoilTests/TranscriptionServiceTests -only-testing:FoilTests/AppStateTests -only-testing:FoilTests/DiagnosticLogTests -only-testing:FoilTests/TranscriptionHistoryTests
```

Expected: PASS.

- [ ] **Step 2: Run the targeted UI bundle**

Run:

```sh
xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO -only-testing:FoilUITests/FoilUITests/testTranscriptCleanupFormattingSettingsAreHiddenUntilEnabled
```

Expected: PASS. If the broader `FoilUITests/FoilUITests` row is required by the board's final audit, run that after the focused row is stable.

- [ ] **Step 3: Run diff hygiene**

Run:

```sh
git diff --check
git diff --stat
```

Expected: `git diff --check` exits 0 and `git diff --stat` contains only intended implementation, tests, and goal/plan files.

- [ ] **Step 4: Audit against the approved spec**

Create the final T008 receipt only after evidence proves:

- cleanup is off by default and sends no cleanup request
- cleanup provider routing is independent from STT provider routing
- cleanup prompt assembly includes default/custom prompt, preferred terms, and return-only instruction
- prompt reset restores the default cleanup-formatting prompt
- cleanup failure falls back to raw transcript and reports `cleanupFailed`
- history stores only the final pasted text
- diagnostics omit transcripts, cleaned text, custom prompt text, preferred terms, API keys, and bearer tokens
- Settings shows cleanup provider, prompt editor, reset, and preferred terms only when cleanup is enabled

Expected: The final receipt names the strongest realistic failure mode, the command or inspection that rules it out, and any residual risk.

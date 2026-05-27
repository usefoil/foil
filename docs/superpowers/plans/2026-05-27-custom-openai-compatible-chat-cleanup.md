# Custom OpenAI-Compatible Chat Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit Custom OpenAI-compatible chat cleanup so cleanup/rewrite can run through a user-configured chat endpoint without silently routing local/custom transcripts to Groq.

**Architecture:** Keep transcription provider selection unchanged. Add a cleanup-only provider model, scoped cleanup credential storage, and a cleanup service path used only by `TranscriptionController.processTranscriptOrRaw`. Settings exposes custom chat cleanup only when cleanup/rewrite is enabled.

**Tech Stack:** Swift, SwiftUI, XCTest, URLSession/URLRequest, Keychain Services, UserDefaults.

---

## File Structure

- Modify `Foil/TranscriptionService.swift`: add cleanup provider types and chat-only cleanup service helpers.
- Modify `Foil/AppState.swift`: persist cleanup provider settings, derive effective cleanup routing, and add custom cleanup connection test state.
- Modify `Foil/KeychainHelper.swift`: add scoped cleanup API key account support separate from transcription provider keys.
- Modify `Foil/TranscriptionController.swift`: resolve cleanup provider separately from transcription provider.
- Modify `Foil/SettingsView.swift`: expose cleanup provider picker, custom chat fields, and connection test/status copy.
- Modify `Foil/DiagnosticLog.swift`: include redacted cleanup routing/configuration in setup reports.
- Modify `FoilTests/TranscriptionServiceTests.swift`: cover cleanup provider endpoints and request body.
- Modify `FoilTests/TranscriptionControllerTests.swift`: cover routing and fallback behavior.
- Modify `FoilTests/DiagnosticLogTests.swift`: cover redacted cleanup config.
- Modify UI tests if existing settings tests assert cleanup copy.
- Modify `README.md`: document cleanup routing and troubleshooting.

## Task 1: Cleanup Provider Model And Defaults

**Files:**
- Modify: `Foil/TranscriptionService.swift`
- Modify: `Foil/AppState.swift`
- Test: `FoilTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Write failing provider model tests**

Add tests near the existing provider tests in `FoilTests/TranscriptionServiceTests.swift`:

```swift
func testCustomChatCleanupProviderBuildsExpectedEndpoints() {
    let provider = TranscriptCleanupProvider.customOpenAICompatibleChat(
        baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
        model: "llama3.1:8b"
    )

    XCTAssertEqual(provider.id, .customOpenAICompatibleChat)
    XCTAssertEqual(provider.displayName, "Custom OpenAI-compatible chat")
    XCTAssertEqual(provider.chatCompletionsEndpoint?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
    XCTAssertEqual(provider.modelsEndpoint?.absoluteString, "http://127.0.0.1:11434/v1/models")
    XCTAssertEqual(provider.model, "llama3.1:8b")
    XCTAssertFalse(provider.requiresAPIKey)
}

func testNoCleanupProviderHasNoEndpoints() {
    let provider = TranscriptCleanupProvider.none

    XCTAssertEqual(provider.id, .none)
    XCTAssertEqual(provider.displayName, "None")
    XCTAssertNil(provider.chatCompletionsEndpoint)
    XCTAssertNil(provider.modelsEndpoint)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```sh
xcodebuild test -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionServiceTests/testCustomChatCleanupProviderBuildsExpectedEndpoints -only-testing:FoilTests/TranscriptionServiceTests/testNoCleanupProviderHasNoEndpoints
```

Expected: FAIL because `TranscriptCleanupProvider` is not defined.

- [ ] **Step 3: Add cleanup provider types**

Add this in `Foil/TranscriptionService.swift` after `TranscriptionProvider`:

```swift
enum TranscriptCleanupProviderID: String, CaseIterable, Identifiable {
    case none
    case groq
    case customOpenAICompatibleChat = "custom-openai-compatible-chat"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            "None"
        case .groq:
            "Groq"
        case .customOpenAICompatibleChat:
            "Custom OpenAI-compatible chat"
        }
    }
}

struct TranscriptCleanupProvider: Equatable {
    let id: TranscriptCleanupProviderID
    let displayName: String
    let baseURL: URL?
    let model: String
    let requiresAPIKey: Bool

    static let none = TranscriptCleanupProvider(
        id: .none,
        displayName: "None",
        baseURL: nil,
        model: "",
        requiresAPIKey: false
    )

    static func groq(model: String) -> TranscriptCleanupProvider {
        TranscriptCleanupProvider(
            id: .groq,
            displayName: "Groq",
            baseURL: URL(string: "https://api.groq.com/openai/v1")!,
            model: model,
            requiresAPIKey: true
        )
    }

    static func customOpenAICompatibleChat(
        baseURL: URL,
        model: String,
        requiresAPIKey: Bool = false
    ) -> TranscriptCleanupProvider {
        TranscriptCleanupProvider(
            id: .customOpenAICompatibleChat,
            displayName: "Custom OpenAI-compatible chat",
            baseURL: baseURL,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "llama3.1:8b" : model,
            requiresAPIKey: requiresAPIKey
        )
    }

    var chatCompletionsEndpoint: URL? {
        endpoint("chat/completions")
    }

    var modelsEndpoint: URL? {
        endpoint("models")
    }

    private func endpoint(_ path: String) -> URL? {
        guard let baseURL else { return nil }
        let root = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(root)/\(path)")
    }
}
```

- [ ] **Step 4: Add AppState persisted defaults**

Add stored properties near `transcriptCleanupModel` in `Foil/AppState.swift`:

```swift
var transcriptCleanupProviderID: TranscriptCleanupProviderID = .groq {
    didSet { Self.defaults.set(transcriptCleanupProviderID.rawValue, forKey: "transcriptCleanupProvider") }
}

var customTranscriptCleanupBaseURL: String = "http://127.0.0.1:11434/v1" {
    didSet { Self.defaults.set(customTranscriptCleanupBaseURL, forKey: "customTranscriptCleanupBaseURL") }
}

var customTranscriptCleanupModel: String = "llama3.1:8b" {
    didSet { Self.defaults.set(customTranscriptCleanupModel, forKey: "customTranscriptCleanupModel") }
}
```

Load them in `init()` after `transcriptCleanupModel`:

```swift
transcriptCleanupProviderID = TranscriptCleanupProviderID(rawValue: defaults.string(forKey: "transcriptCleanupProvider") ?? "") ?? .groq
customTranscriptCleanupBaseURL = defaults.string(forKey: "customTranscriptCleanupBaseURL") ?? "http://127.0.0.1:11434/v1"
customTranscriptCleanupModel = defaults.string(forKey: "customTranscriptCleanupModel") ?? "llama3.1:8b"
```

Include keys in reset/default dictionaries if present in `AppState.reset...` helpers:

```swift
"transcriptCleanupProvider",
"customTranscriptCleanupBaseURL",
"customTranscriptCleanupModel",
```

with defaults:

```swift
"transcriptCleanupProvider": "groq",
"customTranscriptCleanupBaseURL": "http://127.0.0.1:11434/v1",
"customTranscriptCleanupModel": "llama3.1:8b",
```

- [ ] **Step 5: Run tests**

Run:

```sh
xcodebuild test -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionServiceTests/testCustomChatCleanupProviderBuildsExpectedEndpoints -only-testing:FoilTests/TranscriptionServiceTests/testNoCleanupProviderHasNoEndpoints
```

Expected: PASS.

- [ ] **Step 6: Commit**

```sh
git add Foil/TranscriptionService.swift Foil/AppState.swift FoilTests/TranscriptionServiceTests.swift
git commit -m "feat: add transcript cleanup provider model"
```

## Task 2: Scoped Cleanup Credentials

**Files:**
- Modify: `Foil/KeychainHelper.swift`
- Test: add or extend `FoilTests/KeychainHelperTests.swift` if present; otherwise add coverage in `FoilTests/TranscriptionControllerTests.swift`.

- [ ] **Step 1: Write failing credential scope test**

If `FoilTests/KeychainHelperTests.swift` exists, add there. Otherwise add to `TranscriptionControllerTests`:

```swift
func testCleanupApiKeyDoesNotOverwriteGroqOrCustomTranscriptionKeys() throws {
    try KeychainHelper.save(apiKey: "groq-key", for: .groq)
    try KeychainHelper.save(apiKey: "transcription-key", for: .openAICompatible)
    try KeychainHelper.saveCleanupApiKey("cleanup-key", for: .customOpenAICompatibleChat)

    XCTAssertEqual(KeychainHelper.readApiKey(for: .groq), "groq-key")
    XCTAssertEqual(KeychainHelper.readApiKey(for: .openAICompatible), "transcription-key")
    XCTAssertEqual(KeychainHelper.readCleanupApiKey(for: .customOpenAICompatibleChat), "cleanup-key")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the exact test added:

```sh
xcodebuild test -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionControllerTests/testCleanupApiKeyDoesNotOverwriteGroqOrCustomTranscriptionKeys
```

Expected: FAIL because cleanup key APIs do not exist.

- [ ] **Step 3: Implement cleanup key APIs**

In `Foil/KeychainHelper.swift`, add:

```swift
private static func cleanupAccount(for providerID: TranscriptCleanupProviderID) -> String {
    #if DEBUG
    let base = accountOverride ?? defaultAccount
    #else
    let base = defaultAccount
    #endif
    return "\(base).cleanup.\(providerID.rawValue)"
}

static func saveCleanupApiKey(_ apiKey: String, for providerID: TranscriptCleanupProviderID) throws {
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    try saveToKeychain(apiKey: trimmed, account: cleanupAccount(for: providerID))
}

static func readCleanupApiKey(for providerID: TranscriptCleanupProviderID) -> String? {
    readFromKeychain(account: cleanupAccount(for: providerID))
}

static func deleteCleanupApiKey(for providerID: TranscriptCleanupProviderID) {
    deleteFromKeychain(account: cleanupAccount(for: providerID))
}
```

Refactor private helpers so both provider and cleanup accounts can call them:

```swift
private static func saveToKeychain(apiKey: String, for providerID: TranscriptionProviderID = .groq) throws {
    try saveToKeychain(apiKey: apiKey, account: account(for: providerID))
}

private static func saveToKeychain(apiKey: String, account: String) throws {
    let data = Data(apiKey.utf8)
    let query = baseQuery(account: account)
    let attributes: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    let addStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
    if addStatus == errSecSuccess { return }
    if addStatus == errSecDuplicateItem {
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecSuccess else { throw KeychainError.unhandledStatus(updateStatus) }
        return
    }
    throw KeychainError.unhandledStatus(addStatus)
}

private static func readFromKeychain(for providerID: TranscriptionProviderID = .groq) -> String? {
    readFromKeychain(account: account(for: providerID))
}

private static func readFromKeychain(account: String) -> String? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let context = LAContext()
    context.interactionNotAllowed = true
    query[kSecUseAuthenticationContext as String] = context
    let (status, result) = copyMatching(query)
    guard status == errSecSuccess,
          let data = result as? Data,
          let key = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !key.isEmpty else {
        return nil
    }
    return key
}

private static func deleteFromKeychain(for providerID: TranscriptionProviderID = .groq) {
    deleteFromKeychain(account: account(for: providerID))
}

private static func deleteFromKeychain(account: String) {
    SecItemDelete(baseQuery(account: account) as CFDictionary)
}

private static func baseQuery(for providerID: TranscriptionProviderID = .groq) -> [String: Any] {
    baseQuery(account: account(for: providerID))
}

private static func baseQuery(account: String) -> [String: Any] {
    [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]
}
```

- [ ] **Step 4: Run test**

Run:

```sh
xcodebuild test -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionControllerTests/testCleanupApiKeyDoesNotOverwriteGroqOrCustomTranscriptionKeys
```

Expected: PASS.

- [ ] **Step 5: Commit**

```sh
git add Foil/KeychainHelper.swift FoilTests
git commit -m "feat: scope cleanup provider credentials"
```

## Task 3: Cleanup Service Routing

**Files:**
- Modify: `Foil/TranscriptionService.swift`
- Modify: `Foil/AppState.swift`
- Modify: `Foil/TranscriptionController.swift`
- Test: `FoilTests/TranscriptionControllerTests.swift`

- [ ] **Step 1: Write failing routing tests**

Add to `TranscriptionControllerTests`:

```swift
func testLocalProviderWithCleanupModeDoesNotCallGroqByDefault() async {
    appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
    appState.transcriptProcessingMode = .cleanUp
    appState.transcriptCleanupProviderID = .none
    let transport = ControllerStubTransport { request in
        XCTFail("Unexpected cleanup request to \(request.url?.absoluteString ?? "<nil>")")
        throw URLError(.badURL)
    }

    let result = await controller.processTranscriptOrRaw(
        rawText: "raw local transcript",
        apiKey: nil,
        service: TranscriptionService(transport: transport),
        context: "test"
    )

    XCTAssertEqual(result.text, "raw local transcript")
    XCTAssertFalse(result.cleanupFailed)
    XCTAssertEqual(transport.requests.count, 0)
}

func testCustomChatCleanupUsesCustomEndpointModelAndKey() async throws {
    appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
    appState.transcriptProcessingMode = .cleanUp
    appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
    appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
    appState.customTranscriptCleanupModel = "qwen2.5:7b"
    try KeychainHelper.saveCleanupApiKey("cleanup-secret", for: .customOpenAICompatibleChat)

    let transport = ControllerStubTransport { request in
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cleanup-secret")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains(#""model":"qwen2.5:7b""#), body)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(#"{"choices":[{"message":{"content":"cleaned locally"}}]}"#.utf8), response)
    }

    let result = await controller.processTranscriptOrRaw(
        rawText: "raw words",
        apiKey: nil,
        service: TranscriptionService(transport: transport),
        context: "test"
    )

    XCTAssertEqual(result.text, "cleaned locally")
    XCTAssertFalse(result.cleanupFailed)
    XCTAssertEqual(transport.requests.count, 1)
}

func testCustomChatCleanupFailureFallsBackToRaw() async {
    appState.selectedTranscriptionProviderPresetID = .customOpenAICompatible
    appState.transcriptProcessingMode = .rewriteClearly
    appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
    appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
    appState.customTranscriptCleanupModel = "llama3.1:8b"

    let transport = ControllerStubTransport { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        return (Data(#"{"error":{"message":"server unavailable"}}"#.utf8), response)
    }

    let result = await controller.processTranscriptOrRaw(
        rawText: "raw survives",
        apiKey: nil,
        service: TranscriptionService(transport: transport),
        context: "test"
    )

    XCTAssertEqual(result.text, "raw survives")
    XCTAssertTrue(result.cleanupFailed)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```sh
xcodebuild test -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionControllerTests/testLocalProviderWithCleanupModeDoesNotCallGroqByDefault -only-testing:FoilTests/TranscriptionControllerTests/testCustomChatCleanupUsesCustomEndpointModelAndKey -only-testing:FoilTests/TranscriptionControllerTests/testCustomChatCleanupFailureFallsBackToRaw
```

Expected: FAIL because cleanup provider routing is not implemented.

- [ ] **Step 3: Add AppState cleanup resolution**

In `Foil/AppState.swift`, replace `supportsSelectedTranscriptProcessing` / `effectiveTranscriptProcessingMode` behavior with cleanup routing-aware behavior:

```swift
var customTranscriptCleanupBaseURLValue: URL? {
    let trimmed = customTranscriptCleanupBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          url.host != nil else {
        return nil
    }
    return url
}

var selectedTranscriptCleanupProvider: TranscriptCleanupProvider {
    switch transcriptCleanupProviderID {
    case .none:
        return .none
    case .groq:
        return .groq(model: transcriptCleanupModel)
    case .customOpenAICompatibleChat:
        return .customOpenAICompatibleChat(
            baseURL: customTranscriptCleanupBaseURLValue ?? URL(string: "http://127.0.0.1:11434/v1")!,
            model: customTranscriptCleanupModel
        )
    }
}

var supportsSelectedTranscriptProcessing: Bool {
    selectedTranscriptCleanupProvider.id != .none
}

var effectiveTranscriptProcessingMode: TranscriptProcessingMode {
    transcriptProcessingMode == .raw || !supportsSelectedTranscriptProcessing ? .raw : transcriptProcessingMode
}
```

Ensure provider changes do not auto-select Groq cleanup for local/custom providers. If needed, add this to `selectedTranscriptionProviderPresetID.didSet` after refresh:

```swift
if selectedTranscriptionProviderPresetID != .groq && transcriptCleanupProviderID == .groq {
    transcriptCleanupProviderID = .none
}
```

- [ ] **Step 4: Add cleanup processing service method**

In `Foil/TranscriptionService.swift`, add:

```swift
func processTranscript(
    _ transcript: String,
    apiKey: String?,
    mode: TranscriptProcessingMode,
    provider cleanupProvider: TranscriptCleanupProvider
) async throws -> String {
    guard mode != .raw else { return transcript }
    guard let endpoint = cleanupProvider.chatCompletionsEndpoint else {
        return transcript
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    setAuthorizationHeader(apiKey: apiKey, on: &request)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try buildTranscriptProcessingBody(
        transcript: transcript,
        mode: mode,
        model: cleanupProvider.model
    )

    DiagnosticLog.write("processTranscript: sending cleanupProvider=\(cleanupProvider.id.rawValue) mode=\(mode.rawValue) model=\(cleanupProvider.model) inputLength=\(transcript.count)")
    let (data, response) = try await transport.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        DiagnosticLog.write("processTranscript: invalid response type")
        throw TranscriptionError.invalidResponse
    }
    DiagnosticLog.write("processTranscript: response status=\(http.statusCode) responseBytes=\(data.count)")

    if http.statusCode == 200 {
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw TranscriptionError.invalidResponse
        }
        DiagnosticLog.write("processTranscript: success outputLength=\(content.count)")
        return content
    }

    throw mapAPIError(statusCode: http.statusCode, data: data)
}
```

- [ ] **Step 5: Route cleanup separately in controller**

Update `TranscriptionController.processTranscriptOrRaw` after raw guard:

```swift
let cleanupProvider = appState.selectedTranscriptCleanupProvider
guard cleanupProvider.id != .none else {
    DiagnosticLog.write("\(context): transcript processing skipped because cleanup provider is none")
    return (rawText, false)
}

let cleanupApiKey: String?
switch cleanupProvider.id {
case .none:
    cleanupApiKey = nil
case .groq:
    cleanupApiKey = KeychainHelper.readApiKey(for: .groq)
case .customOpenAICompatibleChat:
    cleanupApiKey = KeychainHelper.readCleanupApiKey(for: .customOpenAICompatibleChat)
}

let service = service ?? transcriptionService
appState.transcriptionStage = .cleaningTranscript
do {
    let text = try await service.processTranscript(
        rawText,
        apiKey: cleanupApiKey,
        mode: processingMode,
        provider: cleanupProvider
    )
    return (text, false)
} catch {
    DiagnosticLog.write("\(context): cleanup failed mappedMessage=\(errorMessage(from: error))")
    return (rawText, true)
}
```

Remove the older same-provider cleanup call from this method.

- [ ] **Step 6: Run tests**

Run:

```sh
xcodebuild test -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionControllerTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```sh
git add Foil/TranscriptionService.swift Foil/AppState.swift Foil/TranscriptionController.swift FoilTests/TranscriptionControllerTests.swift
git commit -m "feat: route transcript cleanup through explicit provider"
```

## Task 4: Custom Cleanup Connection Testing

**Files:**
- Modify: `Foil/TranscriptionService.swift`
- Modify: `Foil/AppState.swift`
- Test: `FoilTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Write failing service tests**

Add to `TranscriptionServiceTests`:

```swift
func testValidateCustomCleanupProviderUsesModelsEndpoint() async throws {
    let transport = StubTransport { request in
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/models")
        let response = Self.httpResponse(statusCode: 200, url: request.url!)
        return (Data(#"{"data":[{"id":"llama3.1:8b"}]}"#.utf8), response)
    }
    let service = TranscriptionService(transport: transport)
    let provider = TranscriptCleanupProvider.customOpenAICompatibleChat(
        baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
        model: "llama3.1:8b"
    )

    let result = try await service.validateCleanupProviderConfiguration(provider: provider, apiKey: nil)

    XCTAssertEqual(result, .modelsValidated)
    XCTAssertEqual(transport.requests.count, 1)
}

func testValidateCustomCleanupProviderFallsBackToChatSmokeWhenModelsUnsupported() async throws {
    let transport = StubTransport { request in
        if request.url?.path.hasSuffix("/models") == true {
            let response = Self.httpResponse(statusCode: 404, url: request.url!)
            return (Data(), response)
        }
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains(#""model":"llama3.1:8b""#), body)
        let response = Self.httpResponse(statusCode: 200, url: request.url!)
        return (Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8), response)
    }
    let service = TranscriptionService(transport: transport)
    let provider = TranscriptCleanupProvider.customOpenAICompatibleChat(
        baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
        model: "llama3.1:8b"
    )

    let result = try await service.validateCleanupProviderConfiguration(provider: provider, apiKey: nil)

    XCTAssertEqual(result, .reachableWithoutModelValidation)
    XCTAssertEqual(transport.requests.count, 2)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```sh
xcodebuild test -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionServiceTests/testValidateCustomCleanupProviderUsesModelsEndpoint -only-testing:FoilTests/TranscriptionServiceTests/testValidateCustomCleanupProviderFallsBackToChatSmokeWhenModelsUnsupported
```

Expected: FAIL because `validateCleanupProviderConfiguration` does not exist.

- [ ] **Step 3: Implement cleanup validation**

Add to `TranscriptionService.swift`:

```swift
func validateCleanupProviderConfiguration(
    provider cleanupProvider: TranscriptCleanupProvider,
    apiKey: String?
) async throws -> ProviderValidationResult {
    guard cleanupProvider.id != .none,
          let modelsEndpoint = cleanupProvider.modelsEndpoint else {
        throw TranscriptionError.invalidProviderURL
    }
    guard let baseURL = cleanupProvider.baseURL,
          isValidHTTPBaseURL(baseURL) else {
        throw TranscriptionError.invalidProviderURL
    }

    var modelsRequest = URLRequest(url: modelsEndpoint)
    modelsRequest.httpMethod = "GET"
    modelsRequest.timeoutInterval = Self.providerValidationTimeout
    setAuthorizationHeader(apiKey: apiKey, on: &modelsRequest)

    let (modelsData, modelsResponse) = try await transport.data(for: modelsRequest)
    guard let modelsHTTP = modelsResponse as? HTTPURLResponse else {
        throw TranscriptionError.invalidResponse
    }
    switch modelsHTTP.statusCode {
    case 200:
        if let responseBody = try? JSONDecoder().decode(ModelsResponse.self, from: modelsData) {
            let availableModels = Set(responseBody.data.map(\.id))
            if !cleanupProvider.model.isEmpty && !availableModels.contains(cleanupProvider.model) {
                throw TranscriptionError.modelUnavailable(cleanupProvider.model)
            }
            return .modelsValidated
        }
        return .reachableWithoutModelValidation
    case 404, 405:
        return try await validateCleanupChatSmoke(provider: cleanupProvider, apiKey: apiKey)
    default:
        throw mapAPIError(statusCode: modelsHTTP.statusCode, data: modelsData)
    }
}

private func validateCleanupChatSmoke(
    provider cleanupProvider: TranscriptCleanupProvider,
    apiKey: String?
) async throws -> ProviderValidationResult {
    guard let endpoint = cleanupProvider.chatCompletionsEndpoint else {
        throw TranscriptionError.invalidProviderURL
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = Self.providerValidationTimeout
    setAuthorizationHeader(apiKey: apiKey, on: &request)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try buildTranscriptProcessingBody(
        transcript: "Connection test.",
        mode: .cleanUp,
        model: cleanupProvider.model
    )
    let (data, response) = try await transport.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw TranscriptionError.invalidResponse
    }
    guard http.statusCode == 200 else {
        throw mapAPIError(statusCode: http.statusCode, data: data)
    }
    return .reachableWithoutModelValidation
}
```

- [ ] **Step 4: Add AppState connection test wrapper**

Add state to `AppState`:

```swift
var cleanupConnectionTestState: ProviderConnectionTestState = .idle
```

Add method:

```swift
func testSelectedCleanupProviderConnection(
    service: TranscriptionService = TranscriptionService(),
    apiKey: String? = nil
) async {
    let provider = selectedTranscriptCleanupProvider
    guard provider.id == .customOpenAICompatibleChat else {
        cleanupConnectionTestState = .warning("Connection test is only needed for custom chat cleanup.")
        return
    }
    guard customTranscriptCleanupBaseURLValue != nil else {
        cleanupConnectionTestState = .failed("Invalid base URL. Use an http:// or https:// URL.")
        return
    }

    cleanupConnectionTestState = .running
    let key = apiKey ?? KeychainHelper.readCleanupApiKey(for: .customOpenAICompatibleChat)
    do {
        let result = try await service.validateCleanupProviderConfiguration(provider: provider, apiKey: key)
        switch result {
        case .modelsValidated:
            cleanupConnectionTestState = .succeeded("Cleanup server reachable. Model \(provider.model) is available.")
        case .reachableWithoutModelValidation:
            cleanupConnectionTestState = .warning("Cleanup server reachable. Model availability was not checked.")
        }
    } catch TranscriptionService.TranscriptionError.modelUnavailable(let model) {
        cleanupConnectionTestState = .failed("Cleanup server reachable, but model \(model) was not listed.")
    } catch TranscriptionService.TranscriptionError.invalidProviderURL {
        cleanupConnectionTestState = .failed("Invalid base URL. Use an http:// or https:// URL.")
    } catch is URLError {
        cleanupConnectionTestState = .failed("Could not reach custom cleanup endpoint. Check that the server is running.")
    } catch {
        cleanupConnectionTestState = .failed("Cleanup connection test failed: \(error.localizedDescription)")
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```sh
xcodebuild test -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionServiceTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```sh
git add Foil/TranscriptionService.swift Foil/AppState.swift FoilTests/TranscriptionServiceTests.swift
git commit -m "feat: validate custom cleanup chat endpoint"
```

## Task 5: Settings UI

**Files:**
- Modify: `Foil/SettingsView.swift`
- Modify: `Foil/ApiKeySetupView.swift` or create inline cleanup key controls in `SettingsView.swift`
- Test: focused UI test if existing settings UI tests cover Transcription settings.

- [ ] **Step 1: Add UI test or source-level expectations**

If a settings UI test exists, add assertions for these identifiers:

```swift
XCTAssertTrue(app.popUpButtons["settings.cleanupProviderPicker"].exists)
XCTAssertTrue(app.textFields["settings.customTranscriptCleanupBaseURL"].exists)
XCTAssertTrue(app.textFields["settings.customTranscriptCleanupModel"].exists)
XCTAssertTrue(app.buttons["settings.testCleanupConnectionButton"].exists)
XCTAssertTrue(app.staticTexts["settings.cleanupRoutingHelp"].exists)
```

If there is no suitable UI test harness, add the identifiers in implementation and verify with `make test-ui` after Task 5.

- [ ] **Step 2: Update cleanup section**

Replace the current `Section("Cleanup")` body in `SettingsView.swift` with:

```swift
Section("Cleanup") {
    Picker("After transcription", selection: $appState.transcriptProcessingMode) {
        ForEach(TranscriptProcessingMode.allCases) { mode in
            Text(mode.displayName).tag(mode)
        }
    }
    .accessibilityIdentifier("settings.transcriptProcessingPicker")

    if appState.transcriptProcessingMode != .raw {
        Picker("Cleanup provider", selection: $appState.transcriptCleanupProviderID) {
            if appState.selectedTranscriptionProviderPresetID == .groq {
                Text("Groq").tag(TranscriptCleanupProviderID.groq)
            }
            Text("None").tag(TranscriptCleanupProviderID.none)
            Text("Custom OpenAI-compatible chat").tag(TranscriptCleanupProviderID.customOpenAICompatibleChat)
        }
        .accessibilityIdentifier("settings.cleanupProviderPicker")

        Text("Cleanup uses the selected chat endpoint. Foil will not send local/custom transcripts to Groq unless you choose Groq here.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("settings.cleanupRoutingHelp")

        if appState.transcriptCleanupProviderID == .groq {
            Picker("Cleanup model", selection: $appState.transcriptCleanupModel) {
                Text("Llama 3.3 70B Versatile").tag("llama-3.3-70b-versatile")
                Text("Llama 3.1 8B Instant").tag("llama-3.1-8b-instant")
            }
            .accessibilityIdentifier("settings.cleanupModelPicker")
        } else if appState.transcriptCleanupProviderID == .customOpenAICompatibleChat {
            TextField("Chat base URL", text: $appState.customTranscriptCleanupBaseURL)
                .accessibilityIdentifier("settings.customTranscriptCleanupBaseURL")
            TextField("Chat model", text: $appState.customTranscriptCleanupModel)
                .accessibilityIdentifier("settings.customTranscriptCleanupModel")

            HStack {
                Button("Test cleanup connection") {
                    Task { await appState.testSelectedCleanupProviderConnection() }
                }
                .disabled(appState.cleanupConnectionTestState.isRunning)
                .accessibilityIdentifier("settings.testCleanupConnectionButton")

                cleanupConnectionStatus
            }

            Text("API key is optional. If your endpoint requires one, save it for custom cleanup before testing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.customCleanupHelp")
        } else {
            Text("Foil will paste raw transcripts until a cleanup provider is selected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.transcriptProcessingUnavailable")
        }
    }
}
```

- [ ] **Step 3: Add cleanup status view helper**

Add near `providerConnectionStatus`:

```swift
@ViewBuilder
private var cleanupConnectionStatus: some View {
    switch appState.cleanupConnectionTestState {
    case .idle:
        EmptyView()
    case .running:
        ProgressView()
            .controlSize(.small)
            .accessibilityIdentifier("settings.cleanupConnectionProgress")
    case .succeeded(let message):
        Label(message, systemImage: "checkmark.circle")
            .foregroundStyle(.green)
            .accessibilityIdentifier("settings.cleanupConnectionSucceeded")
    case .warning(let message):
        Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .accessibilityIdentifier("settings.cleanupConnectionWarning")
    case .failed(let message):
        Label(message, systemImage: "xmark.circle")
            .foregroundStyle(.red)
            .accessibilityIdentifier("settings.cleanupConnectionFailed")
    }
}
```

- [ ] **Step 4: Add cleanup key control**

Use a small inline secure field in the custom cleanup block if reusing `ApiKeySetupView` is too Groq/transcription-specific:

```swift
@State private var customCleanupAPIKey = ""
```

Add under custom cleanup help:

```swift
SecureField("Optional cleanup API key", text: $customCleanupAPIKey)
    .accessibilityIdentifier("settings.customCleanupAPIKey")
HStack {
    Button("Save cleanup key") {
        Task {
            try? KeychainHelper.saveCleanupApiKey(customCleanupAPIKey, for: .customOpenAICompatibleChat)
            customCleanupAPIKey = ""
        }
    }
    .disabled(customCleanupAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    .accessibilityIdentifier("settings.saveCustomCleanupAPIKeyButton")

    Button("Delete cleanup key") {
        KeychainHelper.deleteCleanupApiKey(for: .customOpenAICompatibleChat)
        customCleanupAPIKey = ""
    }
    .accessibilityIdentifier("settings.deleteCustomCleanupAPIKeyButton")
}
```

- [ ] **Step 5: Run UI/build checks**

Run:

```sh
xcodebuild build -scheme Foil -configuration Debug -destination 'platform=macOS' OTHER_SWIFT_FLAGS='-warnings-as-errors'
make test-ui
```

Expected: build succeeds and focused UI smoke passes. If UI tests are too broad locally, run the specific settings test target and record the reason.

- [ ] **Step 6: Commit**

```sh
git add Foil/SettingsView.swift FoilTests
git commit -m "feat: expose custom chat cleanup settings"
```

## Task 6: Diagnostics And Docs

**Files:**
- Modify: `Foil/DiagnosticLog.swift`
- Modify: `FoilTests/DiagnosticLogTests.swift`
- Modify: `README.md`

- [ ] **Step 1: Write failing diagnostics test**

Add to `DiagnosticLogTests`:

```swift
func testSetupReportIncludesCleanupProviderWithoutSecrets() {
    let appState = AppState()
    appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
    appState.transcriptProcessingMode = .cleanUp
    appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
    appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
    appState.customTranscriptCleanupModel = "llama3.1:8b"

    let report = DiagnosticLog.setupReport(appState: appState)

    XCTAssertTrue(report.contains("- Cleanup Provider: Custom OpenAI-compatible chat"))
    XCTAssertTrue(report.contains("- Cleanup Base URL: http://127.0.0.1:11434/v1"))
    XCTAssertTrue(report.contains("- Cleanup Model: llama3.1:8b"))
    XCTAssertFalse(report.contains("cleanup-secret"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```sh
xcodebuild test -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/DiagnosticLogTests/testSetupReportIncludesCleanupProviderWithoutSecrets
```

Expected: FAIL because cleanup provider fields are absent.

- [ ] **Step 3: Update diagnostics**

In `DiagnosticLog.setupReport`, add lines:

```swift
"- Cleanup Provider: \(appState.selectedTranscriptCleanupProvider.displayName)",
"- Cleanup Base URL: \(appState.selectedTranscriptCleanupProvider.baseURL?.absoluteString ?? "None")",
"- Cleanup Model: \(appState.selectedTranscriptCleanupProvider.model.isEmpty ? "None" : appState.selectedTranscriptCleanupProvider.model)",
```

Do not read or print cleanup API keys.

- [ ] **Step 4: Update README provider section**

Change the cleanup copy to:

```markdown
Cleanup modes can use Groq chat models or a Custom OpenAI-compatible chat
endpoint. Local whisper.cpp and custom transcription remain raw by default;
Foil will not send local/custom transcripts to Groq for cleanup unless you
explicitly select Groq as the cleanup provider. If you choose a custom cleanup
endpoint, transcript text is sent to that endpoint.
```

Add troubleshooting:

```markdown
**Custom cleanup endpoint not reachable:** Confirm the chat server is running,
the base URL includes `/v1`, the model name matches the server, and any required
API key is saved in Cleanup settings.

**Cleanup failed but raw transcript pasted:** Transcription succeeded, but the
cleanup endpoint failed or returned an unsupported response. Foil pasted the raw
transcript so your dictation is not lost.
```

- [ ] **Step 5: Run tests and docs grep**

Run:

```sh
xcodebuild test -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/DiagnosticLogTests
rg -n "Cleanup modes|Custom cleanup endpoint not reachable|Foil will not send local/custom transcripts to Groq" README.md
```

Expected: tests pass and README contains updated copy.

- [ ] **Step 6: Commit**

```sh
git add Foil/DiagnosticLog.swift FoilTests/DiagnosticLogTests.swift README.md
git commit -m "docs: explain custom chat cleanup routing"
```

## Task 7: Final Verification And PR

**Files:**
- No feature files unless fixing verification failures.

- [ ] **Step 1: Run focused unit tests**

Run:

```sh
xcodebuild test -scheme Foil -destination 'platform=macOS' -only-testing:FoilTests/TranscriptionServiceTests -only-testing:FoilTests/TranscriptionControllerTests -only-testing:FoilTests/DiagnosticLogTests
```

Expected: PASS.

- [ ] **Step 2: Run full unit suite**

Run:

```sh
make test
```

Expected: PASS.

- [ ] **Step 3: Run UI smoke**

Run:

```sh
make test-ui
```

Expected: PASS. If a local macOS permission state blocks UI tests, record exact output and use CI as the required verification.

- [ ] **Step 4: Run diff check**

Run:

```sh
git diff --check
```

Expected: no output.

- [ ] **Step 5: Optional live smoke with owner-provided key**

Only run when explicitly provided an OpenAI-compatible chat API key. Use a
manual curl smoke if no dedicated Make target exists:

```sh
curl "$OPENAI_COMPATIBLE_CHAT_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $OPENAI_COMPATIBLE_CHAT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"$OPENAI_COMPATIBLE_CHAT_MODEL"'",
    "messages": [
      {"role":"system","content":"Clean up the transcript lightly. Return only the cleaned text."},
      {"role":"user","content":"hello comma this is a foil cleanup smoke test"}
    ],
    "temperature": 0.2,
    "max_completion_tokens": 64
  }'
```

Expected: the endpoint returns a chat-completions response with non-empty
assistant content. Do not commit or paste the key.

- [ ] **Step 6: Push and open PR**

```sh
git status --short
git push -u origin HEAD
gh pr create --fill
```

Expected: PR opens with summary, tests, and issue #86 reference.

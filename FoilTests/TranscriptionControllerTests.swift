import XCTest
@testable import Foil

// MARK: - Delegate spy

@MainActor
final class TranscriptionDelegateSpy: TranscriptionControllerDelegate {
    private(set) var didStartCalls: [URL] = []
    private(set) var didTranscribeCalls: [(text: String, audioURL: URL, cleanupFailed: Bool)] = []
    private(set) var didFailCalls: [(error: Error, errorMessage: String, audioURL: URL, format: AudioFormat)] = []

    func transcriptionController(
        _ controller: TranscriptionController,
        didStartTranscribing audioURL: URL
    ) {
        didStartCalls.append(audioURL)
    }

    func transcriptionController(
        _ controller: TranscriptionController,
        didTranscribe text: String,
        audioURL: URL,
        cleanupFailed: Bool
    ) {
        didTranscribeCalls.append((text: text, audioURL: audioURL, cleanupFailed: cleanupFailed))
    }

    func transcriptionController(
        _ controller: TranscriptionController,
        didFail error: Error,
        errorMessage: String,
        audioURL: URL,
        format: AudioFormat
    ) {
        didFailCalls.append((error: error, errorMessage: errorMessage, audioURL: audioURL, format: format))
    }
}

private final class ControllerStubTransport: TranscriptionTransport {
    var requests: [URLRequest] = []
    let handler: (URLRequest) async throws -> (Data, URLResponse)

    init(handler: @escaping (URLRequest) async throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return try await handler(request)
    }
}

// MARK: - Tests

@MainActor
final class TranscriptionControllerTests: XCTestCase {
    private var appState: AppState!
    private var controller: TranscriptionController!
    private var spy: TranscriptionDelegateSpy!
    private var keychainStorageDirectory: URL!
    private let defaultsDomainName = Bundle.main.bundleIdentifier ?? "com.neonwatty.Foil"

    override func setUpWithError() throws {
        UserDefaults.standard.removePersistentDomain(forName: defaultsDomainName)
        keychainStorageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilTranscriptionControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: keychainStorageDirectory, withIntermediateDirectories: true)
        KeychainHelper.serviceOverride = "com.neonwatty.Foil.transcription-controller-tests.\(UUID().uuidString)"
        KeychainHelper.storageDirectoryOverride = keychainStorageDirectory
        appState = AppState()
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(),
            appState: appState
        )
        spy = TranscriptionDelegateSpy()
        controller.delegate = spy
    }

    override func tearDown() {
        controller = nil
        appState = nil
        spy = nil
        if let keychainStorageDirectory {
            try? FileManager.default.removeItem(at: keychainStorageDirectory)
        }
        KeychainHelper.serviceOverride = nil
        KeychainHelper.storageDirectoryOverride = nil
        keychainStorageDirectory = nil
        UserDefaults.standard.removePersistentDomain(forName: defaultsDomainName)
    }

    // MARK: - errorMessage mapping

    func testErrorMessageInvalidApiKey() {
        let msg = controller.errorMessage(from: TranscriptionService.TranscriptionError.invalidApiKey)
        XCTAssertEqual(msg, "Invalid API key")
    }

    func testErrorMessageRateLimited() {
        let msg = controller.errorMessage(from: TranscriptionService.TranscriptionError.rateLimited("Rate limit reached"))
        XCTAssertEqual(msg, "Groq rate limit reached")
    }

    func testErrorMessageFileTooLarge() {
        let msg = controller.errorMessage(from: TranscriptionService.TranscriptionError.fileTooLarge)
        XCTAssertEqual(msg, "Recording too long")
    }

    func testErrorMessageRecordingTooLong() {
        let msg = controller.errorMessage(from: AudioRecorder.RecordingError.recordingTooLong)
        XCTAssertEqual(msg, "Recording too long")
    }

    func testErrorMessageQuotaExceeded() {
        let msg = controller.errorMessage(from: TranscriptionService.TranscriptionError.quotaExceeded(nil))
        XCTAssertEqual(msg, "Groq quota exceeded")
    }

    func testErrorMessageServerError() {
        let msg = controller.errorMessage(from: TranscriptionService.TranscriptionError.serverError(503))
        XCTAssertEqual(msg, "Groq is temporarily unavailable")
    }

    func testErrorMessageBadRequest() {
        let msg = controller.errorMessage(from: TranscriptionService.TranscriptionError.badRequest(nil))
        XCTAssertEqual(msg, "Groq rejected the request")
    }

    func testErrorMessageModelUnavailable() {
        let msg = controller.errorMessage(from: TranscriptionService.TranscriptionError.modelUnavailable("some-model"))
        XCTAssertEqual(msg, "Model unavailable: some-model")
    }

    func testErrorMessageApiError() {
        let msg = controller.errorMessage(from: TranscriptionService.TranscriptionError.apiError(418, "teapot"))
        XCTAssertEqual(msg, "API error (418)")
    }

    func testErrorMessageNoInternet() {
        let msg = controller.errorMessage(from: URLError(.notConnectedToInternet))
        XCTAssertEqual(msg, "No internet connection")
    }

    func testErrorMessageTimedOut() {
        let msg = controller.errorMessage(from: URLError(.timedOut))
        XCTAssertEqual(msg, "Request timed out")
    }

    func testErrorMessageCannotConnectToHost() {
        let msg = controller.errorMessage(from: URLError(.cannotConnectToHost))
        XCTAssertEqual(msg, "Cannot reach Groq")
    }

    func testErrorMessageCannotFindHost() {
        let msg = controller.errorMessage(from: URLError(.cannotFindHost))
        XCTAssertEqual(msg, "Cannot reach Groq")
    }

    func testErrorMessageUsesSelectedProviderForLocalProvider() {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP

        XCTAssertEqual(
            controller.errorMessage(from: TranscriptionService.TranscriptionError.serverError(503)),
            "Local whisper.cpp is temporarily unavailable"
        )
        XCTAssertEqual(
            controller.errorMessage(from: URLError(.cannotConnectToHost)),
            "Cannot reach Local whisper.cpp"
        )
    }

    func testErrorMessageUnknownFallback() {
        struct SomeUnknownError: Error, LocalizedError {
            var errorDescription: String? { "something went wrong" }
        }
        let msg = controller.errorMessage(from: SomeUnknownError())
        XCTAssertTrue(msg.hasPrefix("Transcription failed:"), "Expected fallback message, got: \(msg)")
    }

    // MARK: - processTranscriptOrRaw

    func testProcessTranscriptOrRawReturnsRawWhenModeIsRaw() async {
        appState.transcriptProcessingMode = .raw
        let result = await controller.processTranscriptOrRaw(
            rawText: "hello world",
            apiKey: "any-key",
            context: "test"
        )
        XCTAssertEqual(result.text, "hello world")
        XCTAssertFalse(result.cleanupFailed)
    }

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
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testOpenAICleanupUsesOpenAIKeyEvenWhenTranscriptionProviderIsGroq() async throws {
        appState.selectedTranscriptionProviderPresetID = .groq
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .openAI
        appState.openAITranscriptCleanupModel = "gpt-5.4-mini"
        try KeychainHelper.save(apiKey: "groq-transcription-key", for: .groq)
        try KeychainHelper.save(apiKey: "openai-cleanup-key", for: .openAI)

        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-cleanup-key")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains(#""model":"gpt-5.4-mini""#), body)
            XCTAssertTrue(body.contains(#""input":"raw text""#), body)
            XCTAssertFalse(body.contains(#""messages""#), body)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"output_text":"openai clean text"}"#.utf8), response)
        }

        let result = await controller.processTranscriptOrRaw(
            rawText: "raw text",
            apiKey: "groq-transcription-key",
            service: TranscriptionService(transport: transport),
            context: "test"
        )

        XCTAssertEqual(result.text, "openai clean text")
        XCTAssertFalse(result.cleanupFailed)
        XCTAssertEqual(transport.requests.count, 1)
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

    func testProcessTranscriptOrRawStillRunsGroqCleanupWhenSupported() async throws {
        appState.selectedTranscriptionProviderID = .groq
        appState.transcriptProcessingMode = .cleanUp
        try KeychainHelper.save(apiKey: "test-key", for: .groq)
        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (
                Data(#"{"choices":[{"message":{"content":"clean transcript"}}]}"#.utf8),
                response
            )
        }
        let service = TranscriptionService(transport: transport)

        let result = await controller.processTranscriptOrRaw(
            rawText: "raw transcript",
            apiKey: "test-key",
            service: service,
            context: "test"
        )

        XCTAssertEqual(result.text, "clean transcript")
        XCTAssertFalse(result.cleanupFailed)
        XCTAssertEqual(transport.requests.count, 1)
    }

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

    func testInvalidCustomChatCleanupBaseURLDoesNotSendCleanupRequest() async {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "not a url"
        appState.customTranscriptCleanupModel = "llama3.1:8b"

        let transport = ControllerStubTransport { request in
            XCTFail("Unexpected cleanup request to \(request.url?.absoluteString ?? "<nil>")")
            throw URLError(.badURL)
        }

        let result = await controller.processTranscriptOrRaw(
            rawText: "raw stays local",
            apiKey: nil,
            service: TranscriptionService(transport: transport),
            context: "test"
        )

        XCTAssertEqual(result.text, "raw stays local")
        XCTAssertFalse(result.cleanupFailed)
        XCTAssertEqual(transport.requests.count, 0)
    }

    // MARK: - transcribe without API key

    func testTranscribeFailsGracefullyWithoutApiKey() async throws {
        // Ensure no API key is stored (test environment has no keychain entry for this test)
        // We make the audio URL point to a temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        // Write minimal data so the file exists
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // The test keychain environment almost certainly has no key; if it does this test is moot
        // but we still verify that either:
        //   (a) didFail is called (no key path), or
        //   (b) some network error is thrown (key exists, real network call fails)
        // Either way, didTranscribe must NOT be called.
        await controller.transcribe(audioURL: tempURL, format: .wav)

        XCTAssertEqual(spy.didTranscribeCalls.count, 0,
                        "didTranscribe should not be called when no API key or network fails")
        // didFail or didStart may have been called depending on environment
        // The important invariant: no successful transcription without an API key
    }

    func testLocalWhisperTranscribeDoesNotSendSharedOpenAICompatibleApiKey() async throws {
        try KeychainHelper.save(apiKey: "custom-compatible-key", for: .openAICompatible)
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/audio/transcriptions")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("local transcript".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState
        )
        controller.delegate = spy

        await controller.transcribe(audioURL: tempURL, format: .wav)

        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "local transcript")
        XCTAssertEqual(spy.didFailCalls.count, 0)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testLocalWhisperRetryDoesNotSendSharedOpenAICompatibleApiKey() async throws {
        try KeychainHelper.save(apiKey: "custom-compatible-key", for: .openAICompatible)
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let record = TranscriptionRecord(
            id: UUID(),
            timestamp: Date(),
            outcome: .failure(error: "previous failure", audioFileURL: tempURL)
        )
        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/audio/transcriptions")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("retried local transcript".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState
        )
        controller.delegate = spy

        await controller.retryTranscription(record: record)

        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "retried local transcript")
        XCTAssertEqual(spy.didFailCalls.count, 0)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testCustomOpenAICompatibleTranscribeStillSendsSharedOptionalApiKey() async throws {
        try KeychainHelper.save(apiKey: "custom-compatible-key", for: .openAICompatible)
        appState.selectedTranscriptionProviderPresetID = .customOpenAICompatible
        appState.customTranscriptionBaseURL = "http://127.0.0.1:9090/v1"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:9090/v1/audio/transcriptions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer custom-compatible-key")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("custom transcript".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState
        )
        controller.delegate = spy

        await controller.transcribe(audioURL: tempURL, format: .wav)

        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "custom transcript")
        XCTAssertEqual(spy.didFailCalls.count, 0)
        XCTAssertEqual(transport.requests.count, 1)
    }

    // MARK: - retryTranscription with missing audio file

    func testRetryTranscriptionWithNoAudioURLNotifiesDelegateOfFailure() async {
        let record = TranscriptionRecord(
            id: UUID(),
            timestamp: Date(),
            outcome: .failure(error: "some error", audioFileURL: nil)
        )
        await controller.retryTranscription(record: record)

        XCTAssertEqual(spy.didStartCalls.count, 0, "Should not start transcription")
        XCTAssertEqual(spy.didTranscribeCalls.count, 0, "Should not produce a transcript")
        XCTAssertEqual(spy.didFailCalls.count, 1, "Should notify delegate of failure")
        XCTAssertEqual(spy.didFailCalls.first?.errorMessage, "Recording no longer available for retry")
    }

    // MARK: - Delegate is notified of didStart before outcome

    func testTranscribeCallsDidStartBeforeOutcome() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await controller.transcribe(audioURL: tempURL, format: .wav)

        // didStart should be fired first regardless of outcome
        XCTAssertEqual(spy.didStartCalls.count, 1)
        XCTAssertEqual(spy.didStartCalls.first, tempURL)
    }
}

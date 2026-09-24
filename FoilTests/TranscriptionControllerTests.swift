import XCTest
import CryptoKit
@testable import Foil

// MARK: - Delegate spy

@MainActor
final class TranscriptionDelegateSpy: TranscriptionControllerDelegate {
    private(set) var didStartCalls: [URL] = []
    private(set) var didTranscribeCalls: [(
        text: String,
        originalText: String,
        audioURL: URL,
        cleanupFailed: Bool,
        localCorrectionFallbackReason: LocalCorrectionFallbackReason?
    )] = []
    private(set) var didDetectNoRecognizableAudioCalls: [(audioURL: URL, format: AudioFormat)] = []
    private(set) var didFailCalls: [(
        error: Error,
        errorMessage: String,
        audioURL: URL,
        format: AudioFormat,
        appContext: CleanupAppContext?
    )] = []

    func transcriptionController(
        _ controller: TranscriptionController,
        didStartTranscribing audioURL: URL
    ) {
        didStartCalls.append(audioURL)
    }

    func transcriptionController(
        _ controller: TranscriptionController,
        didTranscribe text: String,
        originalText: String,
        audioURL: URL,
        cleanupFailed: Bool,
        localCorrectionFallbackReason: LocalCorrectionFallbackReason?
    ) {
        didTranscribeCalls.append((
            text: text,
            originalText: originalText,
            audioURL: audioURL,
            cleanupFailed: cleanupFailed,
            localCorrectionFallbackReason: localCorrectionFallbackReason
        ))
    }

    func transcriptionController(
        _ controller: TranscriptionController,
        didDetectNoRecognizableAudio audioURL: URL,
        format: AudioFormat
    ) {
        didDetectNoRecognizableAudioCalls.append((audioURL: audioURL, format: format))
    }

    func transcriptionController(
        _ controller: TranscriptionController,
        didFail error: Error,
        errorMessage: String,
        audioURL: URL,
        format: AudioFormat,
        appContext: CleanupAppContext?
    ) {
        didFailCalls.append((
            error: error,
            errorMessage: errorMessage,
            audioURL: audioURL,
            format: format,
            appContext: appContext
        ))
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
        appState = AppState(
            localCorrectionStore: LocalCorrectionStore(
                fileURL: keychainStorageDirectory.appendingPathComponent("local-corrections.json")
            )
        )
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
        unsetenv("E2E_CLEANUP_RECEIPT_PATH")
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

    func testAgentFirstRawBaselinePreservesVocabularyAliasesAndOriginalBytes() async {
        appState.transcriptProcessingMode = .raw
        appState.vocabularyCorrections = [
            VocabularyCorrection(writtenAs: "super base", correctVersion: "Supabase"),
            VocabularyCorrection(writtenAs: "cloud code", correctVersion: "Claude Code"),
            VocabularyCorrection(writtenAs: "codecs", correctVersion: "Codex"),
            VocabularyCorrection(writtenAs: "the cell", correctVersion: "Vercel")
        ]
        let transport = ControllerStubTransport { _ in
            XCTFail("Raw baseline must not request cleanup")
            throw URLError(.badURL)
        }
        let service = TranscriptionService(transport: transport)
        let inputs = [
            "Use super base with cloud code; ask codecs about the cell.",
            "Audio codecs; put it in the cell.",
            "  Cafe\u{0301} 🚀 super base\r\n`cloud code`  ",
            ""
        ]
        for input in inputs {
            let result = await controller.processTranscriptOrRaw(
                rawText: input, apiKey: nil, service: service, context: "agent-first-baseline"
            )
            // Swift String equality treats canonically equivalent Unicode as equal.
            // Comparing UTF-8 catches otherwise invisible normalization/whitespace edits.
            XCTAssertEqual(Array(result.text.utf8), Array(input.utf8))
            XCTAssertFalse(result.cleanupFailed)
        }
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testLocalCorrectionReleasePerformanceGate() async throws {
        struct Request: Decodable {
            let input: String
            let rules: [LocalCorrectionRule]
        }
        struct Configuration: Decodable {
            let reportPath: String
            let commit: String
            let buildConfiguration: String

            enum CodingKeys: String, CodingKey {
                case reportPath = "report_path"
                case commit
                case buildConfiguration = "build_configuration"
            }
        }
        let workloadsPath = "/tmp/foil-local-correction-benchmark-workloads.json"
        let configurationPath = "/tmp/foil-local-correction-benchmark-configuration.json"
        guard FileManager.default.fileExists(atPath: configurationPath) else {
            throw XCTSkip("Run through scripts/test-local-correction-performance.sh")
        }
        let benchmarkConfiguration = try JSONDecoder().decode(
            Configuration.self,
            from: Data(contentsOf: URL(fileURLWithPath: configurationPath))
        )
        XCTAssertEqual(benchmarkConfiguration.buildConfiguration, "Release")
        let workloadData = try Data(contentsOf: URL(fileURLWithPath: workloadsPath))
        let requests = try JSONDecoder().decode([String: Request].self, from: workloadData)
        let transport = ControllerStubTransport { _ in
            XCTFail("Local correction performance gate must not request a provider")
            throw URLError(.badURL)
        }
        let service = TranscriptionService(transport: transport)
        var scenarios: [String: [String: Any]] = [:]
        for name in ["normal", "maximum"] {
            let request = try XCTUnwrap(requests[name])
            var compile: [Double] = []
            var warm: [Double] = []
            var cold: [Double] = []

            for _ in 0..<50 {
                let started = DispatchTime.now().uptimeNanoseconds
                _ = try LocalCorrectionEngine.compile(request.rules)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                compile.append(elapsed)
            }

            let scenarioDirectory = keychainStorageDirectory
                .appendingPathComponent("benchmark-\(name)", isDirectory: true)
            let store = LocalCorrectionStore(
                fileURL: scenarioDirectory.appendingPathComponent("local-corrections.json")
            )
            _ = try store.save(rules: request.rules, isEnabled: true, expectedRevision: 0)
            var lastOutput = ""

            for _ in 0..<50 {
                let coldState = AppState(localCorrectionStore: store)
                coldState.setCleanupGroups([CleanupGroup.defaultGroup(processingMode: .raw)])
                let coldController = TranscriptionController(
                    transcriptionService: service,
                    appState: coldState
                )
                let started = DispatchTime.now().uptimeNanoseconds
                let result = await coldController.processTranscriptOrRaw(
                    rawText: request.input,
                    apiKey: nil,
                    service: service,
                    context: "local-correction-benchmark"
                )
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                XCTAssertEqual(result.localReplacementCount > 0, true)
                cold.append(elapsed)
                lastOutput = result.text
            }

            let warmState = AppState(localCorrectionStore: store)
            warmState.setCleanupGroups([CleanupGroup.defaultGroup(processingMode: .raw)])
            let warmController = TranscriptionController(
                transcriptionService: service,
                appState: warmState
            )
            for _ in 0..<1_000 {
                let started = DispatchTime.now().uptimeNanoseconds
                let result = await warmController.processTranscriptOrRaw(
                    rawText: request.input,
                    apiKey: nil,
                    service: service,
                    context: "local-correction-benchmark"
                )
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                XCTAssertEqual(result.localReplacementCount > 0, true)
                warm.append(elapsed)
                lastOutput = result.text
            }

            let outputDigest = SHA256.hash(data: Data(lastOutput.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            scenarios[name] = [
                "rule_count": request.rules.count,
                "input_bytes": request.input.utf8.count,
                "output_sha256": outputDigest,
                "cold_compile_ms": compile,
                "cold_controller_ms": cold,
                "warm_controller_ms": warm
            ]
        }
        XCTAssertEqual(transport.requests.count, 0)
#if arch(arm64)
        let architecture = "arm64"
#elseif arch(x86_64)
        let architecture = "x86_64"
#else
        let architecture = "unknown"
#endif
        let receipt: [String: Any] = [
            "schema_version": 1,
            "boundary": "TranscriptionController.processTranscriptOrRaw",
            "build_configuration": "Release",
            "hardware": "\(architecture) · \(ProcessInfo.processInfo.processorCount) logical CPUs",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "commit": benchmarkConfiguration.commit,
            "seed": 20260914,
            "scenarios": scenarios
        ]
        let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
        try data.write(
            to: URL(fileURLWithPath: benchmarkConfiguration.reportPath),
            options: .atomic
        )
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "local-correction-release-performance.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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

    func testRawLocalCorrectionAppliesWithoutCleanupRequest() async throws {
        appState.transcriptProcessingMode = .raw
        let snapshot = try appState.saveLocalCorrections(
            [localRule(id: "supabase", source: "super base", replacement: "Supabase", group: nil)],
            isEnabled: true
        )
        let transport = ControllerStubTransport { request in
            XCTFail("Local correction must not make a cleanup request: \(String(describing: request.url))")
            throw URLError(.badURL)
        }

        let result = await controller.processTranscriptOrRaw(
            rawText: "Use super base; keep `super base` literal.",
            apiKey: nil,
            service: TranscriptionService(transport: transport),
            context: "testLocalCorrection"
        )

        XCTAssertEqual(result.text, "Use Supabase; keep `super base` literal.")
        XCTAssertEqual(result.originalText, "Use super base; keep `super base` literal.")
        XCTAssertEqual(result.localCorrectionRevision, snapshot.revision)
        XCTAssertEqual(result.localReplacementCount, 1)
        XCTAssertNil(result.localCorrectionFallbackReason)
        XCTAssertFalse(result.cleanupFailed)
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testReviewedAgentAliasesCorrectExactDictationAndHistoryKeepsOriginal() async throws {
        appState.setCleanupGroups([
            CleanupGroup.defaultGroup(processingMode: .raw),
            CleanupGroup(
                id: "agents",
                name: "Agent apps",
                sortOrder: 1,
                appMatchers: [
                    CleanupAppMatcher(displayName: "Codex", bundleIdentifier: "com.openai.codex")
                ],
                processingMode: .raw
            )
        ])
        _ = try appState.saveLocalCorrections(
            [
                localRule(id: "superbase", source: "Superbase", replacement: "Supabase", group: "agents"),
                localRule(id: "super-base", source: "super base", replacement: "Supabase", group: "agents"),
                localRule(id: "codecs", source: "codecs", replacement: "Codex", group: "agents")
            ],
            isEnabled: true
        )
        let transport = ControllerStubTransport { request in
            XCTFail("Raw scoped correction must not make a cleanup request: \(String(describing: request.url))")
            throw URLError(.badURL)
        }

        let result = await controller.processTranscriptOrRaw(
            rawText: "Superbase and codecs",
            apiKey: nil,
            service: TranscriptionService(transport: transport),
            context: "reviewedAgentAliases",
            appContext: CleanupAppContext(displayName: "Codex", bundleIdentifier: "com.openai.codex")
        )
        let historyDirectory = keychainStorageDirectory.appendingPathComponent("history", isDirectory: true)
        let history = TranscriptionHistory(storageDirectory: historyDirectory)
        history.addSuccess(text: result.text, originalText: result.originalText, sourceAppName: "Codex")

        XCTAssertEqual(result.text, "Supabase and Codex")
        XCTAssertEqual(result.originalText, "Superbase and codecs")
        XCTAssertEqual(result.localReplacementCount, 2)
        XCTAssertEqual(result.cleanupGroupID, "agents")
        XCTAssertEqual(history.records.first?.text, "Supabase and Codex")
        XCTAssertEqual(history.lastRecoverableOriginalText, "Superbase and codecs")
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testOversizeLocalCorrectionInputFallsBackIntactWithoutRequest() async throws {
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        try KeychainHelper.saveCleanupApiKey("cleanup-secret", for: .customOpenAICompatibleChat)
        _ = try appState.saveLocalCorrections(
            [localRule(id: "a", source: "a", replacement: "b", group: nil)],
            isEnabled: true
        )
        let input = String(repeating: "a", count: LocalCorrectionEngine.maximumInputBytes + 1)
        let transport = ControllerStubTransport { request in
            XCTFail("Oversize local fallback must not request a provider: \(String(describing: request.url))")
            throw URLError(.badURL)
        }

        let result = await controller.processTranscriptOrRaw(
            rawText: input,
            apiKey: nil,
            service: TranscriptionService(transport: transport),
            context: "testOversizeLocalCorrection"
        )

        XCTAssertEqual(Array(result.text.utf8), Array(input.utf8))
        XCTAssertEqual(result.localReplacementCount, 0)
        XCTAssertEqual(result.localCorrectionFallbackReason, .inputTooLarge)
        XCTAssertEqual(result.processingMode, .cleanUp)
        XCTAssertNil(result.cleanupProviderID)
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testOversizeInputWithoutApplicableRuleStillUsesCleanup() async throws {
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        try KeychainHelper.saveCleanupApiKey("cleanup-secret", for: .customOpenAICompatibleChat)
        _ = try appState.saveLocalCorrections(
            [localRule(id: "other", source: "a", replacement: "b", group: "other")],
            isEnabled: true
        )
        let input = String(repeating: "a", count: LocalCorrectionEngine.maximumInputBytes + 1)
        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"choices":[{"message":{"content":"clean text"}}]}"#.utf8), response)
        }

        let result = await controller.processTranscriptOrRaw(
            rawText: input,
            apiKey: nil,
            service: TranscriptionService(transport: transport),
            context: "testOversizeWithoutApplicableRule"
        )

        XCTAssertEqual(result.text, "clean text")
        XCTAssertEqual(result.localReplacementCount, 0)
        XCTAssertNil(result.localCorrectionFallbackReason)
        XCTAssertEqual(result.cleanupProviderID, .customOpenAICompatibleChat)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testDelayedTranscriptionUsesCapturedRuleScopeAndRevisionAfterGroupDeletion() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.setCleanupGroups([
            CleanupGroup.defaultGroup(processingMode: .raw),
            CleanupGroup(
                id: "terminal",
                name: "Terminal",
                sortOrder: 1,
                appMatchers: [
                    CleanupAppMatcher(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
                ],
                processingMode: .raw
            )
        ])
        let captured = try appState.saveLocalCorrections(
            [localRule(id: "captured", source: "super base", replacement: "Captured", group: "terminal")],
            isEnabled: true
        )
        let replacementRule = localRule(id: "new", source: "super base", replacement: "New", group: nil)
        let capturedSnapshot = controller.captureProcessingSnapshot(
            appContext: CleanupAppContext(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        )
        XCTAssertTrue(appState.deleteCleanupGroup(id: "terminal"))
        let current = try appState.saveLocalCorrections(
            [replacementRule],
            isEnabled: true
        )
        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("super base".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState
        )
        controller.delegate = spy
        let audioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await controller.transcribe(
            audioURL: audioURL,
            format: .wav,
            appContext: CleanupAppContext(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
            processingSnapshot: capturedSnapshot
        )

        XCTAssertEqual(captured.revision, 1)
        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "Captured")
        XCTAssertEqual(spy.didFailCalls.count, 0)
        XCTAssertEqual(transport.requests.count, 1)

        let next = await controller.processTranscriptOrRaw(
            rawText: "super base",
            apiKey: nil,
            service: TranscriptionService(transport: transport),
            context: "nextOperation",
            appContext: CleanupAppContext(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        )
        XCTAssertEqual(next.text, "New")
        XCTAssertEqual(next.localCorrectionRevision, current.revision)
        XCTAssertEqual(next.cleanupGroupID, CleanupGroup.defaultGroupID)
    }

    func testAssignedRawCleanupGroupSkipsCleanupRequestWhenDefaultGroupCleansUp() async {
        let terminalMatcher = CleanupAppMatcher(
            displayName: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )
        appState.setCleanupGroups([
            CleanupGroup.defaultGroup(
                processingMode: .cleanUp,
                cleanupProviderID: .groq,
                cleanupModel: "default-cleanup-model"
            ),
            CleanupGroup(
                id: "terminal",
                name: "Terminal",
                sortOrder: 1,
                appMatchers: [terminalMatcher],
                processingMode: .raw,
                cleanupProviderID: .groq,
                cleanupModel: "terminal-cleanup-model"
            )
        ])
        let transport = ControllerStubTransport { request in
            XCTFail("Unexpected cleanup request to \(request.url?.absoluteString ?? "<nil>")")
            throw URLError(.badURL)
        }

        let result = await controller.processTranscriptOrRaw(
            rawText: "agent command with typos",
            apiKey: nil,
            service: TranscriptionService(transport: transport),
            context: "test",
            appContext: CleanupAppContext(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        )

        XCTAssertEqual(result.text, "agent command with typos")
        XCTAssertFalse(result.cleanupFailed)
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testAssignedCleanupGroupUsesGroupProviderModelBaseURLAndPrompt() async throws {
        try KeychainHelper.saveCleanupApiKey("cleanup-secret", for: .customOpenAICompatibleChat)
        appState.setCleanupGroups([
            CleanupGroup.defaultGroup(
                processingMode: .raw,
                cleanupProviderID: .groq,
                cleanupModel: "default-groq-model",
                customPrompt: "Default prompt should not be used"
            ),
            CleanupGroup(
                id: "messages",
                name: "Messages",
                sortOrder: 1,
                appMatchers: [
                    CleanupAppMatcher(displayName: "Messages", bundleIdentifier: "com.apple.MobileSMS")
                ],
                processingMode: .cleanUp,
                cleanupProviderID: .customOpenAICompatibleChat,
                cleanupModel: "messages-cleanup-model",
                customCleanupBaseURL: "http://127.0.0.1:11434/v1",
                customPrompt: "Messages cleanup prompt"
            )
        ])
        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cleanup-secret")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains(#""model":"messages-cleanup-model""#), body)
            XCTAssertTrue(body.contains("Messages cleanup prompt"), body)
            XCTAssertFalse(body.contains("Default prompt should not be used"), body)
            XCTAssertFalse(body.contains("default-groq-model"), body)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"choices":[{"message":{"content":"clean message"}}]}"#.utf8), response)
        }

        let result = await controller.processTranscriptOrRaw(
            rawText: "raw message",
            apiKey: nil,
            service: TranscriptionService(transport: transport),
            context: "test",
            appContext: CleanupAppContext(displayName: "Messages", bundleIdentifier: "com.apple.MobileSMS")
        )

        XCTAssertEqual(result.text, "clean message")
        XCTAssertFalse(result.cleanupFailed)
        XCTAssertEqual(transport.requests.count, 1)
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

    func testSuccessfulCleanupWritesE2EReceiptWhenPathIsProvided() async throws {
        let receiptURL = keychainStorageDirectory.appendingPathComponent("cleanup-receipt.txt")
        setenv("E2E_CLEANUP_RECEIPT_PATH", receiptURL.path, 1)
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"

        let transport = ControllerStubTransport { request in
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
        let receipt = try String(contentsOf: receiptURL, encoding: .utf8)
        XCTAssertTrue(receipt.contains("status=applied"), receipt)
        XCTAssertTrue(receipt.contains("provider=custom-openai-compatible-chat"), receipt)
        XCTAssertTrue(receipt.contains("mode=cleanUp"), receipt)
        XCTAssertTrue(receipt.contains("model=qwen2.5:7b"), receipt)
        XCTAssertTrue(receipt.contains("input_length=8"), receipt)
        XCTAssertTrue(receipt.contains("output_length=10"), receipt)
    }

    func testCleanupReceiptMeasuresLocallyCorrectedRequestAndSuccessfulOutput() async throws {
        let receiptURL = keychainStorageDirectory.appendingPathComponent("corrected-cleanup-receipt.txt")
        setenv("E2E_CLEANUP_RECEIPT_PATH", receiptURL.path, 1)
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"
        _ = try appState.saveLocalCorrections(
            [localRule(id: "expanded", source: "raw", replacement: "expanded", group: nil)],
            isEnabled: true
        )
        let transport = ControllerStubTransport { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("expanded text"), body)
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
        let receipt = try String(contentsOf: receiptURL, encoding: .utf8)
        XCTAssertTrue(receipt.contains("input_length=13"), receipt)
        XCTAssertTrue(receipt.contains("output_length=10"), receipt)
    }

    func testActiveCleanupProfileUsesUnifiedPromptAndReceiptMode() async throws {
        let receiptURL = keychainStorageDirectory.appendingPathComponent("cleanup-profile-receipt.txt")
        setenv("E2E_CLEANUP_RECEIPT_PATH", receiptURL.path, 1)
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"

        let transport = ControllerStubTransport { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("Clean up the transcript"), body)
            XCTAssertTrue(body.contains("Turn clearly enumerated spoken points into numbered or bulleted lists when that structure is obvious"), body)
            XCTAssertTrue(body.contains("Remove obvious filler, stutters, repeated words, and false starts"), body)
            XCTAssertTrue(body.contains("launch checklist then assign follow ups"), body)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"choices":[{"message":{"content":"Confirm checklist, then assign follow ups."}}]}"#.utf8), response)
        }

        let result = await controller.processTranscriptOrRaw(
            rawText: "launch checklist then assign follow ups",
            apiKey: nil,
            service: TranscriptionService(transport: transport),
            context: "test"
        )

        XCTAssertEqual(result.text, "Confirm checklist, then assign follow ups.")
        XCTAssertFalse(result.cleanupFailed)
        let receipt = try String(contentsOf: receiptURL, encoding: .utf8)
        XCTAssertTrue(receipt.contains("mode=cleanUp"), receipt)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testFailedCleanupWritesE2EReceiptWhenPathIsProvided() async throws {
        let receiptURL = keychainStorageDirectory.appendingPathComponent("cleanup-failed-receipt.txt")
        setenv("E2E_CLEANUP_RECEIPT_PATH", receiptURL.path, 1)
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"

        let transport = ControllerStubTransport { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data("unauthorized".utf8), response)
        }

        let result = await controller.processTranscriptOrRaw(
            rawText: "raw text",
            apiKey: nil,
            service: TranscriptionService(transport: transport),
            context: "test"
        )

        XCTAssertEqual(result.text, "raw text")
        XCTAssertTrue(result.cleanupFailed)
        let receipt = try String(contentsOf: receiptURL, encoding: .utf8)
        XCTAssertTrue(receipt.contains("status=failed"), receipt)
        XCTAssertTrue(receipt.contains("provider=custom-openai-compatible-chat"), receipt)
        XCTAssertTrue(receipt.contains("mode=cleanUp"), receipt)
        XCTAssertTrue(receipt.contains("error=Invalid API key"), receipt)
    }

    func testFailedCleanupReceiptMeasuresLocallyCorrectedRequestAndFallback() async throws {
        let receiptURL = keychainStorageDirectory.appendingPathComponent("corrected-cleanup-failed-receipt.txt")
        setenv("E2E_CLEANUP_RECEIPT_PATH", receiptURL.path, 1)
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"
        _ = try appState.saveLocalCorrections(
            [localRule(id: "expanded", source: "raw", replacement: "expanded", group: nil)],
            isEnabled: true
        )
        let transport = ControllerStubTransport { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data("unauthorized".utf8), response)
        }

        let result = await controller.processTranscriptOrRaw(
            rawText: "raw text",
            apiKey: nil,
            service: TranscriptionService(transport: transport),
            context: "test"
        )

        XCTAssertEqual(result.text, "expanded text")
        XCTAssertTrue(result.cleanupFailed)
        let receipt = try String(contentsOf: receiptURL, encoding: .utf8)
        XCTAssertTrue(receipt.contains("input_length=13"), receipt)
        XCTAssertTrue(receipt.contains("output_length=13"), receipt)
    }

    func testCleanupRequestIncludesCustomPromptAndPreferredTermsFromAppState() async {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"
        appState.setCustomPrompt("Preserve the speaker style.", for: .cleanUp)
        appState.preferredTermsText = "Supabase\nVercel"
        appState.addVocabularyCorrection(writtenAs: "super base", correctVersion: "Supabase")

        let transport = ControllerStubTransport { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("Preserve the speaker style."), body)
            XCTAssertTrue(body.contains("If the transcript says \\\"super base\\\", use \\\"Supabase\\\"."), body)
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

    func testRecleanTranscriptUsesNewlySavedVocabularyCorrection() async {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"
        appState.addVocabularyCorrection(writtenAs: "super base", correctVersion: "Supabase")

        let transport = ControllerStubTransport { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("If the transcript says \\\"super base\\\", use \\\"Supabase\\\"."), body)
            XCTAssertTrue(body.contains("please clean super base"), body)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"choices":[{"message":{"content":"please clean Supabase"}}]}"#.utf8), response)
        }

        let result = await controller.recleanTranscript(
            rawText: "please clean super base",
            service: TranscriptionService(transport: transport)
        )

        XCTAssertEqual(result.text, "please clean Supabase")
        XCTAssertFalse(result.cleanupFailed)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testRecleanTranscriptDoesNotReapplyLocalRulesToFinalText() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"
        let correction = try XCTUnwrap(
            appState.addVocabularyCorrection(writtenAs: "Supabase", correctVersion: "WRONG SECOND PASS")
        )
        _ = try appState.setVocabularyCorrectionLocalScope(id: correction.id, groupID: nil)
        _ = try appState.setLocalCorrectionsEnabled(true)

        let transport = ControllerStubTransport { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let messages = body?["messages"] as? [[String: Any]]
            XCTAssertEqual(messages?.last?["content"] as? String, "already says Supabase")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"choices":[{"message":{"content":"still says Supabase"}}]}"#.utf8), response)
        }

        let result = await controller.recleanTranscript(
            rawText: "already says Supabase",
            service: TranscriptionService(transport: transport)
        )

        XCTAssertEqual(result.text, "still says Supabase")
        XCTAssertEqual(result.localReplacementCount, 0)
        XCTAssertEqual(result.localCorrectionFallbackReason, .processingDisabled)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testHistoryTransformUsesSelectedCleanupProviderAndVocabularyContext() async {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.transcriptProcessingMode = .raw
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"
        appState.addVocabularyCorrection(writtenAs: "super base", correctVersion: "Supabase")
        appState.preferredTermsText = "Supabase"

        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("Polish this transcript into clear, natural writing."), body)
            XCTAssertTrue(body.contains("If the transcript says \\\"super base\\\", use \\\"Supabase\\\"."), body)
            XCTAssertTrue(body.contains("Preferred terms"), body)
            XCTAssertTrue(body.contains("please polish super base"), body)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"choices":[{"message":{"content":"please polish Supabase"}}]}"#.utf8), response)
        }

        let result = await controller.transformTranscript(
            rawText: "please polish super base",
            transformKind: .polish,
            service: TranscriptionService(transport: transport),
            context: "testHistoryTransform"
        )

        XCTAssertEqual(result.text, "please polish Supabase")
        XCTAssertFalse(result.transformFailed)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testHistoryBulletizeTransformReturnsProviderBulletFormat() async {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.transcriptProcessingMode = .raw
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"

        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("Convert this transcript into concise bullet points."), body)
            XCTAssertTrue(body.contains("first talk through launch checklist then assign follow ups"), body)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (
                Data(#"{"choices":[{"message":{"content":"- Confirm launch checklist.\n- Assign follow ups."}}]}"#.utf8),
                response
            )
        }

        let result = await controller.transformTranscript(
            rawText: "first talk through launch checklist then assign follow ups",
            transformKind: .bulletize,
            service: TranscriptionService(transport: transport),
            context: "testHistoryBulletizeTransform"
        )

        XCTAssertEqual(result.text, "- Confirm launch checklist.\n- Assign follow ups.")
        XCTAssertFalse(result.transformFailed)
        XCTAssertTrue(result.text.split(separator: "\n").allSatisfy { $0.hasPrefix("- ") }, result.text)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testRecleanTranscriptFailureReturnsOriginalText() async {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"
        appState.addVocabularyCorrection(writtenAs: "super base", correctVersion: "Supabase")

        let transport = ControllerStubTransport { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("If the transcript says \\\"super base\\\", use \\\"Supabase\\\"."), body)
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"error":{"message":"server unavailable"}}"#.utf8), response)
        }

        let result = await controller.recleanTranscript(
            rawText: "please clean super base",
            service: TranscriptionService(transport: transport)
        )

        XCTAssertEqual(result.text, "please clean super base")
        XCTAssertTrue(result.cleanupFailed)
        XCTAssertEqual(transport.requests.count, 1)
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
        appState.transcriptProcessingMode = .cleanUp
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

    func testTranscriptionFailureReturnsCapturedAppContextForRetryPersistence() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        let audioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let context = CleanupAppContext(
            displayName: "Renamed Terminal",
            bundleIdentifier: "com.apple.Terminal",
            appPath: "/System/Applications/Utilities/Terminal.app"
        )
        let transport = ControllerStubTransport { _ in throw URLError(.notConnectedToInternet) }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState
        )
        controller.delegate = spy

        await controller.transcribe(audioURL: audioURL, format: .wav, appContext: context)

        XCTAssertEqual(spy.didFailCalls.count, 1)
        XCTAssertEqual(spy.didFailCalls.first?.appContext, context)
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

    func testPracticeUsesTranscriptionEvenWhenMockEnabledAndSkipsCleanupAndMetrics() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.onboardingPracticeActive = true
        appState.mockTranscriptionEnabled = true
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        let usageStore = UsageEventStore(storageDirectory: temporaryUsageDirectory())
        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("My practice phrase.".utf8), response)
        }
        controller = TranscriptionController(transcriptionService: TranscriptionService(transport: transport), appState: appState, usageEventStore: usageStore)
        controller.delegate = spy
        let audio = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audio) }
        await controller.transcribe(audioURL: audio, format: .wav)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "My practice phrase.")
        XCTAssertTrue(usageStore.events.isEmpty)
    }

    func testCancelledPracticeDeletesAudioAndDoesNotProduceSuccess() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.onboardingPracticeActive = true
        let transport = ControllerStubTransport { _ in throw CancellationError() }
        controller = TranscriptionController(transcriptionService: TranscriptionService(transport: transport), appState: appState)
        controller.delegate = spy
        let audio = try temporaryAudioFile()
        await controller.transcribe(audioURL: audio, format: .wav)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertTrue(spy.didTranscribeCalls.isEmpty)
        XCTAssertTrue(spy.didFailCalls.isEmpty)
    }

    func testBlankAudioSentinelDoesNotReachCleanupOrSuccessfulTranscription() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.transcriptProcessingMode = .cleanUp
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/audio/transcriptions")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("  [BLANK_AUDIO]\n".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState
        )
        controller.delegate = spy

        await controller.transcribe(audioURL: tempURL, format: .wav)

        XCTAssertEqual(spy.didDetectNoRecognizableAudioCalls.count, 1)
        XCTAssertEqual(spy.didDetectNoRecognizableAudioCalls.first?.audioURL, tempURL)
        XCTAssertEqual(spy.didDetectNoRecognizableAudioCalls.first?.format, .wav)
        XCTAssertEqual(spy.didTranscribeCalls.count, 0)
        XCTAssertEqual(spy.didFailCalls.count, 0)
        XCTAssertEqual(transport.requests.count, 1, "No cleanup request should run for blank audio")
    }

    func testPunctuationOnlyProviderResponseDoesNotReachSuccessfulTranscription() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.transcriptProcessingMode = .cleanUp
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/audio/transcriptions")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(".\n".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState
        )
        controller.delegate = spy

        await controller.transcribe(audioURL: tempURL, format: .wav)

        XCTAssertEqual(spy.didDetectNoRecognizableAudioCalls.count, 1)
        XCTAssertEqual(spy.didTranscribeCalls.count, 0)
        XCTAssertEqual(spy.didFailCalls.count, 0)
        XCTAssertEqual(transport.requests.count, 1, "No cleanup request should run for punctuation-only output")
    }

    func testTranscribeUsesSourceAppContextForCleanupGroupResolution() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.setCleanupGroups([
            CleanupGroup.defaultGroup(
                processingMode: .cleanUp,
                cleanupProviderID: .customOpenAICompatibleChat,
                cleanupModel: "default-cleanup-model",
                customCleanupBaseURL: "http://127.0.0.1:11434/v1",
                customPrompt: "Default cleanup prompt"
            ),
            CleanupGroup(
                id: "terminal",
                name: "Terminal",
                sortOrder: 1,
                appMatchers: [
                    CleanupAppMatcher(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
                ],
                processingMode: .raw
            )
        ])
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/audio/transcriptions")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("terminal raw transcript".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState
        )
        controller.delegate = spy

        await controller.transcribe(
            audioURL: tempURL,
            format: .wav,
            appContext: CleanupAppContext(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        )

        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "terminal raw transcript")
        XCTAssertEqual(spy.didFailCalls.count, 0)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testTranscribeRecordsUsageEventForResolvedCleanupGroup() async throws {
        try KeychainHelper.saveCleanupApiKey("cleanup-secret", for: .customOpenAICompatibleChat)
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.setCleanupGroups([
            CleanupGroup.defaultGroup(processingMode: .raw),
            CleanupGroup(
                id: "messages",
                name: "Messages",
                sortOrder: 1,
                appMatchers: [
                    CleanupAppMatcher(displayName: "Messages", bundleIdentifier: "com.apple.MobileSMS")
                ],
                processingMode: .cleanUp,
                cleanupProviderID: .customOpenAICompatibleChat,
                cleanupModel: "messages-cleanup-model",
                customCleanupBaseURL: "http://127.0.0.1:11434/v1",
                customPrompt: "Messages cleanup prompt"
            )
        ])
        let usageStore = UsageEventStore(storageDirectory: temporaryUsageDirectory())
        let transport = ControllerStubTransport { request in
            if request.url?.absoluteString == "http://127.0.0.1:8080/v1/audio/transcriptions" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data("hello from messages".utf8), response)
            }
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
            let body = #"{"choices":[{"message":{"content":"Hello from Messages."}}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState,
            usageEventStore: usageStore
        )
        controller.delegate = spy
        let tempURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await controller.transcribe(
            audioURL: tempURL,
            format: .wav,
            appContext: CleanupAppContext(displayName: "Messages", bundleIdentifier: "com.apple.MobileSMS")
        )

        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "Hello from Messages.")
        XCTAssertEqual(usageStore.events.count, 1)
        let event = try XCTUnwrap(usageStore.events.first)
        XCTAssertEqual(event.wordCount, 3)
        XCTAssertEqual(event.sourceAppName, "Messages")
        XCTAssertEqual(event.sourceBundleIdentifier, "com.apple.MobileSMS")
        XCTAssertEqual(event.cleanupGroupID, "messages")
        XCTAssertEqual(event.cleanupGroupName, "Messages")
        XCTAssertEqual(event.processingMode, .cleanUp)
        XCTAssertEqual(event.cleanupProviderID, .customOpenAICompatibleChat)
        XCTAssertEqual(event.cleanupModel, "messages-cleanup-model")
        XCTAssertFalse(event.cleanupFailed)
        XCTAssertEqual(event.outcome, .success)
    }

    func testTranscribeRecordsCleanupFailedFallbackUsageEvent() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.setCleanupGroups([
            CleanupGroup.defaultGroup(
                processingMode: .cleanUp,
                cleanupProviderID: .customOpenAICompatibleChat,
                cleanupModel: "fallback-cleanup-model",
                customCleanupBaseURL: "http://127.0.0.1:11434/v1"
            )
        ])
        let correction = try XCTUnwrap(
            appState.addVocabularyCorrection(writtenAs: "super base", correctVersion: "Supabase")
        )
        _ = try appState.setVocabularyCorrectionLocalScope(id: correction.id, groupID: nil)
        _ = try appState.setLocalCorrectionsEnabled(true)
        let usageStore = UsageEventStore(storageDirectory: temporaryUsageDirectory())
        let transport = ControllerStubTransport { request in
            if request.url?.absoluteString == "http://127.0.0.1:8080/v1/audio/transcriptions" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data("super base fallback transcript".utf8), response)
            }
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            XCTAssertTrue(body.contains("Supabase fallback transcript"), body)
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data("cleanup failed".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState,
            usageEventStore: usageStore
        )
        controller.delegate = spy
        let tempURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await controller.transcribe(audioURL: tempURL, format: .wav)

        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "Supabase fallback transcript")
        XCTAssertEqual(spy.didTranscribeCalls.first?.originalText, "super base fallback transcript")
        XCTAssertEqual(spy.didTranscribeCalls.first?.cleanupFailed, true)
        let event = try XCTUnwrap(usageStore.events.first)
        XCTAssertTrue(event.cleanupFailed)
        XCTAssertEqual(event.outcome, .cleanupFailedFallback)
        XCTAssertEqual(event.cleanupProviderID, .customOpenAICompatibleChat)
        XCTAssertEqual(event.cleanupModel, "fallback-cleanup-model")
        XCTAssertEqual(event.processingMode, .cleanUp)
        XCTAssertEqual(event.wordCount, 3)
    }

    func testTranscribeRecordsRawUsageEventWithoutCleanupProviderRequest() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.setCleanupGroups([
            CleanupGroup.defaultGroup(processingMode: .cleanUp),
            CleanupGroup(
                id: "terminal",
                name: "Terminal",
                sortOrder: 1,
                appMatchers: [
                    CleanupAppMatcher(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
                ],
                processingMode: .raw
            )
        ])
        let usageStore = UsageEventStore(storageDirectory: temporaryUsageDirectory())
        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/audio/transcriptions")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("terminal raw words".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState,
            usageEventStore: usageStore
        )
        controller.delegate = spy
        let tempURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await controller.transcribe(
            audioURL: tempURL,
            format: .wav,
            appContext: CleanupAppContext(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        )

        XCTAssertEqual(transport.requests.count, 1)
        let event = try XCTUnwrap(usageStore.events.first)
        XCTAssertEqual(event.processingMode, .raw)
        XCTAssertNil(event.cleanupProviderID)
        XCTAssertNil(event.cleanupModel)
        XCTAssertEqual(event.cleanupGroupID, "terminal")
        XCTAssertEqual(event.wordCount, 3)
    }

    func testUsageTopAppCanDriveCleanupGroupAssignmentAndLaterRouting() async throws {
        try KeychainHelper.saveCleanupApiKey("cleanup-secret", for: .customOpenAICompatibleChat)
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.setCleanupGroups([
            CleanupGroup.defaultGroup(processingMode: .raw),
            CleanupGroup(
                id: "terminal",
                name: "Terminal",
                sortOrder: 1,
                processingMode: .raw
            )
        ])
        let usageStore = UsageEventStore(storageDirectory: temporaryUsageDirectory())
        var transcriptionResponses = [
            "terminal first transcript",
            "terminal second transcript"
        ]
        let transport = ControllerStubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/audio/transcriptions")
            let text = transcriptionResponses.removeFirst()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(text.utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState,
            usageEventStore: usageStore
        )
        controller.delegate = spy
        let firstAudioURL = try temporaryAudioFile()
        let secondAudioURL = try temporaryAudioFile()
        defer {
            try? FileManager.default.removeItem(at: firstAudioURL)
            try? FileManager.default.removeItem(at: secondAudioURL)
        }
        let terminalContext = CleanupAppContext(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")

        await controller.transcribe(audioURL: firstAudioURL, format: .wav, appContext: terminalContext)

        let topApp = try XCTUnwrap(usageStore.topApps(limit: 1).first)
        XCTAssertEqual(topApp.displayName, "Terminal")
        XCTAssertEqual(topApp.bundleIdentifier, "com.apple.Terminal")
        appState.addAppMatcher(
            CleanupAppMatcher(displayName: topApp.displayName, bundleIdentifier: topApp.bundleIdentifier),
            toCleanupGroupID: "terminal"
        )
        XCTAssertTrue(appState.updateCleanupGroup(id: CleanupGroup.defaultGroupID) { group in
            group.processingMode = .cleanUp
            group.cleanupProviderID = .customOpenAICompatibleChat
            group.cleanupModel = "default-cleanup-model"
            group.customCleanupBaseURL = "http://127.0.0.1:11434/v1"
        })

        await controller.transcribe(audioURL: secondAudioURL, format: .wav, appContext: terminalContext)

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(spy.didFailCalls.count, 0)
        XCTAssertEqual(spy.didTranscribeCalls.map(\.text), ["terminal first transcript", "terminal second transcript"])
        XCTAssertEqual(usageStore.events.count, 2)
        let secondEvent = try XCTUnwrap(usageStore.events.first)
        XCTAssertEqual(secondEvent.sourceAppName, "Terminal")
        XCTAssertEqual(secondEvent.sourceBundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(secondEvent.cleanupGroupID, "terminal")
        XCTAssertEqual(secondEvent.cleanupGroupName, "Terminal")
        XCTAssertEqual(secondEvent.processingMode, .raw)
        XCTAssertNil(secondEvent.cleanupProviderID)
        XCTAssertNil(secondEvent.cleanupModel)
    }

    func testTranscribeDoesNotRecordUsageWhenMetricsDisabled() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.usageMetricsEnabled = false
        let usageStore = UsageEventStore(storageDirectory: temporaryUsageDirectory())
        let transport = ControllerStubTransport { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("disabled metrics transcript".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState,
            usageEventStore: usageStore
        )
        controller.delegate = spy
        let tempURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await controller.transcribe(audioURL: tempURL, format: .wav)

        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "disabled metrics transcript")
        XCTAssertTrue(usageStore.events.isEmpty)
    }

    func testUsageStoreFailureDoesNotBlockSuccessfulTranscription() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        let blockedFile = keychainStorageDirectory.appendingPathComponent("not-a-directory")
        try Data([0x00]).write(to: blockedFile)
        let usageStore = UsageEventStore(storageDirectory: blockedFile)
        let transport = ControllerStubTransport { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("still returns transcript".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState,
            usageEventStore: usageStore
        )
        controller.delegate = spy
        let tempURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await controller.transcribe(audioURL: tempURL, format: .wav)

        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "still returns transcript")
        XCTAssertEqual(spy.didFailCalls.count, 0)
        XCTAssertEqual(usageStore.lastError, .saveFailed)
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
            sourceAppName: nil,
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

    func testRetryPreservesSourceAppScopeForLocalCorrections() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.setCleanupGroups([
            CleanupGroup.defaultGroup(processingMode: .raw),
            CleanupGroup(
                id: "terminal",
                name: "Terminal",
                sortOrder: 1,
                appMatchers: [CleanupAppMatcher(
                    displayName: "Terminal",
                    bundleIdentifier: "com.apple.Terminal"
                )],
                processingMode: .raw
            )
        ])
        _ = try appState.saveLocalCorrections(
            [localRule(id: "scoped", source: "codecs", replacement: "Codex", group: "terminal")],
            isEnabled: true
        )
        let tempURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let record = TranscriptionRecord(
            id: UUID(),
            timestamp: Date(),
            sourceAppName: "Renamed Terminal",
            sourceAppBundleIdentifier: "com.apple.Terminal",
            outcome: .failure(error: "previous failure", audioFileURL: tempURL)
        )
        let transport = ControllerStubTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("open codecs".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState
        )
        controller.delegate = spy

        await controller.retryTranscription(record: record)

        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "open Codex")
        XCTAssertEqual(spy.didFailCalls.count, 0)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testRetryWithoutSourceAppAppliesOnlyGlobalLocalCorrections() async throws {
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.setCleanupGroups([
            CleanupGroup.defaultGroup(processingMode: .raw)
        ])
        _ = try appState.saveLocalCorrections(
            [
                localRule(id: "global", source: "codecs", replacement: "Codex", group: nil),
                localRule(
                    id: "unassigned",
                    source: "super base",
                    replacement: "Supabase",
                    group: CleanupGroup.defaultGroupID
                )
            ],
            isEnabled: true
        )
        let tempURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let record = TranscriptionRecord(
            id: UUID(),
            timestamp: Date(),
            sourceAppName: nil,
            outcome: .failure(error: "previous failure", audioFileURL: tempURL)
        )
        let transport = ControllerStubTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("open codecs and super base".utf8), response)
        }
        controller = TranscriptionController(
            transcriptionService: TranscriptionService(transport: transport),
            appState: appState
        )
        controller.delegate = spy

        await controller.retryTranscription(record: record)

        XCTAssertEqual(spy.didTranscribeCalls.first?.text, "open Codex and super base")
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
            sourceAppName: nil,
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

    private func temporaryAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data([0x00]).write(to: url)
        return url
    }

    private func temporaryUsageDirectory() -> URL {
        keychainStorageDirectory
            .appendingPathComponent("usage-\(UUID().uuidString)", isDirectory: true)
    }

    private func localRule(
        id: String,
        source: String,
        replacement: String,
        group: String?
    ) -> LocalCorrectionRule {
        LocalCorrectionRule(
            id: id,
            source: source,
            replacement: replacement,
            group: group,
            enabled: true,
            caseSensitive: false
        )
    }
}

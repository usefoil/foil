import Darwin
import XCTest
@testable import Foil

final class TranscriptionServiceTests: XCTestCase {
    private final class StubTransport: TranscriptionTransport {
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

    private static func makeAudioFile(name: String = UUID().uuidString, bytes: [UInt8] = [0x52, 0x49, 0x46, 0x46]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension("wav")
        try Data(bytes).write(to: url)
        return url
    }

    private static func httpResponse(statusCode: Int, url: URL = URL(string: "https://api.groq.com")!) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private static func apiErrorJSON(message: String, type: String? = nil, code: String? = nil) -> Data {
        var error: [String: Any] = ["message": message]
        if let type { error["type"] = type }
        if let code { error["code"] = code }
        let payload: [String: Any] = ["error": error]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - Providers

    func testGroqProviderBuildsExpectedDefaultEndpoints() {
        let provider = TranscriptionProvider.groq

        XCTAssertEqual(
            provider.audioTranscriptionsEndpoint.absoluteString,
            "https://api.groq.com/openai/v1/audio/transcriptions"
        )
        XCTAssertEqual(
            provider.chatCompletionsEndpoint.absoluteString,
            "https://api.groq.com/openai/v1/chat/completions"
        )
        XCTAssertEqual(
            provider.modelsEndpoint.absoluteString,
            "https://api.groq.com/openai/v1/models"
        )
        XCTAssertEqual(provider.transcriptionModel, "whisper-large-v3-turbo")
        XCTAssertTrue(provider.requiresAPIKey)
        XCTAssertTrue(provider.supportsModelValidation)
    }

    func testOpenAICompatibleProviderBuildsEndpointsFromCustomBaseURL() {
        let provider = TranscriptionProvider.openAICompatible(
            baseURL: URL(string: "http://127.0.0.1:8080/v1")!,
            model: "whisper-1"
        )

        XCTAssertEqual(
            provider.audioTranscriptionsEndpoint.absoluteString,
            "http://127.0.0.1:8080/v1/audio/transcriptions"
        )
        XCTAssertEqual(
            provider.chatCompletionsEndpoint.absoluteString,
            "http://127.0.0.1:8080/v1/chat/completions"
        )
        XCTAssertEqual(
            provider.modelsEndpoint.absoluteString,
            "http://127.0.0.1:8080/v1/models"
        )
        XCTAssertEqual(provider.transcriptionModel, "whisper-1")
        XCTAssertFalse(provider.requiresAPIKey)
        XCTAssertFalse(provider.supportsModelValidation)
    }

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

    func testOpenAICleanupProviderBuildsExpectedEndpointsAndDefaultModel() {
        let provider = TranscriptCleanupProvider.openAI(model: "")

        XCTAssertEqual(provider.id, .openAI)
        XCTAssertEqual(provider.displayName, "OpenAI")
        XCTAssertEqual(provider.chatCompletionsEndpoint?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(provider.responsesEndpoint?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(provider.modelsEndpoint?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(provider.model, "gpt-5.4-mini")
        XCTAssertTrue(provider.requiresAPIKey)
    }

    func testNoCleanupProviderHasNoEndpoints() {
        let provider = TranscriptCleanupProvider.none

        XCTAssertEqual(provider.id, .none)
        XCTAssertEqual(provider.displayName, "None")
        XCTAssertNil(provider.chatCompletionsEndpoint)
        XCTAssertNil(provider.responsesEndpoint)
        XCTAssertNil(provider.modelsEndpoint)
    }

    func testLocalWhisperPresetDefinesExpectedDefaults() {
        let preset = TranscriptionProviderPreset.localWhisperCPP

        XCTAssertEqual(preset.id, .localWhisperCPP)
        XCTAssertEqual(preset.displayName, "Local whisper.cpp")
        XCTAssertEqual(preset.providerID, .openAICompatible)
        XCTAssertEqual(preset.baseURL?.absoluteString, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(preset.model, "whisper-1")
        XCTAssertFalse(preset.requiresAPIKey)
        XCTAssertFalse(preset.supportsTranscriptProcessing)
        XCTAssertFalse(preset.isEditable)
    }

    func testOpenAIWhisperProviderIDsExistForDedicatedCloudPreset() {
        XCTAssertNotNil(TranscriptionProviderID(rawValue: "openai"))
        XCTAssertNotNil(TranscriptionProviderPresetID(rawValue: "openai-whisper"))
    }

    func testOpenAIWhisperPresetDefinesCloudEndpointAndRequiresKey() {
        let preset = TranscriptionProviderPreset.openAIWhisper
        let provider = TranscriptionProvider.openAIWhisper

        XCTAssertEqual(preset.id, .openAIWhisper)
        XCTAssertEqual(preset.displayName, "OpenAI Whisper")
        XCTAssertEqual(preset.providerID, .openAI)
        XCTAssertEqual(preset.baseURL?.absoluteString, "https://api.openai.com/v1")
        XCTAssertEqual(preset.model, "whisper-1")
        XCTAssertTrue(preset.requiresAPIKey)
        XCTAssertFalse(preset.supportsTranscriptProcessing)
        XCTAssertFalse(preset.isEditable)

        XCTAssertEqual(provider.id, .openAI)
        XCTAssertEqual(provider.displayName, "OpenAI Whisper")
        XCTAssertEqual(provider.audioTranscriptionsEndpoint.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(provider.modelsEndpoint.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(provider.transcriptionModel, "whisper-1")
        XCTAssertTrue(provider.requiresAPIKey)
        XCTAssertTrue(provider.supportsModelValidation)
        XCTAssertFalse(provider.supportsTranscriptProcessing)
    }

    func testLocalWhisperSetupModelsCoverApprovedSourceVerifiedOptions() {
        let options = LocalWhisperSetupModel.all

        XCTAssertEqual(
            options.map(\.id),
            [.tinyEN, .baseEN, .smallEN, .mediumEN, .largeV3Turbo, .largeV3]
        )
        XCTAssertEqual(LocalWhisperSetupModel.recommendedDefaultID, .baseEN)
        XCTAssertEqual(options.map(\.downloadIdentifier), [
            "tiny.en",
            "base.en",
            "small.en",
            "medium.en",
            "large-v3-turbo",
            "large-v3"
        ])
        XCTAssertEqual(options.map(\.ggmlFilename), [
            "ggml-tiny.en.bin",
            "ggml-base.en.bin",
            "ggml-small.en.bin",
            "ggml-medium.en.bin",
            "ggml-large-v3-turbo.bin",
            "ggml-large-v3.bin"
        ])
        XCTAssertEqual(LocalWhisperSetupModel.option(id: .baseEN).languageScope, "English-only")
        XCTAssertEqual(LocalWhisperSetupModel.option(id: .largeV3Turbo).languageScope, "Multilingual")
    }

    func testLocalWhisperSetupCommandsUseSelectedModelFile() {
        let model = LocalWhisperSetupModel.option(id: .smallEN)
        let commands = LocalWhisperSetupCommands(model: model)

        XCTAssertTrue(commands.cloneCommand.contains("mkdir -p ~/Developer"))
        XCTAssertTrue(commands.cloneCommand.contains("git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git ~/Developer/whisper.cpp"))
        XCTAssertTrue(commands.buildCommand.contains("cmake -B build -DWHISPER_BUILD_TESTS=OFF"))
        XCTAssertTrue(commands.buildCommand.contains("cmake --build build -j --config Release"))
        XCTAssertTrue(commands.downloadCommand.contains("sh ./models/download-ggml-model.sh small.en"))
        XCTAssertTrue(commands.startServerCommand.contains("--host 127.0.0.1"))
        XCTAssertTrue(commands.startServerCommand.contains("--port 8080"))
        XCTAssertTrue(commands.startServerCommand.contains("--model ~/Developer/whisper.cpp/models/ggml-small.en.bin"))
        XCTAssertFalse(commands.startServerCommand.contains("--language"))
        XCTAssertTrue(commands.startServerCommand.contains("--inference-path /v1/audio/transcriptions"))
        XCTAssertTrue(commands.startServerCommand.contains("--convert"))
        XCTAssertTrue(commands.startServerCommand.contains("--no-timestamps"))
        XCTAssertEqual(commands.localBaseURL, "http://127.0.0.1:8080/v1")
    }

    func testLocalWhisperSetupCommandsExposeExpandedProcessLaunchArguments() {
        let model = LocalWhisperSetupModel.option(id: .baseEN)
        let commands = LocalWhisperSetupCommands(model: model, installPath: "~/Developer/whisper.cpp")

        XCTAssertEqual(
            commands.serverBinaryURL.path,
            "\(NSHomeDirectory())/Developer/whisper.cpp/build/bin/whisper-server"
        )
        XCTAssertEqual(
            commands.modelFileURL.path,
            "\(NSHomeDirectory())/Developer/whisper.cpp/models/ggml-base.en.bin"
        )
        XCTAssertEqual(commands.startServerArguments, [
            "--host", "127.0.0.1",
            "--port", "8080",
            "--model", "\(NSHomeDirectory())/Developer/whisper.cpp/models/ggml-base.en.bin",
            "--inference-path", "/v1/audio/transcriptions",
            "--convert",
            "--no-timestamps"
        ])
        XCTAssertFalse(commands.startServerArguments.joined(separator: " ").contains("~"))
        XCTAssertEqual(commands.modelsEndpointURL.absoluteString, "http://127.0.0.1:8080/v1/models")
    }

    @MainActor
    func testLocalWhisperServerControllerReportsAlreadyRunningBeforeCheckingFiles() async {
        let model = LocalWhisperSetupModel.option(id: .baseEN)
        let commands = LocalWhisperSetupCommands(model: model, installPath: "/tmp/foil-missing-whisper-\(UUID().uuidString)")
        let controller = LocalWhisperServerController { _ in true }

        let result = await controller.start(commands: commands)

        XCTAssertEqual(result, .alreadyRunning("http://127.0.0.1:8080/v1"))
    }

    @MainActor
    func testLocalWhisperServerControllerReportsMissingBinary() async throws {
        let installURL = try Self.makeTemporaryWhisperInstall()
        defer { try? FileManager.default.removeItem(at: installURL) }
        let model = LocalWhisperSetupModel.option(id: .baseEN)
        let commands = LocalWhisperSetupCommands(model: model, installPath: installURL.path)
        let controller = LocalWhisperServerController { _ in false }

        let result = await controller.start(commands: commands)

        XCTAssertEqual(result, .missingBinary(commands.serverBinaryURL.path))
    }

    @MainActor
    func testLocalWhisperServerControllerReportsMissingModel() async throws {
        let installURL = try Self.makeTemporaryWhisperInstall()
        defer { try? FileManager.default.removeItem(at: installURL) }
        let model = LocalWhisperSetupModel.option(id: .smallEN)
        let commands = LocalWhisperSetupCommands(model: model, installPath: installURL.path)
        try Self.writeExecutableStub(at: commands.serverBinaryURL)
        let controller = LocalWhisperServerController { _ in false }

        let result = await controller.start(commands: commands)

        XCTAssertEqual(result, .missingModel(commands.modelFileURL.path))
    }

    @MainActor
    func testLocalWhisperServerControllerReportsNonExecutableBinaryAsFailedStart() async throws {
        let installURL = try Self.makeTemporaryWhisperInstall()
        defer { try? FileManager.default.removeItem(at: installURL) }
        let model = LocalWhisperSetupModel.option(id: .baseEN)
        let commands = LocalWhisperSetupCommands(model: model, installPath: installURL.path)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: commands.serverBinaryURL)
        try Data().write(to: commands.modelFileURL)
        let controller = LocalWhisperServerController { _ in false }

        let result = await controller.start(commands: commands)

        guard case .failed(let message) = result else {
            return XCTFail("Expected failed start, got \(result)")
        }
        XCTAssertTrue(message.contains("not executable"))
        XCTAssertTrue(message.contains(commands.serverBinaryURL.path))
    }

    func testLocalWhisperSetupExplanationSeparatesAPIModelFromServerModelFile() {
        let model = LocalWhisperSetupModel.option(id: .largeV3Turbo)
        let commands = LocalWhisperSetupCommands(model: model)

        XCTAssertTrue(commands.modelSelectionExplanation.contains("whisper-1"))
        XCTAssertTrue(commands.modelSelectionExplanation.contains("--model ggml-large-v3-turbo.bin"))
        XCTAssertFalse(commands.modelSelectionExplanation.contains("changes the Foil model picker"))
    }

    private static func makeTemporaryWhisperInstall() throws -> URL {
        let installURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilWhisperInstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: installURL.appendingPathComponent("build/bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: installURL.appendingPathComponent("models", isDirectory: true),
            withIntermediateDirectories: true
        )
        return installURL
    }

    private static func writeExecutableStub(at url: URL) throws {
        try Data("#!/bin/sh\nsleep 10\n".utf8).write(to: url)
        chmod(url.path, 0o755)
    }

    func testCustomPresetTrimsEmptyModelToWhisperOne() {
        let preset = TranscriptionProviderPreset.customOpenAICompatible(
            baseURL: URL(string: "http://localhost:9000/v1"),
            model: " "
        )

        XCTAssertEqual(preset.id, .customOpenAICompatible)
        XCTAssertEqual(preset.displayName, "Custom OpenAI-compatible")
        XCTAssertEqual(preset.model, "whisper-1")
        XCTAssertTrue(preset.isEditable)
    }

    func testMultipartBodyContainsAllFields() throws {
        let service = TranscriptionService()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let boundary = "test-boundary-123"
        let body = try TranscriptionService.buildMultipartBody(
            audioFileURL: tempURL,
            model: "whisper-large-v3-turbo",
            format: .wav,
            boundary: boundary
        )
        let bodyString = String(data: body, encoding: .utf8)!

        XCTAssertTrue(bodyString.contains("--test-boundary-123\r\n"))
        XCTAssertTrue(bodyString.contains("name=\"model\"\r\n\r\nwhisper-large-v3-turbo"))
        XCTAssertTrue(bodyString.contains("name=\"response_format\"\r\n\r\ntext"))
        XCTAssertTrue(bodyString.contains("name=\"file\"; filename=\"audio.wav\""))
        XCTAssertTrue(bodyString.contains("Content-Type: audio/wav"))
        XCTAssertTrue(bodyString.contains("--test-boundary-123--"))
    }

    func testMultipartBodyM4AFormat() throws {
        let service = TranscriptionService()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio.m4a")
        try Data([0x00, 0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let body = try TranscriptionService.buildMultipartBody(
            audioFileURL: tempURL,
            model: "whisper-large-v3",
            format: .m4a,
            boundary: "b"
        )
        let bodyString = String(data: body, encoding: .utf8)!

        XCTAssertTrue(bodyString.contains("filename=\"audio.m4a\""))
        XCTAssertTrue(bodyString.contains("Content-Type: audio/mp4"))
    }

    func testMultipartBodyFLACFormat() throws {
        let service = TranscriptionService()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio.flac")
        try Data([0x66, 0x4C, 0x61, 0x43]).write(to: tempURL) // "fLaC" magic
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let body = try TranscriptionService.buildMultipartBody(
            audioFileURL: tempURL,
            model: "whisper-large-v3",
            format: .flac,
            boundary: "b"
        )
        let bodyString = String(data: body, encoding: .utf8)!

        XCTAssertTrue(bodyString.contains("filename=\"audio.flac\""))
        XCTAssertTrue(bodyString.contains("Content-Type: audio/flac"))
    }

    func testMultipartBodyIncludesAudioData() throws {
        let service = TranscriptionService()

        let audioBytes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05]
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio2.wav")
        try Data(audioBytes).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let body = try TranscriptionService.buildMultipartBody(
            audioFileURL: tempURL,
            model: "whisper-large-v3",
            format: .wav,
            boundary: "b"
        )

        let audioData = Data(audioBytes)
        XCTAssertNotNil(body.range(of: audioData))
    }

    // MARK: - Format consistency

    func testAllThreeFormatsProduceDistinctContentTypes() throws {
        let service = TranscriptionService()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-ct.bin")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var contentTypes: Set<String> = []

        for format in AudioFormat.allCases {
            let body = try TranscriptionService.buildMultipartBody(
                audioFileURL: tempURL, model: "m", format: format, boundary: "b"
            )
            let bodyString = String(data: body, encoding: .isoLatin1)!
            if let range = bodyString.range(of: "Content-Type: audio/") {
                let start = range.lowerBound
                let lineEnd = bodyString[start...].firstIndex(of: "\r") ?? bodyString.endIndex
                contentTypes.insert(String(bodyString[start..<lineEnd]))
            }
        }

        XCTAssertEqual(contentTypes.count, 3, "Each format should produce a distinct Content-Type")
    }

    func testMultipartBodyIncludesResponseFormatText() throws {
        let service = TranscriptionService()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-rf.wav")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let body = try TranscriptionService.buildMultipartBody(
            audioFileURL: tempURL, model: "whisper-large-v3", format: .wav, boundary: "b"
        )
        let bodyString = String(data: body, encoding: .utf8)!
        XCTAssertTrue(bodyString.contains("name=\"response_format\"\r\n\r\ntext"),
                       "Multipart body must request text response format")
    }

    func testMultipartBodyBoundaryTermination() throws {
        let service = TranscriptionService()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-term.wav")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let body = try TranscriptionService.buildMultipartBody(
            audioFileURL: tempURL, model: "m", format: .wav, boundary: "BOUNDARY"
        )
        let bodyString = String(data: body, encoding: .utf8)!
        XCTAssertTrue(bodyString.hasSuffix("--BOUNDARY--\r\n"),
                       "Multipart body must end with closing boundary")
    }

    func testTranscriptProcessingBodyUsesGroqChatShape() throws {
        let service = TranscriptionService()

        let data = try service.buildTranscriptProcessingBody(
            transcript: "um this is teh thing",
            mode: .cleanUp,
            model: "llama-3.3-70b-versatile"
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let messages = json?["messages"] as? [[String: String]]

        XCTAssertEqual(json?["model"] as? String, "llama-3.3-70b-versatile")
        XCTAssertEqual(json?["temperature"] as? Double, 0.2)
        XCTAssertEqual(json?["max_completion_tokens"] as? Int, 1024)
        XCTAssertEqual(messages?.first?["role"], "system")
        XCTAssertTrue(messages?.first?["content"]?.contains("Clean up transcript formatting") == true)
        XCTAssertEqual(messages?.last?["role"], "user")
        XCTAssertEqual(messages?.last?["content"], "um this is teh thing")
    }

    func testCleanupFormattingRequestUsesDefaultPromptPreferredTermsAndReturnOnlyInstruction() throws {
        let request = TranscriptCleanupRequest(
            rawTranscript: "first item supa base second item",
            mode: .cleanUp,
            customPrompt: nil,
            vocabularyCorrections: [],
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
            vocabularyCorrections: [],
            preferredTerms: [],
            provider: .groq(model: "llama-3.3-70b-versatile")
        )

        let body = try TranscriptionService.buildTranscriptProcessingBody(request: request)
        let bodyString = String(data: body, encoding: .utf8)!

        XCTAssertTrue(bodyString.contains("Use short paragraphs and preserve product names."), bodyString)
        XCTAssertFalse(bodyString.contains("Preferred terms"), bodyString)
        XCTAssertTrue(bodyString.contains("Return only the final processed transcript"), bodyString)
    }

    func testCleanupFormattingRequestIncludesVocabularyCorrectionsBeforePreferredTerms() throws {
        let request = TranscriptCleanupRequest(
            rawTranscript: "please fix super base auth",
            mode: .cleanUp,
            customPrompt: nil,
            vocabularyCorrections: [
                VocabularyCorrection(writtenAs: "super base", correctVersion: "Supabase")
            ],
            preferredTerms: ["Postgres"],
            provider: .customOpenAICompatibleChat(
                baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
                model: "qwen2.5:7b"
            )
        )

        let body = try TranscriptionService.buildTranscriptProcessingBody(request: request)
        let bodyString = String(data: body, encoding: .utf8)!

        XCTAssertTrue(bodyString.contains("Vocabulary corrections"), bodyString)
        XCTAssertTrue(bodyString.contains("If the transcript says \\\"super base\\\", use \\\"Supabase\\\"."), bodyString)
        XCTAssertTrue(bodyString.contains("Preferred terms"), bodyString)
        XCTAssertTrue(bodyString.contains("Postgres"), bodyString)
        XCTAssertTrue(bodyString.contains("please fix super base auth"), bodyString)
    }

    // MARK: - Deterministic transport/status mapping

    func testTranscribeReturnsTrimmedTextForHTTP200() async throws {
        let transport = StubTransport { request in
            XCTAssertEqual(request.timeoutInterval, TranscriptionService.transcriptionTimeout)
            return (
                Data("  hello world\n".utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        }
        let service = TranscriptionService(transport: transport)
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let text = try await service.transcribe(
            audioFileURL: tempURL,
            apiKey: "test-key",
            model: "whisper-large-v3",
            format: .wav
        )

        XCTAssertEqual(text, "hello world")
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testTranscribeAcceptsJSONTextResponseForOpenAICompatibleServers() async throws {
        let transport = StubTransport { request in
            (
                Data(#"{"text":"  json transcript\n"}"#.utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        }
        let service = TranscriptionService(transport: transport)
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let text = try await service.transcribe(
            audioFileURL: tempURL,
            apiKey: "test-key",
            model: "whisper-large-v3",
            format: .wav
        )

        XCTAssertEqual(text, "json transcript")
    }

    func testTranscribeRetriesTransientServerErrorOnce() async throws {
        var attempts = 0
        let transport = StubTransport { request in
            attempts += 1
            if attempts == 1 {
                return (
                    Data("temporary outage".utf8),
                    Self.httpResponse(statusCode: 503, url: request.url!)
                )
            }
            return (
                Data("recovered transcript".utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        }
        let service = TranscriptionService(transport: transport)
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let text = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "m")

        XCTAssertEqual(text, "recovered transcript")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testTranscribeUsesCustomOpenAICompatibleEndpointAndCanOmitAuthorization() async throws {
        let provider = TranscriptionProvider.openAICompatible(
            baseURL: URL(string: "http://127.0.0.1:8080/v1")!,
            model: "whisper-1"
        )
        let transport = StubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/audio/transcriptions")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (
                Data("local transcript".utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        }
        let service = TranscriptionService(provider: provider, transport: transport)
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let text = try await service.transcribe(
            audioFileURL: tempURL,
            apiKey: nil,
            model: provider.transcriptionModel,
            format: .wav
        )

        XCTAssertEqual(text, "local transcript")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testTranscribeTrimsDummyAuthorizationForLocalProvider() async throws {
        let provider = TranscriptionProvider.openAICompatible(
            baseURL: URL(string: "http://127.0.0.1:8080/v1")!,
            model: "whisper-1"
        )
        let transport = StubTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local")
            return (
                Data("local transcript".utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        }
        let service = TranscriptionService(provider: provider, transport: transport)
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        _ = try await service.transcribe(
            audioFileURL: tempURL,
            apiKey: " local ",
            model: provider.transcriptionModel,
            format: .wav
        )
    }

    func testTranscribeMapsHTTP401ToInvalidApiKey() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data("unauthorized".utf8), Self.httpResponse(statusCode: 401, url: request.url!))
        })
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "bad", model: "m")
            XCTFail("Expected invalid API key error")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .invalidApiKey)
        }
    }

    func testTranscribeMapsHTTP413ToFileTooLarge() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data("too large".utf8), Self.httpResponse(statusCode: 413, url: request.url!))
        })
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "m")
            XCTFail("Expected file too large error")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .fileTooLarge)
        }
    }

    func testTranscribePreflightsOversizedFileBeforeNetwork() async throws {
        var transportCalled = false
        let service = TranscriptionService(transport: StubTransport { _ in
            transportCalled = true
            return (Data("should not call".utf8), Self.httpResponse(statusCode: 200))
        })
        let tempURL = try Self.makeAudioFile(
            name: "oversized",
            bytes: Array(repeating: 0x00, count: TranscriptionService.maxUploadBytes + 1)
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "m")
            XCTFail("Expected file too large")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .fileTooLarge)
        }
        XCTAssertFalse(transportCalled)
    }

    func testAsyncMultipartBodyMatchesSyncBuilder() async throws {
        let service = TranscriptionService()
        let tempURL = try Self.makeAudioFile(bytes: [0x01, 0x02, 0x03])
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let sync = try TranscriptionService.buildMultipartBody(
            audioFileURL: tempURL,
            model: "whisper-large-v3",
            format: .wav,
            language: .es,
            boundary: "boundary"
        )
        let async = try await service.buildMultipartBodyAsync(
            audioFileURL: tempURL,
            model: "whisper-large-v3",
            format: .wav,
            language: .es,
            boundary: "boundary"
        )

        XCTAssertEqual(async, sync)
    }

    func testTranscribeMapsHTTP429ToRateLimited() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (
                Self.apiErrorJSON(message: "Rate limit reached", type: "rate_limit_error"),
                Self.httpResponse(statusCode: 429, url: request.url!)
            )
        })
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "m")
            XCTFail("Expected rate limit error")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .rateLimited("Rate limit reached"))
        }
    }

    func testTranscribeMapsHTTP429QuotaBodyToQuotaExceeded() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (
                Self.apiErrorJSON(message: "Quota exceeded. Check billing.", type: "insufficient_quota"),
                Self.httpResponse(statusCode: 429, url: request.url!)
            )
        })
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "m")
            XCTFail("Expected quota error")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .quotaExceeded("Quota exceeded. Check billing."))
        }
    }

    func testTranscribeMapsHTTP500ToServerError() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data("server exploded".utf8), Self.httpResponse(statusCode: 500, url: request.url!))
        })
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "m")
            XCTFail("Expected server error")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .serverError(500))
        }
    }

    func testTranscribeMapsBadRequestModelBodyToModelUnavailable() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (
                Self.apiErrorJSON(message: "The model 'missing-model' does not exist"),
                Self.httpResponse(statusCode: 400, url: request.url!)
            )
        })
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "missing-model")
            XCTFail("Expected model unavailable")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .modelUnavailable("missing-model"))
        }
    }

    func testProcessTranscriptMapsMalformedChatResponseToInvalidResponse() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8), Self.httpResponse(statusCode: 200, url: request.url!))
        })

        do {
            _ = try await service.processTranscript(
                "raw transcript",
                apiKey: "key",
                mode: .cleanUp,
                model: "llama-3.3-70b-versatile"
            )
            XCTFail("Expected invalid response")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testProcessTranscriptMapsMalformedJSONToInvalidResponse() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data(#"{"choices":["#.utf8), Self.httpResponse(statusCode: 200, url: request.url!))
        })

        do {
            _ = try await service.processTranscript(
                "raw transcript",
                apiKey: "key",
                mode: .cleanUp,
                model: "llama-3.3-70b-versatile"
            )
            XCTFail("Expected invalid response")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testOpenAICleanupRequestUsesResponsesAPIShape() async throws {
        let transport = StubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            )
            XCTAssertEqual(body["model"] as? String, "gpt-5.4-mini")
            XCTAssertEqual(body["input"] as? String, "raw transcript")
            XCTAssertEqual(body["max_output_tokens"] as? Int, 1024)
            XCTAssertNil(body["messages"])
            XCTAssertNil(body["max_completion_tokens"])
            XCTAssertTrue((body["instructions"] as? String)?.contains("Clean up transcript formatting") == true)
            XCTAssertTrue((body["instructions"] as? String)?.contains("Return only the final processed transcript.") == true)

            return (
                Data(#"{"output_text":"clean text"}"#.utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        }
        let service = TranscriptionService(transport: transport)

        let result = try await service.processTranscript(
            request: TranscriptCleanupRequest(
                rawTranscript: "raw transcript",
                mode: .cleanUp,
                customPrompt: nil,
                vocabularyCorrections: [],
                preferredTerms: [],
                provider: .openAI(model: "gpt-5.4-mini")
            ),
            apiKey: "openai-key"
        )

        XCTAssertEqual(result, "clean text")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testOpenAICleanupDecodesNestedResponsesOutputText() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
            return (
                Data(#"{"output":[{"type":"message","content":[{"type":"output_text","text":"nested clean text"}]}]}"#.utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        })

        let result = try await service.processTranscript(
            request: TranscriptCleanupRequest(
                rawTranscript: "raw transcript",
                mode: .cleanUp,
                customPrompt: nil,
                vocabularyCorrections: [],
                preferredTerms: [],
                provider: .openAI(model: "gpt-5.4-mini")
            ),
            apiKey: "openai-key"
        )

        XCTAssertEqual(result, "nested clean text")
    }

    func testProcessTranscriptMapsHTTP401ToInvalidApiKey() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data("unauthorized".utf8), Self.httpResponse(statusCode: 401, url: request.url!))
        })

        do {
            _ = try await service.processTranscript(
                "raw transcript",
                apiKey: "bad",
                mode: .cleanUp,
                model: "llama-3.3-70b-versatile"
            )
            XCTFail("Expected invalid API key")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .invalidApiKey)
        }
    }

    func testProcessTranscriptMapsHTTP429ToRateLimited() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (
                Self.apiErrorJSON(message: "Rate limit reached", type: "rate_limit_error"),
                Self.httpResponse(statusCode: 429, url: request.url!)
            )
        })

        do {
            _ = try await service.processTranscript(
                "raw transcript",
                apiKey: "key",
                mode: .cleanUp,
                model: "llama-3.3-70b-versatile"
            )
            XCTFail("Expected rate limit")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .rateLimited("Rate limit reached"))
        }
    }

    func testValidateApiKeyUsesModelsEndpointAndAuthorization() async throws {
        let transport = StubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            return (
                Data(#"{"data":[{"id":"whisper-large-v3-turbo"},{"id":"llama-3.3-70b-versatile"}]}"#.utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        }
        let service = TranscriptionService(transport: transport)

        try await service.validateApiKey(
            apiKey: "test-key",
            requiredModels: ["whisper-large-v3-turbo", "llama-3.3-70b-versatile"]
        )

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testValidateApiKeySkipsModelsEndpointForOpenAICompatibleProvider() async throws {
        var transportCalled = false
        let provider = TranscriptionProvider.openAICompatible(
            baseURL: URL(string: "http://127.0.0.1:8080/v1")!,
            model: "whisper-1"
        )
        let service = TranscriptionService(provider: provider, transport: StubTransport { request in
            transportCalled = true
            return (Data("unexpected".utf8), Self.httpResponse(statusCode: 500, url: request.url!))
        })

        try await service.validateApiKey(apiKey: nil, requiredModels: ["whisper-1"])

        XCTAssertFalse(transportCalled)
    }

    func testValidateProviderConfigurationChecksCustomModelsEndpoint() async throws {
        let provider = TranscriptionProvider.openAICompatible(
            baseURL: URL(string: "http://127.0.0.1:8080/v1")!,
            model: "whisper-1"
        )
        let transport = StubTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.timeoutInterval, TranscriptionService.providerValidationTimeout)
            return (
                Data(#"{"data":[{"id":"whisper-1"}]}"#.utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        }
        let service = TranscriptionService(provider: provider, transport: transport)

        let result = try await service.validateProviderConfiguration(apiKey: nil, requiredModels: ["whisper-1"])

        XCTAssertEqual(result, .modelsValidated)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testValidateProviderConfigurationAllowsReachableCustomServerWithoutModelsEndpoint() async throws {
        let provider = TranscriptionProvider.openAICompatible(
            baseURL: URL(string: "http://127.0.0.1:8080/v1")!,
            model: "whisper-1"
        )
        let service = TranscriptionService(provider: provider, transport: StubTransport { request in
            (
                Data("not found".utf8),
                Self.httpResponse(statusCode: 404, url: request.url!)
            )
        })

        let result = try await service.validateProviderConfiguration(apiKey: nil, requiredModels: ["whisper-1"])

        XCTAssertEqual(result, .reachableWithoutModelValidation)
    }

    func testValidateProviderConfigurationFailsWhenCustomServerIsUnreachable() async throws {
        let provider = TranscriptionProvider.openAICompatible(
            baseURL: URL(string: "http://127.0.0.1:9999/v1")!,
            model: "whisper-1"
        )
        let service = TranscriptionService(provider: provider, transport: StubTransport { _ in
            throw URLError(.cannotConnectToHost)
        })

        do {
            _ = try await service.validateProviderConfiguration(apiKey: nil, requiredModels: ["whisper-1"])
            XCTFail("Expected reachability failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cannotConnectToHost)
        }
    }

    func testValidateProviderConfigurationRejectsInvalidCustomBaseURL() async throws {
        let provider = TranscriptionProvider.openAICompatible(
            baseURL: URL(fileURLWithPath: "/tmp/whisper"),
            model: "whisper-1"
        )
        let service = TranscriptionService(provider: provider, transport: StubTransport { request in
            XCTFail("Invalid base URL should fail before request: \(String(describing: request.url))")
            return (Data(), Self.httpResponse(statusCode: 500))
        })

        do {
            _ = try await service.validateProviderConfiguration(apiKey: nil, requiredModels: ["whisper-1"])
            XCTFail("Expected invalid provider URL")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .invalidProviderURL)
        }
    }

    func testValidateProviderConfigurationFailsWhenCustomModelIsUnavailable() async throws {
        let provider = TranscriptionProvider.openAICompatible(
            baseURL: URL(string: "http://127.0.0.1:8080/v1")!,
            model: "whisper-1"
        )
        let service = TranscriptionService(provider: provider, transport: StubTransport { request in
            (
                Data(#"{"data":[{"id":"other-model"}]}"#.utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        })

        do {
            _ = try await service.validateProviderConfiguration(apiKey: nil, requiredModels: ["whisper-1"])
            XCTFail("Expected missing custom model failure")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .modelUnavailable("whisper-1"))
        }
    }

    func testValidateCustomCleanupProviderUsesModelsEndpoint() async throws {
        let transport = StubTransport { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            if request.url?.path.hasSuffix("/models") == true {
                XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/models")
                XCTAssertEqual(request.httpMethod, "GET")
                let response = Self.httpResponse(statusCode: 200, url: request.url!)
                return (Data(#"{"data":[{"id":"llama3.1:8b"}]}"#.utf8), response)
            }

            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            let response = Self.httpResponse(statusCode: 200, url: request.url!)
            return (Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8), response)
        }
        let service = TranscriptionService(transport: transport)
        let provider = TranscriptCleanupProvider.customOpenAICompatibleChat(
            baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
            model: "llama3.1:8b"
        )

        let result = try await service.validateCleanupProviderConfiguration(provider: provider, apiKey: nil)

        XCTAssertEqual(result, .modelsValidated)
        XCTAssertEqual(transport.requests.map(\.url?.path), ["/v1/models", "/v1/chat/completions"])
    }

    func testValidateOpenAICleanupProviderUsesResponsesSmoke() async throws {
        let transport = StubTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-key")
            if request.url?.path.hasSuffix("/models") == true {
                XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models")
                XCTAssertEqual(request.httpMethod, "GET")
                let response = Self.httpResponse(statusCode: 200, url: request.url!)
                return (Data(#"{"data":[{"id":"gpt-5.4-mini"}]}"#.utf8), response)
            }

            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            )
            XCTAssertEqual(body["model"] as? String, "gpt-5.4-mini")
            XCTAssertEqual(body["input"] as? String, "Connection test.")
            XCTAssertNil(body["messages"])
            let response = Self.httpResponse(statusCode: 200, url: request.url!)
            return (Data(#"{"output_text":"ok"}"#.utf8), response)
        }
        let service = TranscriptionService(transport: transport)
        let provider = TranscriptCleanupProvider.openAI(model: "gpt-5.4-mini")

        let result = try await service.validateCleanupProviderConfiguration(provider: provider, apiKey: "openai-key")

        XCTAssertEqual(result, .modelsValidated)
        XCTAssertEqual(transport.requests.map(\.url?.path), ["/v1/models", "/v1/responses"])
    }

    func testValidateCustomCleanupProviderFallsBackToChatSmokeWhenModelsUnsupported() async throws {
        let transport = StubTransport { request in
            if request.url?.path.hasSuffix("/models") == true {
                let response = Self.httpResponse(statusCode: 404, url: request.url!)
                return (Data(), response)
            }

            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
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

    func testValidateCustomCleanupProviderFailsWhenChatSmokeReturnsMalformedJSON() async throws {
        let transport = StubTransport { request in
            if request.url?.path.hasSuffix("/models") == true {
                let response = Self.httpResponse(statusCode: 200, url: request.url!)
                return (Data(#"{"data":[{"id":"llama3.1:8b"}]}"#.utf8), response)
            }

            let response = Self.httpResponse(statusCode: 200, url: request.url!)
            return (Data("not json".utf8), response)
        }
        let service = TranscriptionService(transport: transport)
        let provider = TranscriptCleanupProvider.customOpenAICompatibleChat(
            baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
            model: "llama3.1:8b"
        )

        do {
            _ = try await service.validateCleanupProviderConfiguration(provider: provider, apiKey: nil)
            XCTFail("Expected invalid response")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .invalidResponse)
        }
        XCTAssertEqual(transport.requests.map(\.url?.path), ["/v1/models", "/v1/chat/completions"])
    }

    func testValidateCustomCleanupProviderFailsWhenChatSmokeReturnsEmptyContent() async throws {
        let transport = StubTransport { request in
            if request.url?.path.hasSuffix("/models") == true {
                let response = Self.httpResponse(statusCode: 200, url: request.url!)
                return (Data(#"{"data":[{"id":"llama3.1:8b"}]}"#.utf8), response)
            }

            let response = Self.httpResponse(statusCode: 200, url: request.url!)
            return (Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8), response)
        }
        let service = TranscriptionService(transport: transport)
        let provider = TranscriptCleanupProvider.customOpenAICompatibleChat(
            baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
            model: "llama3.1:8b"
        )

        do {
            _ = try await service.validateCleanupProviderConfiguration(provider: provider, apiKey: nil)
            XCTFail("Expected invalid response")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .invalidResponse)
        }
        XCTAssertEqual(transport.requests.map(\.url?.path), ["/v1/models", "/v1/chat/completions"])
    }

    func testValidateApiKeyMapsHTTP401ToInvalidApiKey() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data("unauthorized".utf8), Self.httpResponse(statusCode: 401, url: request.url!))
        })

        do {
            try await service.validateApiKey(apiKey: "bad")
            XCTFail("Expected invalid API key")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .invalidApiKey)
        }
    }

    func testValidateApiKeyFailsWhenRequiredModelIsUnavailable() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (
                Data(#"{"data":[{"id":"whisper-large-v3-turbo"}]}"#.utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        })

        do {
            try await service.validateApiKey(
                apiKey: "key",
                requiredModels: ["whisper-large-v3-turbo", "missing-cleanup-model"]
            )
            XCTFail("Expected model unavailable")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .modelUnavailable("missing-cleanup-model"))
        }
    }

    func testTranscribePropagatesTimeoutAndOfflineErrors() async throws {
        for code in [URLError.timedOut, .notConnectedToInternet] {
            let service = TranscriptionService(transport: StubTransport { _ in
                throw URLError(code)
            })
            let tempURL = try Self.makeAudioFile()
            defer { try? FileManager.default.removeItem(at: tempURL) }

            do {
                _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "m")
                XCTFail("Expected URL error \(code)")
            } catch let error as URLError {
                XCTAssertEqual(error.code, code)
            }
        }
    }
}

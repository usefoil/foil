import Foundation

protocol TranscriptionTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: TranscriptionTransport {}

enum TranscriptionProviderID: String, CaseIterable, Identifiable {
    case groq
    case openAI = "openai"
    case openAICompatible = "openai-compatible"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq:
            "Groq"
        case .openAI:
            "OpenAI"
        case .openAICompatible:
            "OpenAI-compatible"
        }
    }

    var apiKeysURL: URL? {
        switch self {
        case .groq:
            URL(string: "https://console.groq.com/keys")
        case .openAI:
            URL(string: "https://platform.openai.com/api-keys")
        case .openAICompatible:
            nil
        }
    }

    var apiKeysLinkTitle: String? {
        switch self {
        case .groq:
            "Get or manage Groq API keys"
        case .openAI:
            "Get or manage OpenAI API keys"
        case .openAICompatible:
            nil
        }
    }
}

enum TranscriptionProviderPresetID: String, CaseIterable, Identifiable {
    case groq
    case openAIWhisper = "openai-whisper"
    case localWhisperCPP = "local-whisper-cpp"
    case customOpenAICompatible = "custom-openai-compatible"

    var id: String { rawValue }
}

struct TranscriptionProviderPreset: Equatable, Identifiable {
    let id: TranscriptionProviderPresetID
    let displayName: String
    let providerID: TranscriptionProviderID
    let baseURL: URL?
    let model: String
    let requiresAPIKey: Bool
    let supportsTranscriptProcessing: Bool
    let isEditable: Bool

    static let groq = TranscriptionProviderPreset(
        id: .groq,
        displayName: "Groq",
        providerID: .groq,
        baseURL: URL(string: "https://api.groq.com/openai/v1")!,
        model: "whisper-large-v3-turbo",
        requiresAPIKey: true,
        supportsTranscriptProcessing: true,
        isEditable: false
    )

    static let localWhisperCPP = TranscriptionProviderPreset(
        id: .localWhisperCPP,
        displayName: "Local whisper.cpp",
        providerID: .openAICompatible,
        baseURL: URL(string: "http://127.0.0.1:8080/v1")!,
        model: "whisper-1",
        requiresAPIKey: false,
        supportsTranscriptProcessing: false,
        isEditable: false
    )

    static let openAIWhisper = TranscriptionProviderPreset(
        id: .openAIWhisper,
        displayName: "OpenAI Whisper",
        providerID: .openAI,
        baseURL: URL(string: "https://api.openai.com/v1")!,
        model: "whisper-1",
        requiresAPIKey: true,
        supportsTranscriptProcessing: false,
        isEditable: false
    )

    static func customOpenAICompatible(baseURL: URL?, model: String) -> TranscriptionProviderPreset {
        TranscriptionProviderPreset(
            id: .customOpenAICompatible,
            displayName: "Custom OpenAI-compatible",
            providerID: .openAICompatible,
            baseURL: baseURL,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "whisper-1" : model,
            requiresAPIKey: false,
            supportsTranscriptProcessing: false,
            isEditable: true
        )
    }

    static func builtIn(id: TranscriptionProviderPresetID) -> TranscriptionProviderPreset? {
        switch id {
        case .groq:
            groq
        case .openAIWhisper:
            openAIWhisper
        case .localWhisperCPP:
            localWhisperCPP
        case .customOpenAICompatible:
            nil
        }
    }
}

struct TranscriptionProvider: Equatable {
    let id: TranscriptionProviderID
    let displayName: String
    let baseURL: URL
    let transcriptionModel: String
    let requiresAPIKey: Bool
    let supportsModelValidation: Bool
    let supportsTranscriptProcessing: Bool

    static let groq = TranscriptionProvider(
        id: .groq,
        displayName: "Groq",
        baseURL: URL(string: "https://api.groq.com/openai/v1")!,
        transcriptionModel: "whisper-large-v3-turbo",
        requiresAPIKey: true,
        supportsModelValidation: true,
        supportsTranscriptProcessing: true
    )

    static let openAIWhisper = TranscriptionProvider(
        id: .openAI,
        displayName: "OpenAI Whisper",
        baseURL: URL(string: "https://api.openai.com/v1")!,
        transcriptionModel: "whisper-1",
        requiresAPIKey: true,
        supportsModelValidation: true,
        supportsTranscriptProcessing: false
    )

    static func openAICompatible(
        baseURL: URL,
        model: String,
        displayName: String = "OpenAI-compatible",
        requiresAPIKey: Bool = false
    ) -> TranscriptionProvider {
        TranscriptionProvider(
            id: .openAICompatible,
            displayName: displayName,
            baseURL: baseURL,
            transcriptionModel: model,
            requiresAPIKey: requiresAPIKey,
            supportsModelValidation: false,
            supportsTranscriptProcessing: false
        )
    }

    var audioTranscriptionsEndpoint: URL {
        endpoint("audio/transcriptions")
    }

    var chatCompletionsEndpoint: URL {
        endpoint("chat/completions")
    }

    var modelsEndpoint: URL {
        endpoint("models")
    }

    private func endpoint(_ path: String) -> URL {
        let root = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(root)/\(path)")!
    }
}

enum TranscriptCleanupProviderID: String, CaseIterable, Identifiable {
    case none
    case groq
    case openAI = "openai"
    case customOpenAICompatibleChat = "custom-openai-compatible-chat"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            "None"
        case .groq:
            "Groq"
        case .openAI:
            "OpenAI"
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

    static func openAI(model: String) -> TranscriptCleanupProvider {
        TranscriptCleanupProvider(
            id: .openAI,
            displayName: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "gpt-5.4-mini" : model,
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

    var responsesEndpoint: URL? {
        endpoint("responses")
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

struct TranscriptCleanupRequest: Equatable {
    let rawTranscript: String
    let mode: TranscriptProcessingMode
    let customPrompt: String?
    let vocabularyCorrections: [VocabularyCorrection]
    let preferredTerms: [String]
    let provider: TranscriptCleanupProvider

    var resolvedPrompt: String {
        let trimmed = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? mode.defaultPrompt : trimmed
    }

    var systemInstruction: String {
        guard mode != .raw else { return "" }
        var parts = [resolvedPrompt]
        if !vocabularyCorrections.isEmpty {
            let corrections = vocabularyCorrections
                .map { "- If the transcript says \"\($0.writtenAs)\", use \"\($0.correctVersion)\"." }
                .joined(separator: "\n")
            parts.append("Vocabulary corrections:\n\(corrections)")
        }
        if !preferredTerms.isEmpty {
            let terms = preferredTerms.map { "- \($0)" }.joined(separator: "\n")
            parts.append("Preferred terms to preserve or prefer when appropriate:\n\(terms)")
        }
        parts.append("Return only the final processed transcript.")
        return parts.joined(separator: "\n\n")
    }
}

enum LocalWhisperSetupModelID: String, CaseIterable, Identifiable {
    case tinyEN = "tiny.en"
    case baseEN = "base.en"
    case smallEN = "small.en"
    case mediumEN = "medium.en"
    case largeV3Turbo = "large-v3-turbo"
    case largeV3 = "large-v3"

    var id: String { rawValue }
}

struct LocalWhisperSetupModel: Equatable, Identifiable {
    let id: LocalWhisperSetupModelID
    let displayName: String
    let languageScope: String
    let diskGuidance: String
    let performanceGuidance: String

    var downloadIdentifier: String { id.rawValue }
    var ggmlFilename: String { "ggml-\(downloadIdentifier).bin" }

    static let all: [LocalWhisperSetupModel] = [
        LocalWhisperSetupModel(
            id: .tinyEN,
            displayName: "Tiny English",
            languageScope: "English-only",
            diskGuidance: "Smallest download",
            performanceGuidance: "Fastest local smoke-test option with the lowest accuracy."
        ),
        LocalWhisperSetupModel(
            id: .baseEN,
            displayName: "Base English",
            languageScope: "English-only",
            diskGuidance: "Small download",
            performanceGuidance: "Recommended starter model for English transcription."
        ),
        LocalWhisperSetupModel(
            id: .smallEN,
            displayName: "Small English",
            languageScope: "English-only",
            diskGuidance: "Moderate download",
            performanceGuidance: "Better English accuracy with still-manageable local performance."
        ),
        LocalWhisperSetupModel(
            id: .mediumEN,
            displayName: "Medium English",
            languageScope: "English-only",
            diskGuidance: "Large download",
            performanceGuidance: "Higher English accuracy with slower local transcription."
        ),
        LocalWhisperSetupModel(
            id: .largeV3Turbo,
            displayName: "Large V3 Turbo",
            languageScope: "Multilingual",
            diskGuidance: "Large download",
            performanceGuidance: "Strong multilingual quality with faster large-v3-family performance."
        ),
        LocalWhisperSetupModel(
            id: .largeV3,
            displayName: "Large V3",
            languageScope: "Multilingual",
            diskGuidance: "Largest download",
            performanceGuidance: "Highest standard large-v3 quality with the slowest local performance."
        )
    ]

    static let recommendedDefaultID: LocalWhisperSetupModelID = .baseEN

    static func option(id: LocalWhisperSetupModelID) -> LocalWhisperSetupModel {
        all.first { $0.id == id }!
    }
}

struct LocalWhisperSetupCommands: Equatable {
    static let defaultInstallPath = "~/Developer/whisper.cpp"
    static let defaultHost = "127.0.0.1"
    static let defaultPort = 8080
    static let apiCompatibilityModel = "whisper-1"

    let model: LocalWhisperSetupModel
    var installPath: String = Self.defaultInstallPath
    var host: String = Self.defaultHost
    var port: Int = Self.defaultPort

    var cloneCommand: String {
        """
        mkdir -p ~/Developer
        git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git \(installPath)
        """
    }

    var buildCommand: String {
        """
        cd \(installPath)
        cmake -B build -DWHISPER_BUILD_TESTS=OFF
        cmake --build build -j --config Release
        """
    }

    var downloadCommand: String {
        """
        cd \(installPath)
        sh ./models/download-ggml-model.sh \(model.downloadIdentifier)
        """
    }

    var startServerCommand: String {
        """
        \(installPath)/build/bin/whisper-server \\
          --host \(host) \\
          --port \(port) \\
          --model \(installPath)/models/\(model.ggmlFilename) \\
          --inference-path /v1/audio/transcriptions \\
          --convert \\
          --no-timestamps
        """
    }

    var expandedInstallPath: String {
        (installPath as NSString).expandingTildeInPath
    }

    var installDirectoryURL: URL {
        URL(fileURLWithPath: expandedInstallPath, isDirectory: true)
    }

    var serverBinaryURL: URL {
        installDirectoryURL
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("whisper-server", isDirectory: false)
    }

    var serverBinaryDisplayPath: String {
        Self.userFacingPath(serverBinaryURL.path)
    }

    var modelFileURL: URL {
        installDirectoryURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(model.ggmlFilename, isDirectory: false)
    }

    var modelFileDisplayPath: String {
        Self.userFacingPath(modelFileURL.path)
    }

    var startServerArguments: [String] {
        [
            "--host", host,
            "--port", "\(port)",
            "--model", modelFileURL.path,
            "--inference-path", "/v1/audio/transcriptions",
            "--convert",
            "--no-timestamps"
        ]
    }

    var localBaseURL: String {
        "http://\(host):\(port)/v1"
    }

    var modelsEndpointURL: URL {
        URL(string: "\(localBaseURL)/models")!
    }

    var modelSelectionExplanation: String {
        "\(AppBrand.name) sends \(Self.apiCompatibilityModel) for OpenAI-compatible API shape; whisper-server uses --model \(model.ggmlFilename) as the real local model."
    }

    private static func userFacingPath(_ path: String) -> String {
        let homePath = NSHomeDirectory()
        guard path == homePath || path.hasPrefix("\(homePath)/") else { return path }
        return "~\(path.dropFirst(homePath.count))"
    }
}

enum LocalWhisperServerStartResult: Equatable {
    case alreadyRunning(String)
    case started(String)
    case cancelled
    case missingBinary(String)
    case missingModel(String)
    case failed(String)
}

enum LocalWhisperServerReadinessResult: Equatable {
    case reachable
    case processExited(String?)
    case timedOut
    case cancelled
}

private final class LocalWhisperStartupOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var data = Data()
    private var isCapturing = true

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard isCapturing else { return }
        data.append(newData)
        if data.count > maximumBytes {
            data.removeFirst(data.count - maximumBytes)
        }
    }

    func stopCapturing(clear: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isCapturing = false
        if clear { data.removeAll(keepingCapacity: false) }
    }

    func sanitizedSummary(maximumCharacters: Int) -> String? {
        lock.lock()
        let snapshot = data
        lock.unlock()

        guard !snapshot.isEmpty else { return nil }
        var text = String(decoding: snapshot, as: UTF8.self)
        if let ansiExpression = try? NSRegularExpression(pattern: #"\x1B\[[0-?]*[ -/]*[@-~]"#) {
            text = ansiExpression.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        text = String(text.unicodeScalars.map { scalar in
            if scalar.value == 9 || scalar.value == 10 || scalar.value >= 32 {
                return Character(String(scalar))
            }
            return " "
        })
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let redacted = DiagnosticLog.redacted(lines.suffix(3).joined(separator: " · "))
        guard redacted.count > maximumCharacters else { return redacted }
        return "…" + String(redacted.suffix(maximumCharacters - 1))
    }
}

@MainActor
final class LocalWhisperServerController {
    typealias ReachabilityCheck = (URL) async -> Bool
    typealias Delay = (UInt64) async throws -> Void
    typealias MonotonicTime = () -> UInt64

    nonisolated static let defaultReadinessAttempts = 61
    nonisolated static let defaultReadinessDelayNanoseconds: UInt64 = 500_000_000
    nonisolated static let defaultReadinessTimeoutNanoseconds: UInt64 = 30_000_000_000
    nonisolated static let maximumStartupOutputBytes = 16_384
    nonisolated static let maximumStartupFailureDetailCharacters = 320

    private let fileManager: FileManager
    private let reachabilityCheck: ReachabilityCheck
    private let delay: Delay
    private let monotonicTime: MonotonicTime
    private var process: Process?
    private var standardInputPipe: Pipe?
    private var standardErrorPipe: Pipe?
    private var startupOutputBuffer: LocalWhisperStartupOutputBuffer?
    private var lastStartupFailureDetail: String?
    var onTermination: (() -> Void)?

    init(
        fileManager: FileManager = .default,
        delay: @escaping Delay = { try await Task.sleep(nanoseconds: $0) },
        monotonicTime: @escaping MonotonicTime = { DispatchTime.now().uptimeNanoseconds },
        reachabilityCheck: @escaping ReachabilityCheck = LocalWhisperServerController.defaultReachabilityCheck
    ) {
        self.fileManager = fileManager
        self.reachabilityCheck = reachabilityCheck
        self.delay = delay
        self.monotonicTime = monotonicTime
    }

    var isProcessRunning: Bool {
        process?.isRunning == true
    }

    func start(commands: LocalWhisperSetupCommands) async -> LocalWhisperServerStartResult {
        if await reachabilityCheck(commands.modelsEndpointURL) {
            return .alreadyRunning(commands.localBaseURL)
        }
        guard !Task.isCancelled else { return .cancelled }

        guard fileManager.fileExists(atPath: commands.serverBinaryURL.path) else {
            return .missingBinary(commands.serverBinaryDisplayPath)
        }
        guard fileManager.isExecutableFile(atPath: commands.serverBinaryURL.path) else {
            return .failed("whisper-server is not executable at \(commands.serverBinaryDisplayPath). Rebuild whisper.cpp and try again.")
        }
        guard fileManager.fileExists(atPath: commands.modelFileURL.path) else {
            return .missingModel(commands.modelFileDisplayPath)
        }

        let serverProcess = Process()
        serverProcess.executableURL = commands.serverBinaryURL
        serverProcess.arguments = commands.startServerArguments
        serverProcess.currentDirectoryURL = commands.installDirectoryURL
        // whisper-server watches stdin and exits cleanly when it reaches EOF.
        // GUI apps inherit a closed stdin, so keep a pipe open for its lifetime.
        let inputPipe = Pipe()
        serverProcess.standardInput = inputPipe
        let errorPipe = Pipe()
        let outputBuffer = LocalWhisperStartupOutputBuffer(maximumBytes: Self.maximumStartupOutputBytes)
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            outputBuffer.append(handle.availableData)
        }
        // The server is intentionally headless. stdout is discarded, while stderr is
        // continuously drained. Only a bounded startup tail is retained until the
        // server becomes reachable so transcription-time output is never captured.
        serverProcess.standardOutput = FileHandle.nullDevice
        serverProcess.standardError = errorPipe
        serverProcess.terminationHandler = { [weak self, weak serverProcess, weak errorPipe] terminatedProcess in
            Task { @MainActor in
                guard let self, let serverProcess, self.process === serverProcess else { return }
                self.lastStartupFailureDetail = outputBuffer.sanitizedSummary(
                    maximumCharacters: Self.maximumStartupFailureDetailCharacters
                )
                outputBuffer.stopCapturing(clear: false)
                errorPipe?.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.standardInputPipe = nil
                self.standardErrorPipe = nil
                DiagnosticLog.write(
                    "localWhisperServer: terminated status=\(terminatedProcess.terminationStatus) reason=\(terminatedProcess.terminationReason.rawValue)"
                )
                self.onTermination?()
            }
        }

        do {
            try serverProcess.run()
            process = serverProcess
            standardInputPipe = inputPipe
            standardErrorPipe = errorPipe
            startupOutputBuffer = outputBuffer
            lastStartupFailureDetail = nil
            DiagnosticLog.write("localWhisperServer: started pid=\(serverProcess.processIdentifier) binary=\(commands.serverBinaryURL.path)")
            return .started(commands.localBaseURL)
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            outputBuffer.stopCapturing(clear: true)
            let safeDetail = Self.sanitizedStartupDetail(error.localizedDescription)
            DiagnosticLog.write("localWhisperServer: failed error=\(safeDetail)")
            return .failed("Could not start whisper-server: \(safeDetail)")
        }
    }

    func waitForReadiness(
        commands: LocalWhisperSetupCommands,
        attempts: Int = LocalWhisperServerController.defaultReadinessAttempts,
        delayNanoseconds: UInt64 = LocalWhisperServerController.defaultReadinessDelayNanoseconds,
        timeoutNanoseconds: UInt64 = LocalWhisperServerController.defaultReadinessTimeoutNanoseconds
    ) async -> LocalWhisperServerReadinessResult {
        let startedAt = monotonicTime()
        let (deadline, overflow) = startedAt.addingReportingOverflow(timeoutNanoseconds)
        let effectiveDeadline = overflow ? UInt64.max : deadline

        for attempt in 1...max(1, attempts) {
            if Task.isCancelled { return .cancelled }
            if monotonicTime() >= effectiveDeadline { return .timedOut }
            if await reachabilityCheck(commands.modelsEndpointURL) {
                startupOutputBuffer?.stopCapturing(clear: true)
                lastStartupFailureDetail = nil
                return .reachable
            }
            await Task.yield()
            if !isProcessRunning {
                return .processExited(startupFailureDetail)
            }
            let now = monotonicTime()
            if now >= effectiveDeadline { return .timedOut }
            if attempt < attempts {
                do {
                    try await delay(min(delayNanoseconds, effectiveDeadline - now))
                } catch {
                    return .cancelled
                }
            }
        }
        if Task.isCancelled { return .cancelled }
        if !isProcessRunning { return .processExited(startupFailureDetail) }
        return .timedOut
    }

    var startupFailureDetail: String? {
        lastStartupFailureDetail ?? startupOutputBuffer?.sanitizedSummary(
            maximumCharacters: Self.maximumStartupFailureDetailCharacters
        )
    }

    func terminate() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
        }
        startupOutputBuffer?.stopCapturing(clear: true)
        standardErrorPipe?.fileHandleForReading.readabilityHandler = nil
        self.process = nil
        standardInputPipe = nil
        standardErrorPipe = nil
        startupOutputBuffer = nil
        lastStartupFailureDetail = nil
    }

    private static func sanitizedStartupDetail(_ detail: String) -> String {
        let buffer = LocalWhisperStartupOutputBuffer(maximumBytes: maximumStartupOutputBytes)
        buffer.append(Data(detail.utf8))
        return buffer.sanitizedSummary(maximumCharacters: maximumStartupFailureDetailCharacters)
            ?? "unknown launch error"
    }

    private static func defaultReachabilityCheck(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 0.75
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200 || http.statusCode == 404 || http.statusCode == 405
        } catch {
            return false
        }
    }
}

struct TranscriptionService {
    static let maxUploadBytes = 25 * 1024 * 1024
    static let transcriptionTimeout: TimeInterval = 120
    static let providerValidationTimeout: TimeInterval = 3
    static let transientRetryDelayNanoseconds: UInt64 = 150_000_000

    private let provider: TranscriptionProvider
    private let transport: TranscriptionTransport

    init(provider: TranscriptionProvider = .groq, transport: TranscriptionTransport = URLSession.shared) {
        self.provider = provider
        self.transport = transport
    }

    func withProvider(_ provider: TranscriptionProvider) -> TranscriptionService {
        TranscriptionService(provider: provider, transport: transport)
    }

    func transcribe(
        audioFileURL: URL,
        apiKey: String?,
        model: String,
        format: AudioFormat = .wav,
        language: Language = .auto
    ) async throws -> String {
        guard fileSize(at: audioFileURL) <= Self.maxUploadBytes else {
            DiagnosticLog.write("transcribe: local file too large")
            throw TranscriptionError.fileTooLarge
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: provider.audioTranscriptionsEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.transcriptionTimeout
        setAuthorizationHeader(apiKey: apiKey, on: &request)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try await buildMultipartBodyAsync(
            audioFileURL: audioFileURL, model: model, format: format, language: language, boundary: boundary
        )
        let audioSize = fileSize(at: audioFileURL)
        let bodySize = request.httpBody?.count ?? 0
        DiagnosticLog.write(
            "transcribe: sending format=\(format.rawValue) audioBytes=\(audioSize) bodyBytes=\(bodySize) model=\(model) language=\(language.rawValue)"
        )

        let (data, response) = try await performTranscriptionRequestWithRetry(request)
        guard let http = response as? HTTPURLResponse else {
            DiagnosticLog.write("transcribe: invalid response type")
            throw TranscriptionError.invalidResponse
        }
        DiagnosticLog.write("transcribe: response status=\(http.statusCode) responseBytes=\(data.count)")

        if http.statusCode == 200 {
            let trimmed = try decodeTranscriptionText(data)
            DiagnosticLog.write("transcribe: success textLength=\(trimmed.count)")
            return trimmed
        }

        let error = mapAPIError(statusCode: http.statusCode, data: data)
        DiagnosticLog.write("transcribe: API error status=\(http.statusCode) mapped=\(error.logName) bodyBytes=\(data.count)")
        throw error
    }

    private func performTranscriptionRequestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0...1 {
            do {
                let result = try await transport.data(for: request)
                if attempt == 0,
                   let http = result.1 as? HTTPURLResponse,
                   (500...599).contains(http.statusCode) {
                    DiagnosticLog.write("transcribe: transient server status=\(http.statusCode); retrying once")
                    try await Task.sleep(nanoseconds: Self.transientRetryDelayNanoseconds)
                    continue
                }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where attempt == 0 && isTransientNetworkError(error) {
                lastError = error
                DiagnosticLog.write("transcribe: transient network error=\(error.code.rawValue); retrying once")
                try await Task.sleep(nanoseconds: Self.transientRetryDelayNanoseconds)
            } catch {
                throw error
            }
        }
        throw lastError ?? TranscriptionError.invalidResponse
    }

    private func isTransientNetworkError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            true
        default:
            false
        }
    }

    private func decodeTranscriptionText(_ data: Data) throws -> String {
        if let decoded = try? JSONDecoder().decode(TranscriptionTextResponse.self, from: data) {
            let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                DiagnosticLog.write("transcribe: JSON response text was empty")
                throw TranscriptionError.invalidResponse
            }
            return text
        }

        guard let text = String(data: data, encoding: .utf8) else {
            DiagnosticLog.write("transcribe: failed to decode response as UTF-8")
            throw TranscriptionError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func processTranscript(
        _ transcript: String,
        apiKey: String?,
        mode: TranscriptProcessingMode,
        model: String
    ) async throws -> String {
        guard mode != .raw else { return transcript }
        var request = URLRequest(url: provider.chatCompletionsEndpoint)
        request.httpMethod = "POST"
        setAuthorizationHeader(apiKey: apiKey, on: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try buildTranscriptProcessingBody(transcript: transcript, mode: mode, model: model)

        DiagnosticLog.write("processTranscript: sending mode=\(mode.rawValue) model=\(model) inputLength=\(transcript.count)")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            DiagnosticLog.write("processTranscript: invalid response type")
            throw TranscriptionError.invalidResponse
        }
        DiagnosticLog.write("processTranscript: response status=\(http.statusCode) responseBytes=\(data.count)")

        if http.statusCode == 200 {
            let decoded: ChatCompletionResponse
            do {
                decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            } catch {
                DiagnosticLog.write("processTranscript: failed to decode response")
                throw TranscriptionError.invalidResponse
            }
            guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                throw TranscriptionError.invalidResponse
            }
            DiagnosticLog.write("processTranscript: success outputLength=\(content.count)")
            return content
        }

        let error = mapAPIError(statusCode: http.statusCode, data: data)
        DiagnosticLog.write("processTranscript: API error status=\(http.statusCode) mapped=\(error.logName) bodyBytes=\(data.count)")
        throw error
    }

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
                vocabularyCorrections: [],
                preferredTerms: [],
                provider: cleanupProvider
            ),
            apiKey: apiKey
        )
    }

    func processTranscript(
        request cleanupRequest: TranscriptCleanupRequest,
        apiKey: String?
    ) async throws -> String {
        guard cleanupRequest.mode != .raw else { return cleanupRequest.rawTranscript }
        guard let endpoint = cleanupEndpoint(for: cleanupRequest.provider) else {
            return cleanupRequest.rawTranscript
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        setAuthorizationHeader(apiKey: apiKey, on: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.buildTranscriptProcessingBodyForProvider(request: cleanupRequest)

        DiagnosticLog.write("processTranscript: sending cleanupProvider=\(cleanupRequest.provider.id.rawValue) mode=\(cleanupRequest.mode.rawValue) model=\(cleanupRequest.provider.model) inputLength=\(cleanupRequest.rawTranscript.count)")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            DiagnosticLog.write("processTranscript: invalid response type")
            throw TranscriptionError.invalidResponse
        }
        DiagnosticLog.write("processTranscript: response status=\(http.statusCode) responseBytes=\(data.count)")

        if http.statusCode == 200 {
            let content = try decodeCleanupResponse(data, provider: cleanupRequest.provider)
            DiagnosticLog.write("processTranscript: success outputLength=\(content.count)")
            return content
        }

        let error = mapAPIError(statusCode: http.statusCode, data: data)
        DiagnosticLog.write("processTranscript: API error status=\(http.statusCode) mapped=\(error.logName) bodyBytes=\(data.count)")
        throw error
    }

    private func cleanupEndpoint(for cleanupProvider: TranscriptCleanupProvider) -> URL? {
        switch cleanupProvider.id {
        case .openAI:
            cleanupProvider.responsesEndpoint
        case .groq, .customOpenAICompatibleChat:
            cleanupProvider.chatCompletionsEndpoint
        case .none:
            nil
        }
    }

    func validateApiKey(apiKey: String?, requiredModels: [String] = []) async throws {
        guard provider.supportsModelValidation else {
            DiagnosticLog.write("validateApiKey: skipping model validation for provider=\(provider.id.rawValue)")
            return
        }

        var request = URLRequest(url: provider.modelsEndpoint)
        request.httpMethod = "GET"
        setAuthorizationHeader(apiKey: apiKey, on: &request)

        DiagnosticLog.write("validateApiKey: checking provider=\(provider.id.rawValue) requiredModels=\(requiredModels.count)")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            DiagnosticLog.write("validateApiKey: invalid response type")
            throw TranscriptionError.invalidResponse
        }
        DiagnosticLog.write("validateApiKey: response status=\(http.statusCode) responseBytes=\(data.count)")

        guard http.statusCode == 200 else {
            let error = mapAPIError(statusCode: http.statusCode, data: data)
            DiagnosticLog.write("validateApiKey: API error status=\(http.statusCode) mapped=\(error.logName) bodyBytes=\(data.count)")
            throw error
        }

        let responseBody: ModelsResponse
        do {
            responseBody = try JSONDecoder().decode(ModelsResponse.self, from: data)
        } catch {
            DiagnosticLog.write("validateApiKey: failed to decode models response")
            throw TranscriptionError.invalidResponse
        }

        let availableModels = Set(responseBody.data.map(\.id))
        for model in requiredModels where !availableModels.contains(model) {
            throw TranscriptionError.modelUnavailable(model)
        }
    }

    func validateProviderConfiguration(apiKey: String?, requiredModels: [String] = []) async throws -> ProviderValidationResult {
        guard provider.id == .openAICompatible else {
            try await validateApiKey(apiKey: apiKey, requiredModels: requiredModels)
            return .modelsValidated
        }

        guard isValidHTTPBaseURL(provider.baseURL) else {
            DiagnosticLog.write("validateProviderConfiguration: invalid base URL provider=\(provider.id.rawValue)")
            throw TranscriptionError.invalidProviderURL
        }

        var request = URLRequest(url: provider.modelsEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.providerValidationTimeout
        setAuthorizationHeader(apiKey: apiKey, on: &request)

        DiagnosticLog.write("validateProviderConfiguration: checking reachability provider=\(provider.id.rawValue)")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            DiagnosticLog.write("validateProviderConfiguration: invalid response type")
            throw TranscriptionError.invalidResponse
        }
        DiagnosticLog.write("validateProviderConfiguration: response status=\(http.statusCode) responseBytes=\(data.count)")

        switch http.statusCode {
        case 200:
            guard let responseBody = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
                return .reachableWithoutModelValidation
            }
            let availableModels = Set(responseBody.data.map(\.id))
            for model in requiredModels where !availableModels.contains(model) {
                throw TranscriptionError.modelUnavailable(model)
            }
            return .modelsValidated
        case 404, 405:
            return .reachableWithoutModelValidation
        default:
            throw mapAPIError(statusCode: http.statusCode, data: data)
        }
    }

    func validateCleanupProviderConfiguration(
        provider cleanupProvider: TranscriptCleanupProvider,
        apiKey: String?
    ) async throws -> ProviderValidationResult {
        guard cleanupProvider.id != .none,
              let baseURL = cleanupProvider.baseURL,
              let modelsEndpoint = cleanupProvider.modelsEndpoint,
              isValidHTTPBaseURL(baseURL) else {
            DiagnosticLog.write("validateCleanupProviderConfiguration: invalid cleanup base URL provider=\(cleanupProvider.id.rawValue)")
            throw TranscriptionError.invalidProviderURL
        }

        var request = URLRequest(url: modelsEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.providerValidationTimeout
        setAuthorizationHeader(apiKey: apiKey, on: &request)

        DiagnosticLog.write("validateCleanupProviderConfiguration: checking models provider=\(cleanupProvider.id.rawValue) model=\(cleanupProvider.model)")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            DiagnosticLog.write("validateCleanupProviderConfiguration: invalid response type")
            throw TranscriptionError.invalidResponse
        }
        DiagnosticLog.write("validateCleanupProviderConfiguration: models status=\(http.statusCode) responseBytes=\(data.count)")

        switch http.statusCode {
        case 200:
            guard let responseBody = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
                return try await validateCleanupSmoke(provider: cleanupProvider, apiKey: apiKey)
            }
            let availableModels = Set(responseBody.data.map(\.id))
            if !cleanupProvider.model.isEmpty && !availableModels.contains(cleanupProvider.model) {
                throw TranscriptionError.modelUnavailable(cleanupProvider.model)
            }
            _ = try await validateCleanupSmoke(provider: cleanupProvider, apiKey: apiKey)
            return .modelsValidated
        case 404, 405:
            return try await validateCleanupSmoke(provider: cleanupProvider, apiKey: apiKey)
        default:
            throw mapAPIError(statusCode: http.statusCode, data: data)
        }
    }

    private func validateCleanupSmoke(
        provider cleanupProvider: TranscriptCleanupProvider,
        apiKey: String?
    ) async throws -> ProviderValidationResult {
        guard let endpoint = cleanupEndpoint(for: cleanupProvider) else {
            throw TranscriptionError.invalidProviderURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.providerValidationTimeout
        setAuthorizationHeader(apiKey: apiKey, on: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.buildTranscriptProcessingBodyForProvider(
            request: TranscriptCleanupRequest(
                rawTranscript: "Connection test.",
                mode: .cleanUp,
                customPrompt: nil,
                vocabularyCorrections: [],
                preferredTerms: [],
                provider: cleanupProvider
            )
        )

        DiagnosticLog.write("validateCleanupSmoke: checking provider=\(cleanupProvider.id.rawValue) model=\(cleanupProvider.model)")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            DiagnosticLog.write("validateCleanupSmoke: invalid response type")
            throw TranscriptionError.invalidResponse
        }
        DiagnosticLog.write("validateCleanupSmoke: response status=\(http.statusCode) responseBytes=\(data.count)")

        guard http.statusCode == 200 else {
            throw mapAPIError(statusCode: http.statusCode, data: data)
        }
        _ = try decodeCleanupResponse(data, provider: cleanupProvider)
        return .reachableWithoutModelValidation
    }

    private func decodeCleanupResponse(_ data: Data, provider cleanupProvider: TranscriptCleanupProvider) throws -> String {
        switch cleanupProvider.id {
        case .openAI:
            try decodeResponsesText(data)
        case .groq, .customOpenAICompatibleChat:
            try decodeChatCompletionText(data)
        case .none:
            throw TranscriptionError.invalidResponse
        }
    }

    private func decodeChatCompletionText(_ data: Data) throws -> String {
        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            DiagnosticLog.write("processTranscript: failed to decode chat completion response")
            throw TranscriptionError.invalidResponse
        }

        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw TranscriptionError.invalidResponse
        }
        return content
    }

    private func decodeResponsesText(_ data: Data) throws -> String {
        let decoded: ResponsesResponse
        do {
            decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        } catch {
            DiagnosticLog.write("processTranscript: failed to decode responses response")
            throw TranscriptionError.invalidResponse
        }

        guard let content = decoded.resolvedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw TranscriptionError.invalidResponse
        }
        return content
    }

    func buildTranscriptProcessingBody(
        transcript: String,
        mode: TranscriptProcessingMode,
        model: String
    ) throws -> Data {
        try Self.buildTranscriptProcessingBody(
            request: TranscriptCleanupRequest(
                rawTranscript: transcript,
                mode: mode,
                customPrompt: nil,
                vocabularyCorrections: [],
                preferredTerms: [],
                provider: .groq(model: model)
            )
        )
    }

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

    static func buildResponsesTranscriptProcessingBody(request cleanupRequest: TranscriptCleanupRequest) throws -> Data {
        let request = ResponsesRequest(
            model: cleanupRequest.provider.model,
            instructions: cleanupRequest.systemInstruction,
            input: cleanupRequest.rawTranscript,
            maxOutputTokens: 1024
        )
        return try JSONEncoder().encode(request)
    }

    private static func buildTranscriptProcessingBodyForProvider(request cleanupRequest: TranscriptCleanupRequest) throws -> Data {
        switch cleanupRequest.provider.id {
        case .openAI:
            try buildResponsesTranscriptProcessingBody(request: cleanupRequest)
        case .groq, .customOpenAICompatibleChat, .none:
            try buildTranscriptProcessingBody(request: cleanupRequest)
        }
    }

    static func buildMultipartBody(audioFileURL: URL, model: String, format: AudioFormat, language: Language = .auto, boundary: String) throws -> Data {
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

    func buildMultipartBodyAsync(
        audioFileURL: URL,
        model: String,
        format: AudioFormat,
        language: Language = .auto,
        boundary: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let body = try Self.buildMultipartBody(
                        audioFileURL: audioFileURL,
                        model: model,
                        format: format,
                        language: language,
                        boundary: boundary
                    )
                    continuation.resume(returning: body)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    enum TranscriptionError: Error, Equatable {
        case invalidResponse
        case invalidApiKey
        case invalidProviderURL
        case fileTooLarge
        case rateLimited(String?)
        case quotaExceeded(String?)
        case modelUnavailable(String)
        case badRequest(String?)
        case serverError(Int)
        case apiError(Int, String)

        var logName: String {
            switch self {
            case .invalidResponse: "invalidResponse"
            case .invalidApiKey: "invalidApiKey"
            case .invalidProviderURL: "invalidProviderURL"
            case .fileTooLarge: "fileTooLarge"
            case .rateLimited: "rateLimited"
            case .quotaExceeded: "quotaExceeded"
            case .modelUnavailable: "modelUnavailable"
            case .badRequest: "badRequest"
            case .serverError(let code): "serverError(\(code))"
            case .apiError(let code, _): "apiError(\(code))"
            }
        }
    }

    enum ProviderValidationResult: Equatable {
        case modelsValidated
        case reachableWithoutModelValidation
    }

    private func setAuthorizationHeader(apiKey: String?, on request: inout URLRequest) {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
    }

    private func isValidHTTPBaseURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return false
        }
        return true
    }

    private func mapAPIError(statusCode: Int, data: Data) -> TranscriptionError {
        let apiError = decodeAPIError(data)
        let body = String(data: data, encoding: .utf8) ?? ""
        let message = apiError?.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = apiError?.code?.lowercased()
        let type = apiError?.type?.lowercased()
        let haystack = [message, code, type].compactMap { $0?.lowercased() }.joined(separator: " ")

        switch statusCode {
        case 400:
            if mentionsModel(haystack) {
                return .modelUnavailable(apiError?.modelName ?? message ?? "selected model")
            }
            return .badRequest(message)
        case 401, 403:
            return .invalidApiKey
        case 413:
            return .fileTooLarge
        case 429:
            if haystack.contains("quota") || haystack.contains("billing") || haystack.contains("insufficient") {
                return .quotaExceeded(message)
            }
            return .rateLimited(message)
        case 500...599:
            return .serverError(statusCode)
        default:
            return .apiError(statusCode, body)
        }
    }

    private func mentionsModel(_ text: String) -> Bool {
        text.contains("model") && (
            text.contains("not found")
                || text.contains("does not exist")
                || text.contains("unavailable")
                || text.contains("invalid")
        )
    }

    private func decodeAPIError(_ data: Data) -> APIErrorPayload.ErrorDetail? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(APIErrorPayload.self, from: data).error
    }

    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? -1)
    }

    private struct ChatCompletionRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let maxCompletionTokens: Int

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxCompletionTokens = "max_completion_tokens"
        }

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct ChatCompletionResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String
        }
    }

    private struct ResponsesRequest: Encodable {
        let model: String
        let instructions: String
        let input: String
        let maxOutputTokens: Int

        enum CodingKeys: String, CodingKey {
            case model
            case instructions
            case input
            case maxOutputTokens = "max_output_tokens"
        }
    }

    private struct ResponsesResponse: Decodable {
        let outputText: String?
        let output: [OutputItem]?

        var resolvedText: String? {
            if let outputText, !outputText.isEmpty {
                return outputText
            }

            return output?
                .compactMap { item in
                    item.content?
                        .compactMap(\.text)
                        .joined(separator: "")
                }
                .joined(separator: "")
        }

        enum CodingKeys: String, CodingKey {
            case outputText = "output_text"
            case output
        }

        struct OutputItem: Decodable {
            let content: [ContentItem]?
        }

        struct ContentItem: Decodable {
            let text: String?
        }
    }

    private struct ModelsResponse: Decodable {
        let data: [Model]

        struct Model: Decodable {
            let id: String
        }
    }

    private struct TranscriptionTextResponse: Decodable {
        let text: String
    }

    private struct APIErrorPayload: Decodable {
        let error: ErrorDetail

        struct ErrorDetail: Decodable {
            let message: String
            let type: String?
            let code: String?

            var modelName: String? {
                let quoted = message.split(separator: "'")
                if quoted.count >= 2 {
                    return String(quoted[1])
                }
                return nil
            }
        }
    }
}

extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}

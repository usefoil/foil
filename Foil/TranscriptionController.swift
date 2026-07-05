import Foundation

struct TranscriptProcessingResult: Equatable {
    let text: String
    let cleanupFailed: Bool
    let cleanupGroupID: String
    let cleanupGroupName: String
    let processingMode: TranscriptProcessingMode
    let cleanupProviderID: TranscriptCleanupProviderID?
    let cleanupModel: String?
}

// MARK: - Delegate protocol

@MainActor
protocol TranscriptionControllerDelegate: AnyObject {
    /// Called when transcription begins (audio is being sent to API).
    func transcriptionController(
        _ controller: TranscriptionController,
        didStartTranscribing audioURL: URL
    )

    /// Called when transcription succeeded and text is ready for paste.
    func transcriptionController(
        _ controller: TranscriptionController,
        didTranscribe text: String,
        audioURL: URL,
        cleanupFailed: Bool
    )

    /// Called when transcription failed.
    func transcriptionController(
        _ controller: TranscriptionController,
        didFail error: Error,
        errorMessage: String,
        audioURL: URL,
        format: AudioFormat
    )
}

// MARK: - TranscriptionController

/// Owns the transcription pipeline: API call → optional cleanup → delegate callbacks.
/// Has no knowledge of paste routing, history, or UI — those belong to the delegate (AppDelegate).
@MainActor
final class TranscriptionController {
    // MARK: Public

    weak var delegate: TranscriptionControllerDelegate?

    // MARK: Private

    private let transcriptionService: TranscriptionService
    private let appState: AppState
    private let usageEventStore: UsageEventStore?

    // MARK: Init

    init(
        transcriptionService: TranscriptionService,
        appState: AppState,
        usageEventStore: UsageEventStore? = nil
    ) {
        self.transcriptionService = transcriptionService
        self.appState = appState
        self.usageEventStore = usageEventStore
    }

    // MARK: - Public API

    /// Main transcription flow. Called after recording stops with a valid audio URL.
    func transcribe(
        audioURL: URL,
        format: AudioFormat,
        appContext: CleanupAppContext? = nil
    ) async {
        DiagnosticLog.write("TranscriptionController.transcribe: url=\(audioURL.lastPathComponent) format=\(format.rawValue)")

        delegate?.transcriptionController(self, didStartTranscribing: audioURL)

        let useMockTranscription: Bool
        #if DEBUG
        useMockTranscription = appState.mockTranscriptionEnabled
        #else
        useMockTranscription = false
        #endif
        DiagnosticLog.write("TranscriptionController: mock=\(useMockTranscription)")

        let provider = appState.selectedTranscriptionProvider
        let apiKey: String?
        if useMockTranscription {
            apiKey = nil
        } else {
            let resolvedKey = resolveApiKey()
            if provider.requiresAPIKey && resolvedKey == nil {
                let noKeyError = NoApiKeyError()
                delegate?.transcriptionController(
                    self,
                    didFail: noKeyError,
                    errorMessage: "No API key -- set one via the menu",
                    audioURL: audioURL,
                    format: format
                )
                return
            }
            apiKey = resolvedKey
        }

        do {
            let text: String
            var processingResult: TranscriptProcessingResult?
            var cleanupFailed = false
            let service = transcriptionService.withProvider(provider)

            if useMockTranscription {
                appState.transcriptionStage = .transcribingAudio
                try await Task.sleep(for: .seconds(2))
                text = "Mock transcription at \(Date().formatted(date: .omitted, time: .standard))"
            } else {
                appState.transcriptionStage = .transcribingAudio
                let rawText = try await service.transcribe(
                    audioFileURL: audioURL,
                    apiKey: apiKey,
                    model: appState.selectedTranscriptionModel,
                    format: format,
                    language: appState.selectedLanguage
                )
                let processed = await processTranscriptOrRaw(
                    rawText: rawText,
                    apiKey: apiKey,
                    service: service,
                    context: "transcription",
                    appContext: appContext
                )
                text = processed.text
                cleanupFailed = processed.cleanupFailed
                processingResult = processed
            }

            DiagnosticLog.write("TranscriptionController: success textLength=\(text.count) cleanupFailed=\(cleanupFailed)")
            delegate?.transcriptionController(self, didTranscribe: text, audioURL: audioURL, cleanupFailed: cleanupFailed)
            if let processingResult {
                recordUsageEvent(for: processingResult, appContext: appContext)
            }
        } catch is CancellationError {
            DiagnosticLog.write("TranscriptionController: cancelled")
            return
        } catch {
            let msg = errorMessage(from: error)
            DiagnosticLog.write("TranscriptionController: failed error=\(msg)")
            delegate?.transcriptionController(self, didFail: error, errorMessage: msg, audioURL: audioURL, format: format)
        }
    }

    /// Retry a previously failed transcription record.
    func retryTranscription(record: TranscriptionRecord) async {
        guard let audioURL = record.audioFileURL else {
            DiagnosticLog.write("TranscriptionController.retryTranscription: no audioFileURL on record")
            let sentinelError = NoApiKeyError()
            delegate?.transcriptionController(
                self,
                didFail: sentinelError,
                errorMessage: "Recording no longer available for retry",
                audioURL: URL(fileURLWithPath: ""),
                format: appState.selectedAudioFormat
            )
            return
        }
        let format = AudioFormat(rawValue: audioURL.pathExtension) ?? appState.selectedAudioFormat
        DiagnosticLog.write("TranscriptionController.retryTranscription: url=\(audioURL.lastPathComponent)")

        let provider = appState.selectedTranscriptionProvider
        let apiKey = appState.selectedProviderApiKey
        if provider.requiresAPIKey && apiKey == nil {
            let noKeyError = NoApiKeyError()
            delegate?.transcriptionController(
                self,
                didFail: noKeyError,
                errorMessage: "No API key -- set one via the menu",
                audioURL: audioURL,
                format: format
            )
            return
        }

        do {
            let service = transcriptionService.withProvider(provider)
            appState.transcriptionStage = .transcribingAudio
            let rawText = try await service.transcribe(
                audioFileURL: audioURL,
                apiKey: apiKey,
                model: appState.selectedTranscriptionModel,
                format: format,
                language: appState.selectedLanguage
            )
            let processed = await processTranscriptOrRaw(
                rawText: rawText,
                apiKey: apiKey,
                service: service,
                context: "retry"
            )
            DiagnosticLog.write("TranscriptionController.retryTranscription: success cleanupFailed=\(processed.cleanupFailed)")
            delegate?.transcriptionController(
                self,
                didTranscribe: processed.text,
                audioURL: audioURL,
                cleanupFailed: processed.cleanupFailed
            )
        } catch is CancellationError {
            DiagnosticLog.write("TranscriptionController.retryTranscription: cancelled")
            return
        } catch {
            let msg = errorMessage(from: error)
            DiagnosticLog.write("TranscriptionController.retryTranscription: failed error=\(msg)")
            delegate?.transcriptionController(self, didFail: error, errorMessage: msg, audioURL: audioURL, format: format)
        }
    }

    private func resolveApiKey() -> String? {
        if let envKey = ProcessInfo.processInfo.environment["E2E_API_KEY"],
           !envKey.isEmpty,
           AppDelegate.isE2ETranscriptionSmokeProcess() {
            DiagnosticLog.write("TranscriptionController: using E2E_API_KEY from environment")
            return envKey
        }
        return appState.selectedProviderApiKey
    }

    // MARK: - Internal helpers

    /// Apply transcript processing mode (cleanup/raw).
    func recleanTranscript(
        rawText: String,
        service: TranscriptionService? = nil,
        context: String = "historyReclean",
        appContext: CleanupAppContext? = nil
    ) async -> TranscriptProcessingResult {
        await processTranscriptOrRaw(
            rawText: rawText,
            apiKey: nil,
            service: service,
            context: context,
            appContext: appContext
        )
    }

    /// Apply transcript processing mode (cleanup/raw).
    func processTranscriptOrRaw(
        rawText: String,
        apiKey: String?,
        service: TranscriptionService? = nil,
        context: String,
        appContext: CleanupAppContext? = nil
    ) async -> TranscriptProcessingResult {
        let resolution = appState.resolveCleanupGroup(for: appContext)
        let processingMode = resolution.processingMode
        guard processingMode != .raw else {
            DiagnosticLog.write("\(context): transcript processing skipped cleanupGroup=\(resolution.group.id) mode=\(processingMode.rawValue)")
            return TranscriptProcessingResult(
                text: rawText,
                cleanupFailed: false,
                cleanupGroupID: resolution.group.id,
                cleanupGroupName: resolution.group.name,
                processingMode: processingMode,
                cleanupProviderID: nil,
                cleanupModel: nil
            )
        }

        let cleanupProvider = resolution.provider
        guard cleanupProvider.id != .none else {
            DiagnosticLog.write("\(context): transcript processing skipped because cleanup provider is none")
            return TranscriptProcessingResult(
                text: rawText,
                cleanupFailed: false,
                cleanupGroupID: resolution.group.id,
                cleanupGroupName: resolution.group.name,
                processingMode: processingMode,
                cleanupProviderID: nil,
                cleanupModel: nil
            )
        }

        let cleanupApiKey: String?
        switch cleanupProvider.id {
        case .none:
            cleanupApiKey = nil
        case .groq:
            cleanupApiKey = resolveCleanupApiKey(for: .groq)
        case .openAI:
            cleanupApiKey = resolveCleanupApiKey(for: .openAI)
        case .customOpenAICompatibleChat:
            cleanupApiKey = resolveCleanupApiKey(for: .customOpenAICompatibleChat)
        }

        let service = service ?? transcriptionService
        appState.transcriptionStage = .cleaningTranscript
        let cleanupRequest = TranscriptCleanupRequest(
            rawTranscript: rawText,
            mode: processingMode,
            customPrompt: resolution.customPrompt,
            vocabularyCorrections: appState.vocabularyCorrections,
            preferredTerms: appState.preferredTerms,
            provider: cleanupProvider
        )
        do {
            let text = try await service.processTranscript(
                request: cleanupRequest,
                apiKey: cleanupApiKey,
            )
            writeE2ECleanupReceipt(
                status: "applied",
                provider: cleanupProvider,
                mode: processingMode,
                inputLength: rawText.count,
                outputLength: text.count
            )
            return TranscriptProcessingResult(
                text: text,
                cleanupFailed: false,
                cleanupGroupID: resolution.group.id,
                cleanupGroupName: resolution.group.name,
                processingMode: processingMode,
                cleanupProviderID: cleanupProvider.id,
                cleanupModel: cleanupProvider.model
            )
        } catch {
            DiagnosticLog.write("\(context): cleanup failed mappedMessage=\(errorMessage(from: error))")
            writeE2ECleanupReceipt(
                status: "failed",
                provider: cleanupProvider,
                mode: processingMode,
                inputLength: rawText.count,
                outputLength: rawText.count,
                error: errorMessage(from: error)
            )
            return TranscriptProcessingResult(
                text: rawText,
                cleanupFailed: true,
                cleanupGroupID: resolution.group.id,
                cleanupGroupName: resolution.group.name,
                processingMode: processingMode,
                cleanupProviderID: cleanupProvider.id,
                cleanupModel: cleanupProvider.model
            )
        }
    }

    private func recordUsageEvent(for result: TranscriptProcessingResult, appContext: CleanupAppContext?) {
        guard let usageEventStore else { return }
        usageEventStore.isEnabled = appState.usageMetricsEnabled
        let event = UsageEvent(
            wordCount: Self.wordCount(in: result.text),
            sourceAppName: appContext?.displayName,
            sourceBundleIdentifier: appContext?.bundleIdentifier,
            cleanupGroupID: result.cleanupGroupID,
            cleanupGroupName: result.cleanupGroupName,
            processingMode: result.processingMode,
            cleanupProviderID: result.cleanupProviderID,
            cleanupModel: result.cleanupModel,
            cleanupFailed: result.cleanupFailed,
            outcome: result.cleanupFailed ? .cleanupFailedFallback : .success
        )
        let mutationResult = usageEventStore.record(event)
        if case .failed(let error) = mutationResult {
            DiagnosticLog.write("TranscriptionController: usage event record failed error=\(error.rawValue)")
        }
    }

    private static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    func transformTranscript(
        rawText: String,
        transformKind: HistoryTransformKind,
        service: TranscriptionService? = nil,
        context: String
    ) async -> (text: String, transformFailed: Bool) {
        let cleanupProvider = appState.selectedTranscriptCleanupProvider
        guard cleanupProvider.id != .none else {
            DiagnosticLog.write("\(context): history transform skipped because cleanup provider is none")
            return (rawText, true)
        }

        let cleanupApiKey: String?
        switch cleanupProvider.id {
        case .none:
            cleanupApiKey = nil
        case .groq:
            cleanupApiKey = resolveCleanupApiKey(for: .groq)
        case .openAI:
            cleanupApiKey = resolveCleanupApiKey(for: .openAI)
        case .customOpenAICompatibleChat:
            cleanupApiKey = resolveCleanupApiKey(for: .customOpenAICompatibleChat)
        }

        let service = service ?? transcriptionService
        let cleanupRequest = TranscriptCleanupRequest(
            rawTranscript: rawText,
            mode: .rewriteClearly,
            customPrompt: transformKind.prompt,
            vocabularyCorrections: appState.vocabularyCorrections,
            preferredTerms: appState.preferredTerms,
            provider: cleanupProvider
        )
        do {
            let text = try await service.processTranscript(
                request: cleanupRequest,
                apiKey: cleanupApiKey,
            )
            DiagnosticLog.write("\(context): history transform applied kind=\(transformKind.rawValue) provider=\(cleanupProvider.id.rawValue) inputLength=\(rawText.count) outputLength=\(text.count)")
            return (text, false)
        } catch {
            DiagnosticLog.write("\(context): history transform failed kind=\(transformKind.rawValue) mappedMessage=\(errorMessage(from: error))")
            return (rawText, true)
        }
    }

    private func writeE2ECleanupReceipt(
        status: String,
        provider: TranscriptCleanupProvider,
        mode: TranscriptProcessingMode,
        inputLength: Int,
        outputLength: Int,
        error: String? = nil
    ) {
        let env = ProcessInfo.processInfo.environment
        guard let receiptPath = env["E2E_CLEANUP_RECEIPT_PATH"], !receiptPath.isEmpty else {
            return
        }

        var lines = [
            "status=\(status)",
            "provider=\(provider.id.rawValue)",
            "mode=\(mode.rawValue)",
            "model=\(provider.model)",
            "input_length=\(inputLength)",
            "output_length=\(outputLength)"
        ]
        if let error {
            lines.append("error=\(error.replacingOccurrences(of: "\n", with: " "))")
        }
        let body = lines.joined(separator: "\n") + "\n"
        try? body.write(toFile: receiptPath, atomically: true, encoding: .utf8)
    }

    private func resolveCleanupApiKey(for providerID: TranscriptCleanupProviderID) -> String? {
        if AppDelegate.isE2ETranscriptionSmokeProcess() {
            let env = ProcessInfo.processInfo.environment
            if let cleanupKey = env["E2E_CLEANUP_API_KEY"], !cleanupKey.isEmpty {
                DiagnosticLog.write("TranscriptionController: using E2E_CLEANUP_API_KEY from environment")
                return cleanupKey
            }
            if [.groq, .openAI].contains(providerID),
               let sharedKey = env["E2E_API_KEY"],
               !sharedKey.isEmpty {
                DiagnosticLog.write("TranscriptionController: using E2E_API_KEY for cleanup")
                return sharedKey
            }
        }

        switch providerID {
        case .none:
            return nil
        case .groq:
            return KeychainHelper.readApiKey(for: .groq)
        case .openAI:
            return KeychainHelper.readApiKey(for: .openAI)
        case .customOpenAICompatibleChat:
            return KeychainHelper.readCleanupApiKey(for: .customOpenAICompatibleChat)
        }
    }

    /// Maps all error types to user-facing strings.
    func errorMessage(from error: Error) -> String {
        switch error {
        case TranscriptionService.TranscriptionError.invalidApiKey:
            "Invalid API key"
        case TranscriptionService.TranscriptionError.invalidProviderURL:
            "Invalid provider URL"
        case TranscriptionService.TranscriptionError.fileTooLarge:
            "Recording too long"
        case AudioRecorder.RecordingError.recordingTooLong:
            "Recording too long"
        case AudioRecorder.RecordingError.audioFormatUnavailable:
            "Audio format unavailable -- please restart the app"
        case AudioRecorder.RecordingError.deviceSelectionFailed:
            "Selected input device is unavailable"
        case TranscriptionService.TranscriptionError.rateLimited:
            "\(appState.selectedTranscriptionProvider.displayName) rate limit reached"
        case TranscriptionService.TranscriptionError.quotaExceeded:
            "\(appState.selectedTranscriptionProvider.displayName) quota exceeded"
        case TranscriptionService.TranscriptionError.modelUnavailable(let model):
            "Model unavailable: \(model)"
        case TranscriptionService.TranscriptionError.badRequest:
            "\(appState.selectedTranscriptionProvider.displayName) rejected the request"
        case TranscriptionService.TranscriptionError.serverError:
            "\(appState.selectedTranscriptionProvider.displayName) is temporarily unavailable"
        case TranscriptionService.TranscriptionError.apiError(let code, _):
            "API error (\(code))"
        case let urlError as URLError where urlError.code == .notConnectedToInternet:
            "No internet connection"
        case let urlError as URLError where urlError.code == .timedOut:
            "Request timed out"
        case let urlError as URLError where urlError.code == .cannotConnectToHost
            || urlError.code == .cannotFindHost:
            "Cannot reach \(appState.selectedTranscriptionProvider.displayName)"
        default:
            "Transcription failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supporting types

/// Sentinel error thrown when no API key is stored in the keychain.
struct NoApiKeyError: Error {}

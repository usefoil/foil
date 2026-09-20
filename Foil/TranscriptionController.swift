import Foundation

struct TranscriptProcessingResult: Equatable {
    let text: String
    let originalText: String
    let cleanupFailed: Bool
    let cleanupGroupID: String
    let cleanupGroupName: String
    let processingMode: TranscriptProcessingMode
    let cleanupProviderID: TranscriptCleanupProviderID?
    let cleanupModel: String?
    let localCorrectionRevision: Int
    let localReplacementCount: Int
    let localCorrectionFallbackReason: LocalCorrectionFallbackReason?

    init(
        text: String,
        originalText: String? = nil,
        cleanupFailed: Bool,
        cleanupGroupID: String,
        cleanupGroupName: String,
        processingMode: TranscriptProcessingMode,
        cleanupProviderID: TranscriptCleanupProviderID?,
        cleanupModel: String?,
        localCorrectionRevision: Int = 0,
        localReplacementCount: Int = 0,
        localCorrectionFallbackReason: LocalCorrectionFallbackReason? = nil
    ) {
        self.text = text
        self.originalText = originalText ?? text
        self.cleanupFailed = cleanupFailed
        self.cleanupGroupID = cleanupGroupID
        self.cleanupGroupName = cleanupGroupName
        self.processingMode = processingMode
        self.cleanupProviderID = cleanupProviderID
        self.cleanupModel = cleanupModel
        self.localCorrectionRevision = localCorrectionRevision
        self.localReplacementCount = localReplacementCount
        self.localCorrectionFallbackReason = localCorrectionFallbackReason
    }
}

struct TranscriptProcessingSnapshot {
    let resolution: CleanupGroupResolution
    let localCorrectionGroupID: String?
    let localCorrections: LocalCorrectionExecutionSnapshot
    let vocabularyCorrections: [VocabularyCorrection]
    let preferredTerms: [String]
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
        originalText: String,
        audioURL: URL,
        cleanupFailed: Bool,
        localCorrectionFallbackReason: LocalCorrectionFallbackReason?
    )

    /// Called when a provider succeeds but returns no recognizable speech.
    func transcriptionController(
        _ controller: TranscriptionController,
        didDetectNoRecognizableAudio audioURL: URL,
        format: AudioFormat
    )

    /// Called when transcription failed.
    func transcriptionController(
        _ controller: TranscriptionController,
        didFail error: Error,
        errorMessage: String,
        audioURL: URL,
        format: AudioFormat,
        appContext: CleanupAppContext?
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
        appContext: CleanupAppContext? = nil,
        processingSnapshot: TranscriptProcessingSnapshot? = nil
    ) async {
        DiagnosticLog.write("TranscriptionController.transcribe: url=\(audioURL.lastPathComponent) format=\(format.rawValue)")

        delegate?.transcriptionController(self, didStartTranscribing: audioURL)

        let isPractice = appState.onboardingPracticeActive
        let useMockTranscription: Bool
        #if DEBUG
        useMockTranscription = appState.mockTranscriptionEnabled && !isPractice
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
                    format: format,
                    appContext: appContext
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
            let processingSnapshot = processingSnapshot ?? captureProcessingSnapshot(appContext: appContext)

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
                guard !TranscriptionService.isNoRecognizableAudioTranscript(rawText) else {
                    DiagnosticLog.write("TranscriptionController: provider returned no recognizable audio")
                    delegate?.transcriptionController(
                        self,
                        didDetectNoRecognizableAudio: audioURL,
                        format: format
                    )
                    return
                }
                if isPractice {
                    // Practice tests the selected transcription path, without a second provider or usage record.
                    try Task.checkCancellation()
                    delegate?.transcriptionController(
                        self,
                        didTranscribe: rawText,
                        originalText: rawText,
                        audioURL: audioURL,
                        cleanupFailed: false,
                        localCorrectionFallbackReason: nil
                    )
                    return
                }
                let processed = await processCapturedTranscript(
                    rawText: rawText,
                    apiKey: apiKey,
                    service: service,
                    context: "transcription",
                    snapshot: processingSnapshot
                )
                text = processed.text
                cleanupFailed = processed.cleanupFailed
                processingResult = processed
            }

            try Task.checkCancellation()
            DiagnosticLog.write("TranscriptionController: success textLength=\(text.count) cleanupFailed=\(cleanupFailed)")
            delegate?.transcriptionController(
                self,
                didTranscribe: text,
                originalText: processingResult?.originalText ?? text,
                audioURL: audioURL,
                cleanupFailed: cleanupFailed,
                localCorrectionFallbackReason: processingResult?.localCorrectionFallbackReason
            )
            if let processingResult {
                recordUsageEvent(for: processingResult, appContext: appContext)
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: audioURL)
            DiagnosticLog.write("TranscriptionController: cancelled")
            return
        } catch {
            let msg = errorMessage(from: error)
            DiagnosticLog.write("TranscriptionController: failed error=\(msg)")
            delegate?.transcriptionController(
                self,
                didFail: error,
                errorMessage: msg,
                audioURL: audioURL,
                format: format,
                appContext: appContext
            )
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
                format: appState.selectedAudioFormat,
                appContext: record.sourceAppContext
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
                format: format,
                appContext: record.sourceAppContext
            )
            return
        }

        do {
            let service = transcriptionService.withProvider(provider)
            let retryAppContext = record.sourceAppContext
            let processingSnapshot = captureProcessingSnapshot(appContext: retryAppContext)
            appState.transcriptionStage = .transcribingAudio
            let rawText = try await service.transcribe(
                audioFileURL: audioURL,
                apiKey: apiKey,
                model: appState.selectedTranscriptionModel,
                format: format,
                language: appState.selectedLanguage
            )
            guard !TranscriptionService.isNoRecognizableAudioTranscript(rawText) else {
                DiagnosticLog.write("TranscriptionController.retryTranscription: provider returned no recognizable audio")
                delegate?.transcriptionController(
                    self,
                    didDetectNoRecognizableAudio: audioURL,
                    format: format
                )
                return
            }
            let processed = await processCapturedTranscript(
                rawText: rawText,
                apiKey: apiKey,
                service: service,
                context: "retry",
                snapshot: processingSnapshot
            )
            DiagnosticLog.write("TranscriptionController.retryTranscription: success cleanupFailed=\(processed.cleanupFailed)")
            delegate?.transcriptionController(
                self,
                didTranscribe: processed.text,
                originalText: processed.originalText,
                audioURL: audioURL,
                cleanupFailed: processed.cleanupFailed,
                localCorrectionFallbackReason: processed.localCorrectionFallbackReason
            )
        } catch is CancellationError {
            DiagnosticLog.write("TranscriptionController.retryTranscription: cancelled")
            return
        } catch {
            let msg = errorMessage(from: error)
            DiagnosticLog.write("TranscriptionController.retryTranscription: failed error=\(msg)")
            delegate?.transcriptionController(
                self,
                didFail: error,
                errorMessage: msg,
                audioURL: audioURL,
                format: format,
                appContext: record.sourceAppContext
            )
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
        var snapshot = captureProcessingSnapshot(appContext: appContext)
        snapshot = TranscriptProcessingSnapshot(
            resolution: snapshot.resolution,
            localCorrectionGroupID: snapshot.localCorrectionGroupID,
            localCorrections: LocalCorrectionExecutionSnapshot(
                revision: snapshot.localCorrections.revision,
                enabled: false,
                compiled: snapshot.localCorrections.compiled
            ),
            vocabularyCorrections: snapshot.vocabularyCorrections,
            preferredTerms: snapshot.preferredTerms
        )
        return await processCapturedTranscript(
            rawText: rawText,
            apiKey: nil,
            service: service,
            context: context,
            snapshot: snapshot
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
        await processCapturedTranscript(
            rawText: rawText,
            apiKey: apiKey,
            service: service,
            context: context,
            snapshot: captureProcessingSnapshot(appContext: appContext)
        )
    }

    private func processCapturedTranscript(
        rawText: String,
        apiKey: String?,
        service: TranscriptionService? = nil,
        context: String,
        snapshot: TranscriptProcessingSnapshot
    ) async -> TranscriptProcessingResult {
        let resolution = snapshot.resolution
        let processingMode = resolution.processingMode
        let localResult = LocalCorrectionEngine.correct(
            rawText,
            activeGroup: snapshot.localCorrectionGroupID,
            enabled: snapshot.localCorrections.enabled,
            compiled: snapshot.localCorrections.compiled
        )
        if snapshot.localCorrections.enabled ||
            localResult.replacementCount > 0 ||
            localResult.fallbackReason != .processingDisabled {
            DiagnosticLog.write(
                "\(context): local corrections revision=\(snapshot.localCorrections.revision) replacements=\(localResult.replacementCount) fallback=\(localResult.fallbackReason?.rawValue ?? "none")"
            )
        }
        if localResult.fallbackReason == .inputTooLarge {
            return TranscriptProcessingResult(
                text: rawText,
                originalText: rawText,
                cleanupFailed: false,
                cleanupGroupID: resolution.group.id,
                cleanupGroupName: resolution.group.name,
                processingMode: processingMode,
                cleanupProviderID: nil,
                cleanupModel: nil,
                localCorrectionRevision: snapshot.localCorrections.revision,
                localReplacementCount: 0,
                localCorrectionFallbackReason: .inputTooLarge
            )
        }
        guard processingMode != .raw else {
            DiagnosticLog.write("\(context): transcript processing skipped cleanupGroup=\(resolution.group.id) mode=\(processingMode.rawValue)")
            return TranscriptProcessingResult(
                text: localResult.text,
                originalText: rawText,
                cleanupFailed: false,
                cleanupGroupID: resolution.group.id,
                cleanupGroupName: resolution.group.name,
                processingMode: processingMode,
                cleanupProviderID: nil,
                cleanupModel: nil,
                localCorrectionRevision: snapshot.localCorrections.revision,
                localReplacementCount: localResult.replacementCount,
                localCorrectionFallbackReason: localResult.fallbackReason
            )
        }

        let cleanupProvider = resolution.provider
        guard cleanupProvider.id != .none else {
            DiagnosticLog.write("\(context): transcript processing skipped because cleanup provider is none")
            return TranscriptProcessingResult(
                text: localResult.text,
                originalText: rawText,
                cleanupFailed: false,
                cleanupGroupID: resolution.group.id,
                cleanupGroupName: resolution.group.name,
                processingMode: processingMode,
                cleanupProviderID: nil,
                cleanupModel: nil,
                localCorrectionRevision: snapshot.localCorrections.revision,
                localReplacementCount: localResult.replacementCount,
                localCorrectionFallbackReason: localResult.fallbackReason
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
            rawTranscript: localResult.text,
            mode: processingMode,
            customPrompt: resolution.customPrompt,
            vocabularyCorrections: snapshot.vocabularyCorrections,
            preferredTerms: snapshot.preferredTerms,
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
                inputLength: localResult.text.count,
                outputLength: text.count
            )
            return TranscriptProcessingResult(
                text: text,
                originalText: rawText,
                cleanupFailed: false,
                cleanupGroupID: resolution.group.id,
                cleanupGroupName: resolution.group.name,
                processingMode: processingMode,
                cleanupProviderID: cleanupProvider.id,
                cleanupModel: cleanupProvider.model,
                localCorrectionRevision: snapshot.localCorrections.revision,
                localReplacementCount: localResult.replacementCount,
                localCorrectionFallbackReason: localResult.fallbackReason
            )
        } catch {
            DiagnosticLog.write("\(context): cleanup failed mappedMessage=\(errorMessage(from: error))")
            writeE2ECleanupReceipt(
                status: "failed",
                provider: cleanupProvider,
                mode: processingMode,
                inputLength: localResult.text.count,
                outputLength: localResult.text.count,
                error: errorMessage(from: error)
            )
            return TranscriptProcessingResult(
                text: localResult.text,
                originalText: rawText,
                cleanupFailed: true,
                cleanupGroupID: resolution.group.id,
                cleanupGroupName: resolution.group.name,
                processingMode: processingMode,
                cleanupProviderID: cleanupProvider.id,
                cleanupModel: cleanupProvider.model,
                localCorrectionRevision: snapshot.localCorrections.revision,
                localReplacementCount: localResult.replacementCount,
                localCorrectionFallbackReason: localResult.fallbackReason
            )
        }
    }

    func captureProcessingSnapshot(appContext: CleanupAppContext?) -> TranscriptProcessingSnapshot {
        let hasKnownAppContext = appContext.map {
            $0.displayName != nil || $0.bundleIdentifier != nil || $0.appPath != nil
        } ?? false
        let resolution = appState.resolveCleanupGroup(for: appContext)
        return TranscriptProcessingSnapshot(
            resolution: resolution,
            localCorrectionGroupID: hasKnownAppContext ? resolution.group.id : nil,
            localCorrections: appState.localCorrectionExecutionSnapshot(),
            vocabularyCorrections: appState.vocabularyCorrections,
            preferredTerms: appState.preferredTerms
        )
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

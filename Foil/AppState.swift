import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class AppState {
    enum Status: Equatable {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    enum TransientResult: Equatable {
        case pasted(PasteDelivery)
        case clipboardFallback
    }

    enum TranscriptionStage: Equatable {
        case transcribingAudio
        case cleaningTranscript
        case pasting
    }

    enum PermissionState: Equatable {
        case unknown
        case ready
        case needsAction(String)
    }

    enum SetupCheckState: Equatable {
        case idle
        case running
        case passed(Date)
        case failed(String)
    }

    enum ProviderConnectionTestState: Equatable {
        case idle
        case running
        case succeeded(String)
        case warning(String)
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    enum LocalWhisperServerState: Equatable {
        case idle
        case starting(String)
        case running(String)
        case alreadyRunning(String)
        case missingBinary(String)
        case missingModel(String)
        case failed(String)

        var isStarting: Bool {
            if case .starting = self { return true }
            return false
        }
    }

    enum SessionTone: Equatable {
        case neutral
        case active
        case progress
        case success
        case warning
    }

    enum SessionAction: Equatable {
        case retry
        case openAccessibility
        case openMicrophone
        case addKey
        case pasteAgain
        case copy

        var title: String {
            switch self {
            case .retry: "Retry"
            case .openAccessibility, .openMicrophone: "Open"
            case .addKey: "Add Key"
            case .pasteAgain: "Again"
            case .copy: "Copy"
            }
        }
    }

    struct SessionPresentation: Equatable {
        let title: String
        let detail: String
        let timerText: String?
        let systemImage: String
        let tone: SessionTone
        let primaryAction: SessionAction?
    }

    private(set) var status: Status = .idle

    // MARK: - Timer state

    var recordingStartTime: Date?
    var recordingDuration: TimeInterval = 0
    var transcribingIconFrame: Int = 0
    var lastPasteSummary: String?
    var capturedTargetName: String?
    var feedbackMessage: String?
    var clipboardFeedback: String?
    var transientResult: TransientResult?
    var transcriptionStage: TranscriptionStage?
    private(set) var audioLevelHistory: [Float] = Array(repeating: 0, count: 18)
    var floatingStatusTransientVisible = false
    var floatingStatusDismissed = false
    var accessibilityState: PermissionState = .unknown
    var microphoneState: PermissionState = .unknown
    var apiKeyState: PermissionState = .unknown
    var setupCheckState: SetupCheckState = .idle
    var setupCheckSuccessDetail = "Ready to record"
    var providerConnectionTestState: ProviderConnectionTestState = .idle
    var cleanupConnectionTestState: ProviderConnectionTestState = .idle
    var localWhisperServerState: LocalWhisperServerState = .idle

    static let noMicrophoneDetectedMessage = "No microphone detected"
    static let selectedMicrophoneUnavailableMessage = "Selected microphone unavailable"
    static let microphonePromptTimedOutMessage = "Open Microphone privacy and allow \(AppBrand.name)"

    // MARK: - UserDefaults-backed preferences
    //
    // These are stored properties so that @Observable can track mutations.
    // Each didSet syncs the value back to UserDefaults for persistence.

    private static var defaults: UserDefaults {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let defaults = UserDefaults(suiteName: "com.neonwatty.Foil.UITests") {
            return defaults
        }
        return .standard
    }

    private static var defaultsDomainName: String {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return "com.neonwatty.Foil.UITests"
        }
        return Bundle.main.bundleIdentifier ?? "com.neonwatty.Foil"
    }

    private static var localBridgeDeviceName: String {
        Host.current().localizedName ?? "This Mac"
    }

    let localPairingBridgeService: LocalPairingBridgeService

    var soundEffectsEnabled: Bool = true {
        didSet { Self.defaults.set(soundEffectsEnabled, forKey: "soundEffectsEnabled") }
    }

    var recordingStartSoundCue: RecordingSoundCue = .defaultStart {
        didSet { Self.defaults.set(recordingStartSoundCue.rawValue, forKey: "recordingStartSoundCue") }
    }

    var recordingEndSoundCue: RecordingSoundCue = .defaultEnd {
        didSet { Self.defaults.set(recordingEndSoundCue.rawValue, forKey: "recordingEndSoundCue") }
    }

    var selectedModel: String = "whisper-large-v3-turbo" {
        didSet {
            Self.defaults.set(selectedModel, forKey: "whisperModel")
            resetProviderConnectionTest()
        }
    }

    var selectedTranscriptionProviderID: TranscriptionProviderID = .groq {
        didSet {
            Self.defaults.set(selectedTranscriptionProviderID.rawValue, forKey: "transcriptionProvider")
            guard !isSynchronizingProviderSelection else { return }
            isSynchronizingProviderSelection = true
            selectedTranscriptionProviderPresetID = Self.defaultPresetID(for: selectedTranscriptionProviderID)
            isSynchronizingProviderSelection = false
            handleTranscriptionProviderSelectionChanged()
        }
    }

    var selectedTranscriptionProviderPresetID: TranscriptionProviderPresetID = .groq {
        didSet {
            Self.defaults.set(selectedTranscriptionProviderPresetID.rawValue, forKey: "transcriptionProviderPreset")
            guard !isSynchronizingProviderSelection else { return }
            isSynchronizingProviderSelection = true
            selectedTranscriptionProviderID = selectedTranscriptionProviderPreset.providerID
            isSynchronizingProviderSelection = false
            handleTranscriptionProviderSelectionChanged()
        }
    }

    var customTranscriptionBaseURL: String = "http://127.0.0.1:8080/v1" {
        didSet {
            Self.defaults.set(customTranscriptionBaseURL, forKey: "customTranscriptionBaseURL")
            resetProviderConnectionTest()
        }
    }

    var customTranscriptionModel: String = "whisper-1" {
        didSet {
            Self.defaults.set(customTranscriptionModel, forKey: "customTranscriptionModel")
            resetProviderConnectionTest()
        }
    }

    var selectedAudioFormat: AudioFormat = .m4a {
        didSet { Self.defaults.set(selectedAudioFormat.rawValue, forKey: "audioFormat") }
    }

    var selectedLanguage: Language = .auto {
        didSet { Self.defaults.set(selectedLanguage.rawValue, forKey: "language") }
    }

    var transcriptProcessingMode: TranscriptProcessingMode = .raw {
        didSet { Self.defaults.set(transcriptProcessingMode.rawValue, forKey: "transcriptProcessingMode") }
    }

    var transcriptCleanupModel: String = "llama-3.1-8b-instant" {
        didSet {
            Self.defaults.set(transcriptCleanupModel, forKey: "transcriptCleanupModel")
            resetCleanupConnectionTest()
        }
    }

    var openAITranscriptCleanupModel: String = "gpt-5.4-mini" {
        didSet {
            Self.defaults.set(openAITranscriptCleanupModel, forKey: "openAITranscriptCleanupModel")
            resetCleanupConnectionTest()
        }
    }

    var transcriptCleanupProviderID: TranscriptCleanupProviderID = .groq {
        didSet {
            Self.defaults.set(transcriptCleanupProviderID.rawValue, forKey: "transcriptCleanupProvider")
            resetCleanupConnectionTest()
        }
    }

    var customTranscriptCleanupBaseURL: String = "http://127.0.0.1:11434/v1" {
        didSet {
            Self.defaults.set(customTranscriptCleanupBaseURL, forKey: "customTranscriptCleanupBaseURL")
            resetCleanupConnectionTest()
        }
    }

    var customTranscriptCleanupModel: String = "llama3.1:8b" {
        didSet {
            Self.defaults.set(customTranscriptCleanupModel, forKey: "customTranscriptCleanupModel")
            resetCleanupConnectionTest()
        }
    }

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

    var keepOnClipboard: Bool = false {
        didSet { Self.defaults.set(keepOnClipboard, forKey: "keepOnClipboard") }
    }

    var showFloatingStatus: Bool = false {
        didSet {
            Self.defaults.set(showFloatingStatus, forKey: "showFloatingStatus")
            if showFloatingStatus {
                floatingStatusDismissed = false
            }
        }
    }

    var asyncPasteEnabled: Bool = false {
        didSet { Self.defaults.set(asyncPasteEnabled, forKey: "asyncPasteEnabled") }
    }

    var queuedPasteEnabled: Bool = false {
        didSet { Self.defaults.set(queuedPasteEnabled, forKey: "queuedPasteEnabled") }
    }

    var queuedPasteMode: QueuedPasteMode = .stepThrough {
        didSet { Self.defaults.set(queuedPasteMode.rawValue, forKey: "queuedPasteMode") }
    }

    static let queuedPasteDeliveryShortcut = QueuedPasteDeliveryShortcut.default

    var queuedPasteDeliveryShortcutLabel: String {
        Self.queuedPasteDeliveryShortcut.displayName
    }

    var queuedPasteDeliveryShortcutConflictsWithRecordingHotkey: Bool {
        guard hotkeyChoice == .custom else { return false }
        return Self.queuedPasteDeliveryShortcut.conflictsWithCustomRecordingShortcut(
            keyCode: customHotkeyKeyCode,
            modifiers: customHotkeyModifiers
        )
    }

    var experimentalSkyLightPasteEnabled: Bool = false {
        didSet { Self.defaults.set(experimentalSkyLightPasteEnabled, forKey: "experimentalSkyLightPasteEnabled") }
    }

    var pauseBrowserMediaWhileRecording: Bool = false {
        didSet { Self.defaults.set(pauseBrowserMediaWhileRecording, forKey: "pauseBrowserMediaWhileRecording") }
    }

    var otherAudioPolicyDiagnosticDescription: String {
        pauseBrowserMediaWhileRecording ? "pause supported browser media" : "unaffected"
    }

    var localBridgeEnabled: Bool = false {
        didSet {
            Self.defaults.set(localBridgeEnabled, forKey: "localBridgeEnabled")
            localPairingBridgeService.setEnabled(
                localBridgeEnabled,
                appState: self,
                deviceName: Self.localBridgeDeviceName
            )
            if !localBridgeEnabled {
                localBridgePairingState = .unpaired
                localBridgePairingSession = nil
                localBridgeTrustedPeer = nil
                localBridgeLastReceipt = nil
                localBridgeStatusMessage = "Local bridge off"
            } else {
                syncLocalBridgePresentationAfterEnable()
            }
        }
    }

    var localBridgePairingState: LocalBridgePairingState = .unpaired
    var localBridgePairingSession: LocalBridgePairingSession?
    var localBridgeTrustedPeer: LocalBridgeTrustedPeer?
    var localBridgeLastReceipt: RouteReceipt?
    var localBridgeStatusMessage = "Local bridge off"
    var localBridgePairingPayloadText: String? {
        guard let localBridgePairingSession else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(localBridgePairingSession) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    #if DEBUG
    var mockTranscriptionEnabled: Bool = false {
        didSet { Self.defaults.set(mockTranscriptionEnabled, forKey: "mockTranscriptionEnabled") }
    }
    #endif

    var recordingMode: HotkeyMonitor.RecordingMode = .hold {
        didSet { Self.defaults.set(recordingMode.rawValue, forKey: "recordingMode") }
    }

    var hotkeyChoice: HotkeyMonitor.HotkeyChoice = .rightCommand {
        didSet { Self.defaults.set(hotkeyChoice.rawValue, forKey: "hotkeyChoice") }
    }

    var customHotkeyKeyCode: UInt16 = 0 {
        didSet { Self.defaults.set(Int(customHotkeyKeyCode), forKey: "customHotkeyKeyCode") }
    }

    var customHotkeyModifiers: UInt64 = 0 {
        didSet { Self.defaults.set(customHotkeyModifiers, forKey: "customHotkeyModifiers") }
    }

    var customHotkeyLabel: String = "" {
        didSet { Self.defaults.set(customHotkeyLabel, forKey: "customHotkeyLabel") }
    }

    var selectedInputDeviceUID: String? {
        didSet {
            if let uid = selectedInputDeviceUID {
                Self.defaults.set(uid, forKey: "selectedInputDeviceUID")
            } else {
                Self.defaults.removeObject(forKey: "selectedInputDeviceUID")
            }
        }
    }

    private var isSynchronizingProviderSelection = false

    var selectedProviderUsesSharedApiKey: Bool {
        selectedTranscriptionProviderPresetID != .localWhisperCPP
    }

    var selectedProviderApiKey: String? {
        guard selectedProviderUsesSharedApiKey else { return nil }
        return KeychainHelper.readApiKey(for: selectedTranscriptionProviderID)
    }

    var hasApiKey: Bool { selectedProviderApiKey != nil }

    var selectedTranscriptionProviderPreset: TranscriptionProviderPreset {
        switch selectedTranscriptionProviderPresetID {
        case .groq:
            return .groq
        case .openAIWhisper:
            return .openAIWhisper
        case .localWhisperCPP:
            return .localWhisperCPP
        case .customOpenAICompatible:
            return .customOpenAICompatible(
                baseURL: customTranscriptionBaseURLValue,
                model: customTranscriptionModel
            )
        }
    }

    var selectedTranscriptionProvider: TranscriptionProvider {
        switch selectedTranscriptionProviderPresetID {
        case .groq:
            var provider = TranscriptionProvider.groq
            provider = TranscriptionProvider(
                id: provider.id,
                displayName: provider.displayName,
                baseURL: provider.baseURL,
                transcriptionModel: selectedModel,
                requiresAPIKey: provider.requiresAPIKey,
                supportsModelValidation: provider.supportsModelValidation,
                supportsTranscriptProcessing: provider.supportsTranscriptProcessing
            )
            return provider
        case .openAIWhisper:
            return .openAIWhisper
        case .localWhisperCPP:
            let preset = TranscriptionProviderPreset.localWhisperCPP
            return .openAICompatible(
                baseURL: preset.baseURL!,
                model: preset.model,
                displayName: preset.displayName,
                requiresAPIKey: preset.requiresAPIKey
            )
        case .customOpenAICompatible:
            let fallback = URL(string: "http://127.0.0.1:8080/v1")!
            let baseURL = customTranscriptionBaseURLValue ?? fallback
            return .openAICompatible(
                baseURL: baseURL,
                model: customTranscriptionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "whisper-1"
                    : customTranscriptionModel,
                displayName: "Custom OpenAI-compatible",
                requiresAPIKey: false
            )
        }
    }

    var selectedTranscriptionModel: String {
        selectedTranscriptionProvider.transcriptionModel
    }

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
        case .openAI:
            return .openAI(model: openAITranscriptCleanupModel)
        case .customOpenAICompatibleChat:
            guard let baseURL = customTranscriptCleanupBaseURLValue else {
                return .none
            }
            return .customOpenAICompatibleChat(
                baseURL: baseURL,
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
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .raw:
            return
        case .cleanUp:
            customCleanupPrompt = trimmed
        case .rewriteClearly:
            customRewritePrompt = trimmed
        }
    }

    func resetCustomPrompt(for mode: TranscriptProcessingMode) {
        setCustomPrompt("", for: mode)
    }

    var customTranscriptionBaseURLValue: URL? {
        guard selectedTranscriptionProviderPresetID == .customOpenAICompatible
                || selectedTranscriptionProviderID == .openAICompatible else {
            return nil
        }
        let trimmed = customTranscriptionBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    var isSetupReady: Bool {
        areSystemPermissionsReady
            && apiKeyState == .ready
    }

    var areSystemPermissionsReady: Bool {
        accessibilityState == .ready
            && microphoneState == .ready
    }

    var needsSetupAttention: Bool {
        !isSetupReady
    }

    var isSetupCheckRunning: Bool {
        if case .running = setupCheckState { return true }
        return false
    }

    var isError: Bool {
        if case .error = status { return true }
        return false
    }

    var canStartRecordingControl: Bool {
        status == .idle && isSetupReady
    }

    var canStopRecordingControl: Bool {
        status == .recording
    }

    var canCancelRecordingControl: Bool {
        status == .recording
    }

    var canCancelTranscriptionControl: Bool {
        status == .transcribing
    }

    var shouldShowFloatingStatus: Bool {
        // Always show during active capture/processing so users have visible in-use feedback.
        if status == .recording || status == .transcribing {
            return !floatingStatusDismissed
        }
        // Otherwise respect user preference
        guard showFloatingStatus, !floatingStatusDismissed else { return false }
        switch status {
        case .recording, .error:
            return true
        case .transcribing:
            return true  // already handled above, but kept for exhaustiveness
        case .idle:
            return floatingStatusTransientVisible
                && (feedbackMessage != nil || lastPasteSummary != nil || clipboardFeedback != nil)
        }
    }

    var menuBarIcon: String {
        switch status {
        case .idle:
            if needsSetupAttention {
                return "exclamationmark.triangle.fill"
            }
            switch transientResult {
            case .pasted:
                return "checkmark.circle.fill"
            case .clipboardFallback:
                return "clipboard"
            case nil:
                return "waveform"
            }
        case .recording:
            return "waveform.circle.fill"
        case .transcribing:
            return transcribingIconFrame == 0 ? "ellipsis.circle" : "ellipsis.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var statusText: String {
        switch status {
        case .idle: isSetupReady ? "Ready" : "Setup needed"
        case .recording: "Recording..."
        case .transcribing: "Transcribing..."
        case .error(let msg): msg
        }
    }

    var formattedRecordingDuration: String {
        let seconds = Int(recordingDuration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Recording time warning

    static let maxRecordingDuration: TimeInterval = 600
    static let warningThreshold: TimeInterval = 540

    var isApproachingTimeLimit: Bool {
        status == .recording && recordingDuration >= Self.warningThreshold
    }

    var remainingRecordingTime: TimeInterval {
        max(0, Self.maxRecordingDuration - recordingDuration)
    }

    var formattedRemainingTime: String {
        let remaining = Int(remainingRecordingTime)
        return "\(remaining / 60):\(String(format: "%02d", remaining % 60))"
    }

    func sessionPresentation(
        hotkeyLabel: String,
        hasRetryableFailure: Bool,
        hasLastSuccess: Bool
    ) -> SessionPresentation {
        switch status {
        case .idle:
            if let setupPresentation = setupSessionPresentation() {
                return setupPresentation
            }
            if let setupFailurePresentation = setupFailureSessionPresentation() {
                return setupFailurePresentation
            }
            if isNoAudioCapturedFeedback {
                return SessionPresentation(
                    title: noAudioCapturedTitle,
                    detail: noAudioCapturedDetail,
                    timerText: nil,
                    systemImage: "waveform.slash",
                    tone: .warning,
                    primaryAction: .openMicrophone
                )
            }
            switch transientResult {
            case .pasted:
                return SessionPresentation(
                    title: lastPasteSummary ?? "Pasted",
                    detail: [
                        "Delivered",
                        currentTargetDetail,
                        clipboardFeedback
                    ].compactMap { $0 }.joined(separator: " · "),
                    timerText: nil,
                    systemImage: "checkmark.circle.fill",
                    tone: .success,
                    primaryAction: hasLastSuccess ? .pasteAgain : nil
                )
            case .clipboardFallback:
                return SessionPresentation(
                    title: "Fallback: copied to clipboard",
                    detail: "Target unavailable; paste manually when ready",
                    timerText: nil,
                    systemImage: "clipboard",
                    tone: .warning,
                    primaryAction: hasLastSuccess ? .copy : nil
                )
            case nil:
                return SessionPresentation(
                    title: "Ready",
                    detail: "\(hotkeyLabel) · \(readyPasteDetail)",
                    timerText: nil,
                    systemImage: "waveform",
                    tone: .neutral,
                    primaryAction: nil
                )
            }
        case .recording:
            let instruction = recordingMode == .hold
                ? "Release \(hotkeyLabel) to send"
                : "Press \(hotkeyLabel) again to stop"
            let target = capturedTargetName.map { "Target: \($0)" }
            return SessionPresentation(
                title: "Recording",
                detail: [target, instruction].compactMap { $0 }.joined(separator: " · "),
                timerText: formattedRecordingDuration,
                systemImage: "record.circle",
                tone: .active,
                primaryAction: nil
            )
        case .transcribing:
            return transcriptionSessionPresentation()
        case .error(let message):
            return SessionPresentation(
                title: message,
                detail: errorDetail(for: message, hasRetryableFailure: hasRetryableFailure),
                timerText: nil,
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                primaryAction: errorAction(for: message, hasRetryableFailure: hasRetryableFailure)
            )
        }
    }

    private var noAudioCapturedTitle: String {
        "No audio captured"
    }

    private var noAudioCapturedDetail: String {
        "Try a longer recording or check your microphone input"
    }

    private var isNoAudioCapturedFeedback: Bool {
        feedbackMessage == noAudioCapturedTitle
    }

    private var currentTargetDetail: String {
        capturedTargetName.map { "Target: \($0)" } ?? "Target: current app"
    }

    private var readyPasteDetail: String {
        if queuedPasteEnabled {
            return "Transcripts queue for later paste"
        }
        return asyncPasteEnabled ? "Paste target is captured when recording starts" : "Paste target is the current app"
    }

    private func setupSessionPresentation() -> SessionPresentation? {
        if accessibilityState != .ready {
            return SessionPresentation(
                title: "Setup needed",
                detail: setupDetail(
                    for: accessibilityState,
                    unknown: "Check Accessibility before recording",
                    needsAction: "Enable Accessibility before recording"
                ),
                timerText: nil,
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                primaryAction: .openAccessibility
            )
        }
        if microphoneState != .ready {
            return SessionPresentation(
                title: "Setup needed",
                detail: setupDetail(
                    for: microphoneState,
                    unknown: "Check microphone access before recording",
                    needsAction: microphoneSetupActionDetail
                ),
                timerText: nil,
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                primaryAction: .openMicrophone
            )
        }
        if apiKeyState != .ready {
            return SessionPresentation(
                title: "Setup needed",
                detail: apiKeySetupDetail(),
                timerText: nil,
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                primaryAction: selectedProviderUsesSharedApiKey ? .addKey : .retry
            )
        }
        return nil
    }

    private func setupFailureSessionPresentation() -> SessionPresentation? {
        guard case .failed(let message) = setupCheckState else { return nil }
        return SessionPresentation(
            title: "Setup check failed",
            detail: setupFailureDetail(for: message),
            timerText: nil,
            systemImage: "exclamationmark.triangle.fill",
            tone: .warning,
            primaryAction: setupFailureAction(for: message)
        )
    }

    private func setupFailureDetail(for message: String) -> String {
        if message.localizedCaseInsensitiveContains("local whisper.cpp") {
            return "Start whisper-server on 127.0.0.1:8080, then run setup check again"
        }
        if message.localizedCaseInsensitiveContains("openai-compatible") {
            return "\(message). Check the base URL, server status, and model."
        }
        if message.localizedCaseInsensitiveContains("api key") {
            return "Add or update the \(selectedTranscriptionProvider.displayName) API key"
        }
        if message.localizedCaseInsensitiveContains("microphone") {
            if message == Self.microphonePromptTimedOutMessage {
                return Self.microphonePromptTimedOutMessage
            }
            return "Allow Microphone access or choose a working input device"
        }
        return message
    }

    private func setupFailureAction(for message: String) -> SessionAction? {
        if message.localizedCaseInsensitiveContains("api key") {
            return .addKey
        }
        if message.localizedCaseInsensitiveContains("microphone") {
            return .openMicrophone
        }
        if message.localizedCaseInsensitiveContains("accessibility") {
            return .openAccessibility
        }
        return nil
    }

    private func apiKeySetupDetail() -> String {
        guard selectedProviderUsesSharedApiKey else {
            return "Check Local whisper.cpp server before recording"
        }
        return switch apiKeyState {
        case .unknown:
            selectedTranscriptionProvider.requiresAPIKey
                ? "Check \(selectedTranscriptionProvider.displayName) API key before recording"
                : "\(selectedTranscriptionProvider.displayName) API key is optional"
        case .needsAction(let message):
            message
        case .ready:
            ""
        }
    }

    private func setupDetail(
        for state: PermissionState,
        unknown: String,
        needsAction: String
    ) -> String {
        switch state {
        case .unknown:
            unknown
        case .needsAction:
            needsAction
        case .ready:
            ""
        }
    }

    private var microphoneSetupActionDetail: String {
        switch microphoneState {
        case .needsAction(let message):
            if message == Self.noMicrophoneDetectedMessage {
                return "Connect or select a working microphone before recording"
            }
            if message == Self.selectedMicrophoneUnavailableMessage {
                return "Choose System Default or another available input before recording"
            }
            if message == Self.microphonePromptTimedOutMessage {
                return Self.microphonePromptTimedOutMessage
            }
            return "Allow microphone access before recording"
        case .unknown, .ready:
            return ""
        }
    }

    private func transcriptionSessionPresentation() -> SessionPresentation {
        switch transcriptionStage ?? .transcribingAudio {
        case .transcribingAudio:
            return SessionPresentation(
                title: "Transcribing",
                detail: transcriptionDetail,
                timerText: nil,
                systemImage: "waveform.badge.magnifyingglass",
                tone: .progress,
                primaryAction: nil
            )
        case .cleaningTranscript:
            return SessionPresentation(
                title: "Cleaning up",
                detail: "\(transcriptCleanupModel) · \(transcriptProcessingMode.displayName) · \(currentTargetDetail)",
                timerText: nil,
                systemImage: "sparkles",
                tone: .progress,
                primaryAction: nil
            )
        case .pasting:
            return SessionPresentation(
                title: "Pasting",
                detail: capturedTargetName.map { "Target: \($0)" } ?? "Inserting into current app",
                timerText: nil,
                systemImage: "arrow.down.doc",
                tone: .progress,
                primaryAction: nil
            )
        }
    }

    private var transcriptionDetail: String {
        let baseDetail: String
        switch effectiveTranscriptProcessingMode {
        case .raw:
            baseDetail = "\(selectedTranscriptionProvider.displayName) · \(selectedTranscriptionModel)"
        case .cleanUp, .rewriteClearly:
            baseDetail = "\(selectedTranscriptionProvider.displayName) · cleanup next"
        }
        return "\(baseDetail) · \(currentTargetDetail)"
    }

    private func errorDetail(for message: String, hasRetryableFailure: Bool) -> String {
        if message.localizedCaseInsensitiveContains("cannot reach local whisper.cpp")
            || message.localizedCaseInsensitiveContains("could not reach local whisper.cpp") {
            return "Start whisper-server on 127.0.0.1:8080, then try again"
        }
        if message.localizedCaseInsensitiveContains("cannot reach custom openai-compatible")
            || message.localizedCaseInsensitiveContains("could not reach custom openai-compatible")
            || message.localizedCaseInsensitiveContains("invalid provider url") {
            return "Check the transcription server URL in Settings, then try again"
        }
        if message.localizedCaseInsensitiveContains("api key") {
            guard selectedProviderUsesSharedApiKey else {
                return "Start Local whisper.cpp server and test the connection"
            }
            return selectedTranscriptionProvider.requiresAPIKey
                ? "Add a \(selectedTranscriptionProvider.displayName) API key to transcribe"
                : "\(selectedTranscriptionProvider.displayName) API key is optional"
        }
        if message.localizedCaseInsensitiveContains("accessibility") {
            return "Enable \(AppBrand.name) in Privacy & Security"
        }
        if message.localizedCaseInsensitiveContains("microphone") {
            return "Check Microphone privacy or audio input"
        }
        return hasRetryableFailure ? "Audio saved · Retry transcription" : "Open History for details"
    }

    static func accessibilityRecoveryDetail(isDebugBuild: Bool) -> String {
        "Enable \(AppBrand.name) in Accessibility. Return to \(AppBrand.name). If it is already enabled but still fails, remove the old \(AppBrand.name) entry, quit, and reopen \(AppBrand.name)."
    }

    private func errorAction(for message: String, hasRetryableFailure: Bool) -> SessionAction? {
        if message.localizedCaseInsensitiveContains("api key") {
            return .addKey
        }
        if message.localizedCaseInsensitiveContains("accessibility") {
            return .openAccessibility
        }
        if message.localizedCaseInsensitiveContains("microphone") {
            return .openMicrophone
        }
        return hasRetryableFailure ? .retry : nil
    }

    init(localPairingBridgeService: LocalPairingBridgeService? = nil) {
        self.localPairingBridgeService = localPairingBridgeService ?? LocalPairingBridgeService()

        let defaults = Self.defaults
        var persistedPresetRawValue = defaults
            .persistentDomain(forName: Self.defaultsDomainName)?["transcriptionProviderPreset"] as? String
        if ProcessInfo.processInfo.arguments.contains("--reset-defaults") {
            for key in [
                "soundEffectsEnabled",
                "recordingStartSoundCue",
                "recordingEndSoundCue",
                "transcriptionProvider",
                "transcriptionProviderPreset",
                "whisperModel",
                "customTranscriptionBaseURL",
                "customTranscriptionModel",
                "audioFormat",
                "keepOnClipboard",
                "showLiveFeedbackHUD",
                "showFloatingStatus",
                "asyncPasteEnabled",
                "queuedPasteEnabled",
                "queuedPasteMode",
                "experimentalSkyLightPasteEnabled",
                "pauseBrowserMediaWhileRecording",
                "localBridgeEnabled",
                "mockTranscriptionEnabled",
                "recordingMode",
                "hotkeyChoice",
                "customHotkeyKeyCode",
                "customHotkeyModifiers",
                "customHotkeyLabel",
                "language",
                "transcriptProcessingMode",
                "transcriptCleanupModel",
                "transcriptCleanupProvider",
                "customTranscriptCleanupBaseURL",
                "customTranscriptCleanupModel",
                "customCleanupPrompt.cleanUp",
                "customCleanupPrompt.rewriteClearly",
                "transcriptCleanupPreferredTerms",
                "selectedInputDeviceUID"
            ] {
                defaults.removeObject(forKey: key)
            }
            persistedPresetRawValue = nil
        }

        defaults.register(defaults: [
            "soundEffectsEnabled": true,
            "recordingStartSoundCue": RecordingSoundCue.defaultStart.rawValue,
            "recordingEndSoundCue": RecordingSoundCue.defaultEnd.rawValue,
            "transcriptionProvider": TranscriptionProviderID.groq.rawValue,
            "transcriptionProviderPreset": TranscriptionProviderPresetID.groq.rawValue,
            "whisperModel": "whisper-large-v3-turbo",
            "customTranscriptionBaseURL": "http://127.0.0.1:8080/v1",
            "customTranscriptionModel": "whisper-1",
            "audioFormat": "m4a",
            "keepOnClipboard": false,
            "showFloatingStatus": false,
            "asyncPasteEnabled": false,
            "queuedPasteEnabled": false,
            "queuedPasteMode": QueuedPasteMode.stepThrough.rawValue,
            "experimentalSkyLightPasteEnabled": false,
            "pauseBrowserMediaWhileRecording": false,
            "localBridgeEnabled": false,
            "mockTranscriptionEnabled": false,
            "recordingMode": "hold",
            "hotkeyChoice": "rightCommand",
            "language": "auto",
            "transcriptProcessingMode": "raw",
            "transcriptCleanupModel": "llama-3.1-8b-instant",
            "openAITranscriptCleanupModel": "gpt-5.4-mini",
            "transcriptCleanupProvider": "groq",
            "customTranscriptCleanupBaseURL": "http://127.0.0.1:11434/v1",
            "customTranscriptCleanupModel": "llama3.1:8b",
            "customCleanupPrompt.cleanUp": "",
            "customCleanupPrompt.rewriteClearly": "",
            "transcriptCleanupPreferredTerms": ""
        ])

        // Load persisted values into stored properties.
        // didSet does NOT fire during init, so no redundant writes.
        soundEffectsEnabled = defaults.bool(forKey: "soundEffectsEnabled")
        recordingStartSoundCue = RecordingSoundCue(rawValue: defaults.string(forKey: "recordingStartSoundCue") ?? "")
            ?? .defaultStart
        recordingEndSoundCue = RecordingSoundCue(rawValue: defaults.string(forKey: "recordingEndSoundCue") ?? "")
            ?? .defaultEnd
        let persistedProviderID = TranscriptionProviderID(rawValue: defaults.string(forKey: "transcriptionProvider") ?? "") ?? .groq
        let persistedPresetID: TranscriptionProviderPresetID
        if let rawPreset = persistedPresetRawValue,
           let preset = TranscriptionProviderPresetID(rawValue: rawPreset) {
            persistedPresetID = preset
        } else {
            persistedPresetID = Self.defaultPresetID(for: persistedProviderID)
        }
        isSynchronizingProviderSelection = true
        selectedTranscriptionProviderID = persistedProviderID
        selectedTranscriptionProviderPresetID = persistedPresetID
        isSynchronizingProviderSelection = false
        selectedModel = defaults.string(forKey: "whisperModel") ?? "whisper-large-v3-turbo"
        customTranscriptionBaseURL = defaults.string(forKey: "customTranscriptionBaseURL") ?? "http://127.0.0.1:8080/v1"
        customTranscriptionModel = defaults.string(forKey: "customTranscriptionModel") ?? "whisper-1"
        selectedAudioFormat = AudioFormat(rawValue: defaults.string(forKey: "audioFormat") ?? "") ?? .m4a
        selectedLanguage = Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .auto
        transcriptProcessingMode = TranscriptProcessingMode(rawValue: defaults.string(forKey: "transcriptProcessingMode") ?? "") ?? .raw
        transcriptCleanupModel = defaults.string(forKey: "transcriptCleanupModel") ?? "llama-3.1-8b-instant"
        openAITranscriptCleanupModel = defaults.string(forKey: "openAITranscriptCleanupModel") ?? "gpt-5.4-mini"
        transcriptCleanupProviderID = TranscriptCleanupProviderID(
            rawValue: defaults.string(forKey: "transcriptCleanupProvider") ?? ""
        ) ?? .groq
        customTranscriptCleanupBaseURL = defaults.string(forKey: "customTranscriptCleanupBaseURL")
            ?? "http://127.0.0.1:11434/v1"
        customTranscriptCleanupModel = defaults.string(forKey: "customTranscriptCleanupModel") ?? "llama3.1:8b"
        customCleanupPrompt = defaults.string(forKey: "customCleanupPrompt.cleanUp") ?? ""
        customRewritePrompt = defaults.string(forKey: "customCleanupPrompt.rewriteClearly") ?? ""
        preferredTermsText = Self.normalizedPreferredTerms(
            from: defaults.string(forKey: "transcriptCleanupPreferredTerms") ?? ""
        ).joined(separator: "\n")
        keepOnClipboard = defaults.bool(forKey: "keepOnClipboard")
        showFloatingStatus = defaults.bool(forKey: "showFloatingStatus")
        asyncPasteEnabled = defaults.bool(forKey: "asyncPasteEnabled")
        queuedPasteEnabled = defaults.bool(forKey: "queuedPasteEnabled")
        queuedPasteMode = QueuedPasteMode(rawValue: defaults.string(forKey: "queuedPasteMode") ?? "") ?? .stepThrough
        experimentalSkyLightPasteEnabled = defaults.bool(forKey: "experimentalSkyLightPasteEnabled")
        pauseBrowserMediaWhileRecording = defaults.bool(forKey: "pauseBrowserMediaWhileRecording")
        localBridgeEnabled = defaults.bool(forKey: "localBridgeEnabled")
        self.localPairingBridgeService.setEnabled(
            localBridgeEnabled,
            appState: self,
            deviceName: Self.localBridgeDeviceName
        )
        if localBridgeEnabled {
            syncLocalBridgePresentationAfterEnable()
        } else {
            localBridgeStatusMessage = "Local bridge off"
        }
        #if DEBUG
        mockTranscriptionEnabled = defaults.bool(forKey: "mockTranscriptionEnabled")
        #endif
        recordingMode = HotkeyMonitor.RecordingMode(rawValue: defaults.string(forKey: "recordingMode") ?? "") ?? .hold
        hotkeyChoice = HotkeyMonitor.HotkeyChoice(rawValue: defaults.string(forKey: "hotkeyChoice") ?? "") ?? .rightCommand
        customHotkeyKeyCode = UInt16(defaults.integer(forKey: "customHotkeyKeyCode"))
        customHotkeyModifiers = UInt64(bitPattern: Int64(defaults.integer(forKey: "customHotkeyModifiers")))
        customHotkeyLabel = defaults.string(forKey: "customHotkeyLabel") ?? ""
        selectedInputDeviceUID = Self.defaults.string(forKey: "selectedInputDeviceUID")
        isSynchronizingProviderSelection = true
        selectedTranscriptionProviderID = selectedTranscriptionProviderPreset.providerID
        isSynchronizingProviderSelection = false
        syncCleanupProviderWithTranscriptionPreset()
    }

    private static func defaultPresetID(for providerID: TranscriptionProviderID) -> TranscriptionProviderPresetID {
        switch providerID {
        case .groq:
            .groq
        case .openAI:
            .openAIWhisper
        case .openAICompatible:
            .customOpenAICompatible
        }
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

    private func syncCleanupProviderWithTranscriptionPreset() {
        // Cleanup provider routing is independent from the STT provider.
    }

    private func handleTranscriptionProviderSelectionChanged() {
        syncCleanupProviderWithTranscriptionPreset()
        resetProviderConnectionTest()
        refreshApiKeyState()
        clearProviderScopedErrorPresentation()
    }

    private func clearProviderScopedErrorPresentation() {
        guard case .error = status else { return }
        clearError()
        transcriptionStage = nil
        feedbackMessage = nil
        clipboardFeedback = nil
        floatingStatusTransientVisible = false
    }

    func setStatus(_ newStatus: Status) {
        status = newStatus
        switch newStatus {
        case .idle:
            transcriptionStage = nil
            resetAudioLevels()
            break
        case .recording:
            transcriptionStage = nil
            resetAudioLevels()
            floatingStatusDismissed = false
            floatingStatusTransientVisible = false
            transientResult = nil
            feedbackMessage = "Recording..."
            lastPasteSummary = nil
            clipboardFeedback = nil
        case .transcribing:
            floatingStatusDismissed = false
            floatingStatusTransientVisible = false
            transcriptionStage = transcriptionStage ?? .transcribingAudio
            feedbackMessage = "Sending audio..."
        case .error(let message):
            transcriptionStage = nil
            resetAudioLevels()
            floatingStatusDismissed = false
            floatingStatusTransientVisible = false
            transientResult = nil
            feedbackMessage = message
        }
    }

    func showError(_ message: String) {
        status = .error(message)
        transcriptionStage = nil
        resetAudioLevels()
        feedbackMessage = message
        transientResult = nil
        floatingStatusDismissed = false
        floatingStatusTransientVisible = false
    }

    func recordNoAudioCaptured() {
        status = .idle
        transcriptionStage = nil
        resetAudioLevels()
        transientResult = nil
        feedbackMessage = noAudioCapturedTitle
        lastPasteSummary = nil
        clipboardFeedback = noAudioCapturedDetail
        floatingStatusDismissed = false
        floatingStatusTransientVisible = true
    }

    func updateAccessibilityState(
        isTrusted: Bool,
        message: String = "Enable Accessibility"
    ) {
        accessibilityState = isTrusted
            ? .ready
            : .needsAction(message)
    }

    func updateMicrophoneState(isReady: Bool, message: String = "Allow microphone access") {
        microphoneState = isReady ? .ready : .needsAction(message)
    }

    func applySetupHealth(
        accessibilityTrusted: Bool,
        microphoneAuthorizationStatus: AVAuthorizationStatus
    ) {
        updateAccessibilityState(isTrusted: accessibilityTrusted)
        switch microphoneAuthorizationStatus {
        case .authorized:
            updateMicrophoneState(isReady: true)
        case .denied, .restricted:
            updateMicrophoneState(isReady: false, message: "Allow microphone access")
        case .notDetermined:
            microphoneState = .unknown
        @unknown default:
            microphoneState = .unknown
        }
    }

    func applyInputDeviceHealth(
        availableInputDevices: [AudioRecorder.AudioDevice],
        selectedInputDeviceUID: String? = nil
    ) {
        guard microphoneState == .ready else { return }
        if availableInputDevices.isEmpty {
            updateMicrophoneState(isReady: false, message: Self.noMicrophoneDetectedMessage)
            return
        }
        if let selectedInputDeviceUID,
           !availableInputDevices.contains(where: { $0.uid == selectedInputDeviceUID }) {
            DiagnosticLog.write(
                "SetupHealth: selected microphone unavailable uid=\(selectedInputDeviceUID) fallbackAvailable=true"
            )
        }
    }

    func refreshApiKeyState() {
        if selectedTranscriptionProvider.requiresAPIKey {
            apiKeyState = hasApiKey ? .ready : .needsAction("Add \(selectedTranscriptionProvider.displayName) API key")
        } else {
            apiKeyState = .ready
        }
    }

    func resetProviderConnectionTest() {
        providerConnectionTestState = .idle
    }

    func resetCleanupConnectionTest() {
        cleanupConnectionTestState = .idle
    }

    func beginLocalBridgePairing() {
        guard localBridgeEnabled else {
            localBridgeStatusMessage = "Turn on Local Bridge first"
            return
        }
        do {
            let session = try localPairingBridgeService.beginPairing()
            localBridgePairingSession = session
            localBridgePairingState = localPairingBridgeService.pairingState
            localBridgeStatusMessage = "Pairing code \(session.code)"
        } catch {
            localBridgeStatusMessage = "Pairing unavailable"
        }
    }

    func approveFixtureLocalBridgePairing() {
        guard localBridgeEnabled else {
            localBridgeStatusMessage = "Turn on Local Bridge first"
            return
        }
        guard localPairingBridgeService.activePairingSession != nil else {
            localBridgeStatusMessage = "Start Pair iPhone first"
            return
        }
        do {
            let peer = try localPairingBridgeService.approvePairing(
                iphonePeerID: "fixture-iphone-public-id",
                displayName: "Fixture iPhone"
            )
            localBridgeTrustedPeer = peer
            localBridgePairingSession = nil
            localBridgePairingState = localPairingBridgeService.pairingState
            localBridgeStatusMessage = "Paired with \(peer.displayName)"
        } catch {
            localBridgeStatusMessage = "Pairing approval unavailable"
        }
    }

    func revokeLocalBridgePairing() {
        guard localBridgeEnabled else {
            localBridgeStatusMessage = "Turn on Local Bridge first"
            return
        }
        localPairingBridgeService.revokePairing()
        localBridgePairingSession = nil
        localBridgeTrustedPeer = nil
        localBridgeLastReceipt = nil
        localBridgePairingState = localPairingBridgeService.pairingState
        localBridgeStatusMessage = "Pairing revoked"
    }

    func runFixtureLocalBridgeTranscription() {
        guard localBridgeEnabled else {
            localBridgeStatusMessage = "Turn on Local Bridge first"
            return
        }
        do {
            let request = LocalBridgeTranscriptionStart(
                requestID: "fixture-transcription-request",
                audio: LocalBridgeAudioDescriptor(
                    format: selectedAudioFormat.rawValue,
                    durationMilliseconds: 1_200,
                    byteCount: 12_288
                ),
                requestedRouteID: .macSelected,
                languageHint: selectedLanguage == .auto ? nil : selectedLanguage.rawValue,
                cleanupRouteID: .macDefault
            )
            let response = try localPairingBridgeService.handleMockTranscription(
                request,
                appState: self,
                macDeviceName: Host.current().localizedName ?? "This Mac"
            )
            switch response {
            case .complete(let complete):
                localBridgeLastReceipt = complete.routeReceipt
                localBridgeStatusMessage = "Mock request complete via \(complete.routeReceipt.routeDisplayName)"
            case .failed(let failure):
                localBridgeLastReceipt = failure.routeReceipt
                localBridgeStatusMessage = failure.error.displayMessage
            }
            localBridgePairingState = localPairingBridgeService.pairingState
        } catch LocalPairingBridgeServiceError.pairingRequired {
            localBridgeStatusMessage = "Pair iPhone and approve first"
        } catch {
            localBridgeStatusMessage = "Mock request unavailable"
        }
    }

    private func syncLocalBridgePresentationAfterEnable() {
        localBridgePairingState = localPairingBridgeService.pairingState
        localBridgeTrustedPeer = localPairingBridgeService.trustedPeer
        if let peer = localBridgeTrustedPeer {
            localBridgeStatusMessage = "Paired with \(peer.displayName)"
        } else {
            localBridgeStatusMessage = "Ready to pair"
        }
    }

    func testSelectedProviderConnection(
        service: TranscriptionService = TranscriptionService(),
        apiKey: String? = nil
    ) async {
        guard selectedTranscriptionProvider.id == .openAICompatible else {
            providerConnectionTestState = .warning("Connection test is only needed for custom or local providers.")
            return
        }

        if selectedTranscriptionProviderPresetID == .customOpenAICompatible,
           customTranscriptionBaseURLValue == nil {
            providerConnectionTestState = .failed("Invalid base URL. Use an http:// or https:// URL.")
            return
        }

        providerConnectionTestState = .running
        let key = apiKey ?? selectedProviderApiKey
        do {
            let result = try await service
                .withProvider(selectedTranscriptionProvider)
                .validateProviderConfiguration(
                    apiKey: key,
                    requiredModels: [selectedTranscriptionModel]
                )
            switch result {
            case .modelsValidated:
                providerConnectionTestState = .succeeded("Server reachable. Model \(selectedTranscriptionModel) is available.")
            case .reachableWithoutModelValidation:
                providerConnectionTestState = .warning("Server reachable. Model availability was not checked.")
            }
        } catch TranscriptionService.TranscriptionError.modelUnavailable(let model) {
            providerConnectionTestState = .failed("Server reachable, but model \(model) was not listed.")
        } catch TranscriptionService.TranscriptionError.invalidProviderURL {
            providerConnectionTestState = .failed("Invalid base URL. Use an http:// or https:// URL.")
        } catch is URLError {
            providerConnectionTestState = .failed(providerConnectionUnreachableMessage)
        } catch {
            providerConnectionTestState = .failed("Connection test failed: \(error.localizedDescription)")
        }
    }

    func testSelectedCleanupProviderConnection(
        service: TranscriptionService = TranscriptionService(),
        apiKey: String? = nil
    ) async {
        let provider = selectedTranscriptCleanupProvider
        if provider.id == .customOpenAICompatibleChat, customTranscriptCleanupBaseURLValue == nil {
            cleanupConnectionTestState = .failed("Invalid base URL. Use an http:// or https:// URL.")
            return
        }
        guard provider.id != .none else {
            cleanupConnectionTestState = .warning("Select a cleanup provider before testing.")
            return
        }

        cleanupConnectionTestState = .running
        let key = apiKey ?? cleanupProviderAPIKey(for: provider.id)
        if provider.requiresAPIKey, (key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            cleanupConnectionTestState = .failed(missingCleanupProviderAPIKeyMessage(for: provider.id))
            return
        }

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
            cleanupConnectionTestState = .failed(cleanupProviderUnreachableMessage(for: provider.id))
        } catch {
            cleanupConnectionTestState = .failed("Cleanup connection test failed: \(error.localizedDescription)")
        }
    }

    private func missingCleanupProviderAPIKeyMessage(for providerID: TranscriptCleanupProviderID) -> String {
        switch providerID {
        case .none:
            "Select a cleanup provider before testing."
        case .groq:
            "Add a Groq API key before testing cleanup."
        case .openAI:
            "Add an OpenAI API key before testing cleanup."
        case .customOpenAICompatibleChat:
            "Save a cleanup API key before testing this endpoint."
        }
    }

    private func cleanupProviderAPIKey(for providerID: TranscriptCleanupProviderID) -> String? {
        switch providerID {
        case .none:
            nil
        case .groq:
            KeychainHelper.readApiKey(for: .groq)
        case .openAI:
            KeychainHelper.readApiKey(for: .openAI)
        case .customOpenAICompatibleChat:
            KeychainHelper.readCleanupApiKey(for: .customOpenAICompatibleChat)
        }
    }

    private func cleanupProviderUnreachableMessage(for providerID: TranscriptCleanupProviderID) -> String {
        switch providerID {
        case .none:
            "Select a cleanup provider before testing."
        case .groq:
            "Could not reach Groq. Check your network connection."
        case .openAI:
            "Could not reach OpenAI. Check your network connection."
        case .customOpenAICompatibleChat:
            "Could not reach custom cleanup endpoint. Check that the server is running."
        }
    }

    private var providerConnectionUnreachableMessage: String {
        switch selectedTranscriptionProviderPresetID {
        case .localWhisperCPP:
            "Could not reach Local whisper.cpp. Start whisper-server on 127.0.0.1:8080 and try again."
        case .openAIWhisper:
            "Could not reach OpenAI. Check your network connection."
        case .customOpenAICompatible:
            "Could not reach Custom OpenAI-compatible. Check the base URL, server status, and network access."
        case .groq:
            "Could not reach \(selectedTranscriptionProvider.displayName). Check your network connection."
        }
    }

    func startSetupCheck() {
        setupCheckState = .running
    }

    func completeSetupCheck(detail: String = "Ready to record") {
        setupCheckSuccessDetail = detail
        setupCheckState = .passed(Date())
    }

    func failSetupCheck(_ message: String) {
        setupCheckState = .failed(message)
    }

    func clearError() {
        if case .error = status {
            status = .idle
        }
    }

    func recordPaste(_ delivery: PasteDelivery) {
        resetAudioLevels()
        lastPasteSummary = delivery.userMessage
        feedbackMessage = delivery.userMessage
        clipboardFeedback = delivery == .clipboardFallback
            ? "Text is on the clipboard"
            : (keepOnClipboard ? "Text kept on clipboard" : "Clipboard restored")
        transientResult = delivery == .clipboardFallback ? .clipboardFallback : .pasted(delivery)
        floatingStatusDismissed = false
        floatingStatusTransientVisible = true
    }

    func recordTargetCapture(_ target: PasteTarget?) {
        if let target {
            capturedTargetName = target.appName.isEmpty ? "Unknown app" : target.appName
            feedbackMessage = "Target: \(capturedTargetName!)"
        } else if asyncPasteEnabled || queuedPasteEnabled {
            capturedTargetName = nil
            feedbackMessage = "Target unavailable"
        } else {
            capturedTargetName = nil
        }
    }

    func clearTransientFeedback() {
        capturedTargetName = nil
        feedbackMessage = nil
        clipboardFeedback = nil
        transientResult = nil
        resetAudioLevels()
        floatingStatusTransientVisible = false
        floatingStatusDismissed = false
    }

    func hideFloatingStatus() {
        floatingStatusDismissed = true
    }

    func expireTransientSuccess() {
        guard case .idle = status else { return }
        if case .pasted = transientResult {
            transientResult = nil
            floatingStatusTransientVisible = false
        }
    }

    func recordAudioLevel(_ level: Float) {
        guard status == .recording else { return }
        let boundedLevel = min(max(level.isFinite ? level : 0, 0), 1)
        let smoothedLevel = max(boundedLevel, (audioLevelHistory.last ?? 0) * 0.72)
        audioLevelHistory.append(smoothedLevel)
        let maxSamples = 18
        if audioLevelHistory.count > maxSamples {
            audioLevelHistory.removeFirst(audioLevelHistory.count - maxSamples)
        }
    }

    func resetAudioLevels() {
        audioLevelHistory = Array(repeating: 0, count: 18)
    }
}

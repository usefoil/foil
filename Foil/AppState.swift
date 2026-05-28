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
    var floatingStatusTransientVisible = false
    var floatingStatusDismissed = false
    var accessibilityState: PermissionState = .unknown
    var microphoneState: PermissionState = .unknown
    var apiKeyState: PermissionState = .unknown
    var setupCheckState: SetupCheckState = .idle
    var setupCheckSuccessDetail = "Ready to record"
    var providerConnectionTestState: ProviderConnectionTestState = .idle
    var cleanupConnectionTestState: ProviderConnectionTestState = .idle

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

    var soundEffectsEnabled: Bool = true {
        didSet { Self.defaults.set(soundEffectsEnabled, forKey: "soundEffectsEnabled") }
    }

    var recordingStartSoundCue: RecordingSoundCue = .recordingStart {
        didSet { Self.defaults.set(recordingStartSoundCue.rawValue, forKey: "recordingStartSoundCue") }
    }

    var recordingEndSoundCue: RecordingSoundCue = .recordingStop {
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
            selectedTranscriptionProviderPresetID = selectedTranscriptionProviderID == .groq
                ? .groq
                : .customOpenAICompatible
            isSynchronizingProviderSelection = false
            syncCleanupProviderWithTranscriptionPreset()
            resetProviderConnectionTest()
        }
    }

    var selectedTranscriptionProviderPresetID: TranscriptionProviderPresetID = .groq {
        didSet {
            Self.defaults.set(selectedTranscriptionProviderPresetID.rawValue, forKey: "transcriptionProviderPreset")
            guard !isSynchronizingProviderSelection else { return }
            isSynchronizingProviderSelection = true
            selectedTranscriptionProviderID = selectedTranscriptionProviderPreset.providerID
            isSynchronizingProviderSelection = false
            syncCleanupProviderWithTranscriptionPreset()
            resetProviderConnectionTest()
            refreshApiKeyState()
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

    var transcriptCleanupModel: String = "llama-3.3-70b-versatile" {
        didSet {
            Self.defaults.set(transcriptCleanupModel, forKey: "transcriptCleanupModel")
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

    var hasApiKey: Bool { KeychainHelper.readApiKey(for: selectedTranscriptionProviderID) != nil }

    var selectedTranscriptionProviderPreset: TranscriptionProviderPreset {
        switch selectedTranscriptionProviderPresetID {
        case .groq:
            return .groq
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
        accessibilityState == .ready
            && microphoneState == .ready
            && apiKeyState == .ready
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
        // Always show during active transcription (user needs to know paste is coming)
        if status == .transcribing {
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
                    needsAction: "Allow microphone access before recording"
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
                primaryAction: .addKey
            )
        }
        return nil
    }

    private func apiKeySetupDetail() -> String {
        switch apiKeyState {
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
        if message.localizedCaseInsensitiveContains("api key") {
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

    init() {
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
                "selectedInputDeviceUID"
            ] {
                defaults.removeObject(forKey: key)
            }
            persistedPresetRawValue = nil
        }

        defaults.register(defaults: [
            "soundEffectsEnabled": true,
            "recordingStartSoundCue": RecordingSoundCue.recordingStart.rawValue,
            "recordingEndSoundCue": RecordingSoundCue.recordingStop.rawValue,
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
            "mockTranscriptionEnabled": false,
            "recordingMode": "hold",
            "hotkeyChoice": "rightCommand",
            "language": "auto",
            "transcriptProcessingMode": "raw",
            "transcriptCleanupModel": "llama-3.3-70b-versatile",
            "transcriptCleanupProvider": "groq",
            "customTranscriptCleanupBaseURL": "http://127.0.0.1:11434/v1",
            "customTranscriptCleanupModel": "llama3.1:8b"
        ])

        // Load persisted values into stored properties.
        // didSet does NOT fire during init, so no redundant writes.
        soundEffectsEnabled = defaults.bool(forKey: "soundEffectsEnabled")
        recordingStartSoundCue = RecordingSoundCue(rawValue: defaults.string(forKey: "recordingStartSoundCue") ?? "")
            ?? .recordingStart
        recordingEndSoundCue = RecordingSoundCue(rawValue: defaults.string(forKey: "recordingEndSoundCue") ?? "")
            ?? .recordingStop
        let persistedProviderID = TranscriptionProviderID(rawValue: defaults.string(forKey: "transcriptionProvider") ?? "") ?? .groq
        let persistedPresetID: TranscriptionProviderPresetID
        if let rawPreset = persistedPresetRawValue,
           let preset = TranscriptionProviderPresetID(rawValue: rawPreset) {
            persistedPresetID = preset
        } else {
            persistedPresetID = persistedProviderID == .groq ? .groq : .customOpenAICompatible
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
        transcriptCleanupModel = defaults.string(forKey: "transcriptCleanupModel") ?? "llama-3.3-70b-versatile"
        transcriptCleanupProviderID = TranscriptCleanupProviderID(
            rawValue: defaults.string(forKey: "transcriptCleanupProvider") ?? ""
        ) ?? .groq
        customTranscriptCleanupBaseURL = defaults.string(forKey: "customTranscriptCleanupBaseURL")
            ?? "http://127.0.0.1:11434/v1"
        customTranscriptCleanupModel = defaults.string(forKey: "customTranscriptCleanupModel") ?? "llama3.1:8b"
        keepOnClipboard = defaults.bool(forKey: "keepOnClipboard")
        showFloatingStatus = defaults.bool(forKey: "showFloatingStatus")
        asyncPasteEnabled = defaults.bool(forKey: "asyncPasteEnabled")
        queuedPasteEnabled = defaults.bool(forKey: "queuedPasteEnabled")
        queuedPasteMode = QueuedPasteMode(rawValue: defaults.string(forKey: "queuedPasteMode") ?? "") ?? .stepThrough
        experimentalSkyLightPasteEnabled = defaults.bool(forKey: "experimentalSkyLightPasteEnabled")
        pauseBrowserMediaWhileRecording = defaults.bool(forKey: "pauseBrowserMediaWhileRecording")
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

    private func syncCleanupProviderWithTranscriptionPreset() {
        if selectedTranscriptionProviderPresetID != .groq,
           transcriptCleanupProviderID == .groq {
            transcriptCleanupProviderID = .none
        } else if selectedTranscriptionProviderPresetID == .groq,
                  transcriptProcessingMode != .raw,
                  transcriptCleanupProviderID == .none {
            transcriptCleanupProviderID = .groq
        }
    }

    func setStatus(_ newStatus: Status) {
        status = newStatus
        switch newStatus {
        case .idle:
            transcriptionStage = nil
            break
        case .recording:
            transcriptionStage = nil
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
            floatingStatusDismissed = false
            floatingStatusTransientVisible = false
            transientResult = nil
            feedbackMessage = message
        }
    }

    func showError(_ message: String) {
        status = .error(message)
        transcriptionStage = nil
        feedbackMessage = message
        transientResult = nil
        floatingStatusDismissed = false
        floatingStatusTransientVisible = false
    }

    func recordNoAudioCaptured() {
        status = .idle
        transcriptionStage = nil
        transientResult = nil
        feedbackMessage = "No audio captured"
        lastPasteSummary = nil
        clipboardFeedback = "Try a longer recording or check your microphone"
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
        let key = apiKey ?? KeychainHelper.readApiKey(for: selectedTranscriptionProviderID)
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

    private var providerConnectionUnreachableMessage: String {
        switch selectedTranscriptionProviderPresetID {
        case .localWhisperCPP:
            "Could not reach Local whisper.cpp. Start whisper-server on 127.0.0.1:8080 and try again."
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
}

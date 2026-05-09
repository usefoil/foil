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

    enum PermissionState: Equatable {
        case unknown
        case ready
        case needsAction(String)
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
    var floatingStatusTransientVisible = false
    var floatingStatusDismissed = false
    var accessibilityState: PermissionState = .unknown
    var microphoneState: PermissionState = .unknown
    var apiKeyState: PermissionState = .unknown

    // MARK: - UserDefaults-backed preferences
    //
    // These are stored properties so that @Observable can track mutations.
    // Each didSet syncs the value back to UserDefaults for persistence.

    private static var defaults: UserDefaults {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let defaults = UserDefaults(suiteName: "com.neonwatty.GroqTalk.UITests") {
            return defaults
        }
        return .standard
    }

    var soundEffectsEnabled: Bool = true {
        didSet { Self.defaults.set(soundEffectsEnabled, forKey: "soundEffectsEnabled") }
    }

    var selectedModel: String = "whisper-large-v3-turbo" {
        didSet { Self.defaults.set(selectedModel, forKey: "whisperModel") }
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
        didSet { Self.defaults.set(transcriptCleanupModel, forKey: "transcriptCleanupModel") }
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

    var hasApiKey: Bool { KeychainHelper.readApiKey() != nil }

    var needsSetupAttention: Bool {
        [accessibilityState, microphoneState, apiKeyState].contains { state in
            if case .needsAction = state { return true }
            return false
        }
    }

    var isError: Bool {
        if case .error = status { return true }
        return false
    }

    var shouldShowFloatingStatus: Bool {
        guard showFloatingStatus, !floatingStatusDismissed else { return false }
        switch status {
        case .recording, .transcribing, .error:
            return true
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
        case .idle: "Ready"
        case .recording: "Recording..."
        case .transcribing: "Transcribing..."
        case .error(let msg): msg
        }
    }

    var formattedRecordingDuration: String {
        let seconds = Int(recordingDuration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    init() {
        let defaults = Self.defaults
        if ProcessInfo.processInfo.arguments.contains("--reset-defaults") {
            for key in [
                "soundEffectsEnabled",
                "whisperModel",
                "audioFormat",
                "keepOnClipboard",
                "showLiveFeedbackHUD",
                "showFloatingStatus",
                "asyncPasteEnabled",
                "mockTranscriptionEnabled",
                "recordingMode",
                "hotkeyChoice",
                "language",
                "transcriptProcessingMode",
                "transcriptCleanupModel"
            ] {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.register(defaults: [
            "soundEffectsEnabled": true,
            "whisperModel": "whisper-large-v3-turbo",
            "audioFormat": "m4a",
            "keepOnClipboard": false,
            "showFloatingStatus": false,
            "asyncPasteEnabled": false,
            "mockTranscriptionEnabled": false,
            "recordingMode": "hold",
            "hotkeyChoice": "rightCommand",
            "language": "auto",
            "transcriptProcessingMode": "raw",
            "transcriptCleanupModel": "llama-3.3-70b-versatile"
        ])

        // Load persisted values into stored properties.
        // didSet does NOT fire during init, so no redundant writes.
        soundEffectsEnabled = defaults.bool(forKey: "soundEffectsEnabled")
        selectedModel = defaults.string(forKey: "whisperModel") ?? "whisper-large-v3-turbo"
        selectedAudioFormat = AudioFormat(rawValue: defaults.string(forKey: "audioFormat") ?? "") ?? .m4a
        selectedLanguage = Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .auto
        transcriptProcessingMode = TranscriptProcessingMode(rawValue: defaults.string(forKey: "transcriptProcessingMode") ?? "") ?? .raw
        transcriptCleanupModel = defaults.string(forKey: "transcriptCleanupModel") ?? "llama-3.3-70b-versatile"
        keepOnClipboard = defaults.bool(forKey: "keepOnClipboard")
        showFloatingStatus = defaults.bool(forKey: "showFloatingStatus")
        asyncPasteEnabled = defaults.bool(forKey: "asyncPasteEnabled")
        #if DEBUG
        mockTranscriptionEnabled = defaults.bool(forKey: "mockTranscriptionEnabled")
        #endif
        recordingMode = HotkeyMonitor.RecordingMode(rawValue: defaults.string(forKey: "recordingMode") ?? "") ?? .hold
        hotkeyChoice = HotkeyMonitor.HotkeyChoice(rawValue: defaults.string(forKey: "hotkeyChoice") ?? "") ?? .rightCommand
    }

    func setStatus(_ newStatus: Status) {
        status = newStatus
        switch newStatus {
        case .idle:
            break
        case .recording:
            floatingStatusDismissed = false
            floatingStatusTransientVisible = false
            transientResult = nil
            feedbackMessage = "Recording..."
            lastPasteSummary = nil
            clipboardFeedback = nil
        case .transcribing:
            floatingStatusDismissed = false
            floatingStatusTransientVisible = false
            feedbackMessage = "Sending audio..."
        case .error(let message):
            floatingStatusDismissed = false
            floatingStatusTransientVisible = false
            transientResult = nil
            feedbackMessage = message
        }
    }

    func showError(_ message: String) {
        status = .error(message)
        feedbackMessage = message
        transientResult = nil
        floatingStatusDismissed = false
        floatingStatusTransientVisible = false
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
        apiKeyState = hasApiKey ? .ready : .needsAction("Add Groq API key")
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
        } else if asyncPasteEnabled {
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

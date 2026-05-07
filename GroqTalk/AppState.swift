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

    private(set) var status: Status = .idle

    // MARK: - Timer state

    var recordingStartTime: Date?
    var recordingDuration: TimeInterval = 0
    var transcribingIconFrame: Int = 0
    var lastPasteSummary: String?

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

    var isError: Bool {
        if case .error = status { return true }
        return false
    }

    var menuBarIcon: String {
        switch status {
        case .idle: "waveform"
        case .recording: "waveform.circle.fill"
        case .transcribing:
            transcribingIconFrame == 0 ? "ellipsis.circle" : "ellipsis.circle.fill"
        case .error: "exclamationmark.triangle.fill"
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
        asyncPasteEnabled = defaults.bool(forKey: "asyncPasteEnabled")
        #if DEBUG
        mockTranscriptionEnabled = defaults.bool(forKey: "mockTranscriptionEnabled")
        #endif
        recordingMode = HotkeyMonitor.RecordingMode(rawValue: defaults.string(forKey: "recordingMode") ?? "") ?? .hold
        hotkeyChoice = HotkeyMonitor.HotkeyChoice(rawValue: defaults.string(forKey: "hotkeyChoice") ?? "") ?? .rightCommand
    }

    func setStatus(_ newStatus: Status) {
        status = newStatus
    }

    func showError(_ message: String) {
        status = .error(message)
    }

    func clearError() {
        if case .error = status {
            status = .idle
        }
    }

    func recordPaste(_ delivery: PasteDelivery) {
        lastPasteSummary = "Last paste: \(delivery.label)"
    }
}

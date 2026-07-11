import AVFoundation
import AppKit
import CoreAudio
import SwiftUI

extension Notification.Name {
    static let foilHistoryUITestCommandRelay =
        Notification.Name("com.neonwatty.Foil.uiTests.historyCommand.relay")
    static let foilOnboardingUITestCommandRelay =
        Notification.Name("com.neonwatty.Foil.uiTests.onboardingCommand.relay")
}

struct HistoryUITestCommand: Equatable {
    let id = UUID()
    let name: String
    let query: String?
    let filter: String?
    let appName: String?
    let transformKind: String?
    let index: Int

    init?(notification: Notification) {
        guard let name = notification.userInfo?["command"] as? String else { return nil }
        self.name = name
        self.query = notification.userInfo?["query"] as? String
        self.filter = notification.userInfo?["filter"] as? String
        self.appName = notification.userInfo?["appName"] as? String
        self.transformKind = notification.userInfo?["transformKind"] as? String
        self.index = notification.userInfo?["index"] as? Int
            ?? (notification.userInfo?["index"] as? NSNumber)?.intValue
            ?? 0
    }
}

struct OnboardingUITestCommand: Equatable {
    let id = UUID()
    let name: String

    init?(notification: Notification) {
        guard let name = notification.userInfo?["command"] as? String else { return nil }
        self.name = name
    }
}

/// Encapsulates all UI-testing and automation-smoke helpers that were previously
/// inlined in AppDelegate.  Create one instance in `applicationDidFinishLaunching`
/// and call `configureUITestingIfNeeded()` / `configureAutomationSmokeIfNeeded()`.
@MainActor
final class UITestingController {

    // MARK: - Public constant

    static let automationMockSuccessNotification =
        Notification.Name("com.neonwatty.Foil.automation.mockSuccess")
    static let automationQueuedEnqueueNotification =
        Notification.Name("com.neonwatty.Foil.automation.queuedEnqueue")
    static let automationQueuedDeliverNextNotification =
        Notification.Name("com.neonwatty.Foil.automation.queuedDeliverNext")
    static let openHistoryNotification =
        Notification.Name("com.neonwatty.Foil.uiTests.openHistory")
    static let openHelpNotification =
        Notification.Name("com.neonwatty.Foil.uiTests.openHelp")
    static let runSetupCheckNotification =
        Notification.Name("com.neonwatty.Foil.uiTests.runSetupCheck")
    static let historyCommandNotification =
        Notification.Name("com.neonwatty.Foil.uiTests.historyCommand")
    static let onboardingCommandNotification =
        Notification.Name("com.neonwatty.Foil.uiTests.onboardingCommand")
    static let appCommandNotification =
        Notification.Name("com.neonwatty.Foil.uiTests.appCommand")
    static var stateSnapshotURL: URL {
        if let path = ProcessInfo.processInfo.environment["FOIL_UITEST_STATE_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foil-ui-tests-state.json")
    }
    static var commandInboxURL: URL? {
        guard let path = ProcessInfo.processInfo.environment["FOIL_UITEST_COMMAND_PATH"],
              !path.isEmpty
        else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Dependencies

    private let appState: AppState
    private let queuedPasteQueue: QueuedPasteQueue
    private let history: TranscriptionHistory
    private let usageEventStore: UsageEventStore
    private let pasteController: PasteController

    /// Starts the transcribing spinner animation in the host (AppDelegate).
    private let startTranscribingAnimation: () -> Void
    /// Stops the transcribing spinner animation in the host (AppDelegate).
    private let stopTranscribingAnimation: () -> Void

    // Callbacks used when building MenuBarView inside the test window.
    private let onRetry: () -> Void
    private let onPasteLast: () -> Void
    private let onStartRecording: () -> Void
    private let onStopRecording: () -> Void
    private let onCancelRecording: () -> Void
    private let onCancelTranscription: () -> Void
    private let onHotkeyChanged: () -> Void
    private let onOpenAccessibility: () -> Void
    private let onOpenMicrophone: () -> Void
    private let onRunSetupCheck: () -> Void
    private let onRetryRecord: (TranscriptionRecord) -> Void
    private let onPasteText: (String) -> Void
    private let onReplaceRecordingController: (RecordingController) -> Void
    private let onSimulateSelectedHotkeyCycle: () -> Void

    // MARK: - Window storage

    private var uiTestWindow: NSWindow?
    private var uiTestAppShellWindow: NSWindow?
    private var uiTestHistoryWindow: NSWindow?
    private var uiTestCommandFileTimer: Timer?
    private var lastUITestCommandFileID: String?
    private var recordingEvents: [RecordingEventSnapshot] = []

    private struct StateSnapshot: Encodable {
        let statusText: String
        let sessionTitle: String
        let sessionDetail: String
        let accessibilityText: String
        let accessibilityActionTitle: String?
        let microphoneText: String
        let microphoneActionTitle: String?
        let apiKeyText: String
        let apiKeyActionTitle: String?
        let canStartRecording: Bool
        let recordingEvents: [RecordingEventSnapshot]
    }

    private struct RecordingEventSnapshot: Encodable {
        let name: String
        let detail: String?
        let uptimeNanoseconds: UInt64
    }

    // MARK: - Init

    init(
        appState: AppState,
        queuedPasteQueue: QueuedPasteQueue,
        history: TranscriptionHistory,
        usageEventStore: UsageEventStore,
        pasteController: PasteController,
        startTranscribingAnimation: @escaping () -> Void,
        stopTranscribingAnimation: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onPasteLast: @escaping () -> Void,
        onStartRecording: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        onCancelRecording: @escaping () -> Void,
        onCancelTranscription: @escaping () -> Void,
        onHotkeyChanged: @escaping () -> Void,
        onOpenAccessibility: @escaping () -> Void,
        onOpenMicrophone: @escaping () -> Void,
        onRunSetupCheck: @escaping () -> Void,
        onRetryRecord: @escaping (TranscriptionRecord) -> Void,
        onPasteText: @escaping (String) -> Void,
        onReplaceRecordingController: @escaping (RecordingController) -> Void,
        onSimulateSelectedHotkeyCycle: @escaping () -> Void
    ) {
        self.appState = appState
        self.queuedPasteQueue = queuedPasteQueue
        self.history = history
        self.usageEventStore = usageEventStore
        self.pasteController = pasteController
        self.startTranscribingAnimation = startTranscribingAnimation
        self.stopTranscribingAnimation = stopTranscribingAnimation
        self.onRetry = onRetry
        self.onPasteLast = onPasteLast
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
        self.onCancelRecording = onCancelRecording
        self.onCancelTranscription = onCancelTranscription
        self.onHotkeyChanged = onHotkeyChanged
        self.onOpenAccessibility = onOpenAccessibility
        self.onOpenMicrophone = onOpenMicrophone
        self.onRunSetupCheck = onRunSetupCheck
        self.onRetryRecord = onRetryRecord
        self.onPasteText = onPasteText
        self.onReplaceRecordingController = onReplaceRecordingController
        self.onSimulateSelectedHotkeyCycle = onSimulateSelectedHotkeyCycle
    }

    deinit {
        uiTestCommandFileTimer?.invalidate()
    }

    // MARK: - Configuration entry points

    func configureUITestingIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing") else { return }

        if args.contains("--reset-defaults") {
            history.clear()
            _ = usageEventStore.deleteAll()
            appState.soundEffectsEnabled = true
            appState.keepOnClipboard = false
            appState.usageMetricsEnabled = true
            usageEventStore.isEnabled = true
            appState.asyncPasteEnabled = false
            appState.queuedPasteEnabled = false
            appState.queuedPasteMode = .stepThrough
            appState.selectedModel = "whisper-large-v3-turbo"
            appState.selectedAudioFormat = .m4a
            appState.selectedLanguage = .auto
            appState.transcriptProcessingMode = .raw
            appState.transcriptCleanupModel = "llama-3.1-8b-instant"
            appState.hotkeyChoice = .rightCommand
            appState.recordingMode = .hold
            appState.showFloatingStatus = false
            appState.updateAccessibilityState(isTrusted: true)
            appState.updateMicrophoneState(isReady: true)
            appState.apiKeyState = .ready
            appState.experimentalSkyLightPasteEnabled = false
            appState.pauseBrowserMediaWhileRecording = false
            appState.lastPasteSummary = nil
            #if DEBUG
            appState.mockTranscriptionEnabled = false
            #endif
        }

        if args.contains("--seed-setup-ready") {
            appState.updateAccessibilityState(isTrusted: true)
            appState.updateMicrophoneState(isReady: true)
            appState.apiKeyState = .ready
        }

        if args.contains("--seed-microphone-unknown") {
            appState.updateAccessibilityState(isTrusted: true)
            appState.microphoneState = .unknown
            appState.apiKeyState = .ready
        }

        if args.contains("--seed-microphone-denied") {
            appState.updateAccessibilityState(isTrusted: true)
            appState.updateMicrophoneState(isReady: false, message: "Allow microphone access")
            appState.apiKeyState = .ready
        }

        if args.contains("--seed-setup-failures") {
            appState.updateAccessibilityState(isTrusted: false)
            appState.updateMicrophoneState(isReady: false, message: "Allow microphone access")
            appState.apiKeyState = .needsAction("Add Groq API key")
        }

        if args.contains("--seed-no-audio-captured") {
            appState.recordNoAudioCaptured()
        }

        if args.contains("--seed-history") {
            history.clear()
            history.addSuccess(text: "Seeded transcript for UI testing.", sourceAppName: "Messages")
            history.addSuccess(text: "Second searchable transcript.", sourceAppName: "Mail")
            history.addFailure(error: "Seeded network failure", audioFileURL: nil)
        }

        if args.contains("--seed-usage-events") {
            seedUsageEvents()
        }

        if args.contains("--seed-usage-empty") {
            _ = usageEventStore.deleteAll()
            appState.usageMetricsEnabled = true
            usageEventStore.isEnabled = true
        }

        if args.contains("--seed-usage-disabled") {
            if usageEventStore.events.isEmpty {
                seedUsageEvents()
            }
            appState.usageMetricsEnabled = false
            usageEventStore.isEnabled = false
        }

        if args.contains("--seed-local-provider") {
            appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        }

        if args.contains("--seed-local-server-running") {
            appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
            appState.activeLocalWhisperModelID = .baseEN
            appState.localWhisperServerState = .running("http://127.0.0.1:8080/v1")
        }

        if args.contains("--seed-local-server-starting") {
            appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
            appState.localWhisperSetupModelID = .largeV3Turbo
            appState.localWhisperServerState = .starting("Large V3 Turbo")
        }

        if args.contains("--seed-openai-provider") {
            appState.selectedTranscriptionProviderPresetID = .openAIWhisper
        }

        if args.contains("--seed-invalid-custom-provider") {
            appState.selectedTranscriptionProviderPresetID = .customOpenAICompatible
            appState.customTranscriptionBaseURL = "file:///tmp/whisper"
            appState.customTranscriptionModel = "whisper-1"
        }

        if args.contains("--seed-custom-provider") {
            appState.selectedTranscriptionProviderPresetID = .customOpenAICompatible
            appState.customTranscriptionBaseURL = "http://127.0.0.1:9090/v1"
            appState.customTranscriptionModel = "tiny-test-model"
        }

        if args.contains("--seed-async-paste-enabled") {
            appState.asyncPasteEnabled = true
        }

        if args.contains("--seed-queued-paste-enabled") {
            appState.queuedPasteEnabled = true
        }

        if args.contains("--seed-queued-paste-drain") {
            appState.queuedPasteMode = .drain
        }

        if args.contains("--seed-cleanup-formatting-enabled") {
            appState.transcriptProcessingMode = .cleanUp
        }

        if args.contains("--seed-active-mode-bullets") {
            appState.transcriptProcessingMode = .cleanUp
        }

        if args.contains("--seed-active-mode-numbered") {
            appState.transcriptProcessingMode = .cleanUp
        }

        if args.contains("--seed-active-mode-summary") {
            appState.transcriptProcessingMode = .cleanUp
        }

        if args.contains("--seed-cleanup-provider-none") {
            appState.transcriptCleanupProviderID = .none
        }

        if args.contains("--seed-openai-cleanup-provider") {
            appState.transcriptCleanupProviderID = .openAI
            appState.openAITranscriptCleanupModel = "gpt-5.4-mini"
        }

        if args.contains("--seed-history-reclean-enabled") {
            appState.transcriptProcessingMode = .cleanUp
            appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
            appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
            appState.customTranscriptCleanupModel = "deterministic-ui-test-cleanup"
        }

        if args.contains("--seed-history-transform-enabled") {
            appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
            appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
            appState.customTranscriptCleanupModel = "deterministic-ui-test-transform"
        }

        if args.contains("--seed-floating-status-enabled") {
            appState.showFloatingStatus = true
        }

        if args.contains("--seed-floating-warning") {
            appState.showFloatingStatus = true
            appState.floatingStatusTransientVisible = true
            appState.transientResult = .clipboardFallback
            appState.lastPasteSummary = "Fallback: copied to clipboard"
            appState.clipboardFeedback = "Text is on the clipboard"
        }

        if args.contains("--seed-recording") {
            appState.setStatus(.recording)
            appState.recordingStartTime = Date()
            appState.recordingDuration = 0
        }

        if args.contains("--seed-custom-hotkey") {
            appState.hotkeyChoice = .custom
            appState.customHotkeyKeyCode = 0
            appState.customHotkeyModifiers = 0
            appState.customHotkeyLabel = ""
        }

        #if DEBUG
        if args.contains("--seed-mock-transcription-enabled") {
            appState.mockTranscriptionEnabled = true
        }
        #endif

        UserDefaults(suiteName: "com.neonwatty.Foil.UITests")?.synchronize()

        showUITestWindow()
        if args.contains("--show-app-shell") {
            showUITestAppShellWindow()
        }
        configureUITestCommandNotifications()
        configureUITestCommandFileRelay()
        configureLiveMicrophoneSmokeIfNeeded(args: args)
        configureSimulatedTranscriptionIfNeeded(args: args)
        applyTransientUITestState(args: args)
        writeStateSnapshot()
    }

    func configureAutomationSmokeIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--automation-smoke") else { return }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(runAutomationMockSuccess),
            name: UITestingController.automationMockSuccessNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(enqueueAutomationQueuedMock),
            name: UITestingController.automationQueuedEnqueueNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(deliverAutomationQueuedNext),
            name: UITestingController.automationQueuedDeliverNextNotification,
            object: nil
        )
        DiagnosticLog.write("automation smoke: enabled")
    }

    // MARK: - E2E transcription

    func configureE2ETranscribeIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--e2e-transcribe") else { return }
        guard AppDelegate.isE2ETranscriptionSmokeProcess() else {
            DiagnosticLog.write("E2E: release app smoke gate not enabled")
            return
        }
        configureE2EProviderOverrides()
        configureE2ECleanupOverrides()

        let wavURL: URL
        if let envPath = ProcessInfo.processInfo.environment["E2E_WAV_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            wavURL = URL(fileURLWithPath: envPath)
            DiagnosticLog.write("E2E: using WAV from environment at \(wavURL.path)")
        } else if let bundleURL = Bundle.main.url(forResource: "e2e-test-audio", withExtension: "wav") {
            wavURL = bundleURL
            DiagnosticLog.write("E2E: using bundled WAV at \(wavURL.path)")
        } else {
            DiagnosticLog.write("E2E: no WAV file found — set E2E_WAV_PATH or include e2e-test-audio.wav in bundle")
            return
        }

        let stub = E2EAudioStub(fileURL: wavURL)
        let controller = RecordingController(audioRecorder: stub, appState: appState)
        onReplaceRecordingController(controller)

        appState.selectedAudioFormat = .wav

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            DiagnosticLog.write("E2E: starting simulated recording")
            onStartRecording()
            try? await Task.sleep(for: .milliseconds(800))
            DiagnosticLog.write("E2E: stopping simulated recording")
            onStopRecording()
        }
    }

    private func seedUsageEvents() {
        _ = usageEventStore.deleteAll()
        appState.usageMetricsEnabled = true
        usageEventStore.isEnabled = true
        let events = [
            UsageEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                timestamp: usageSeedDate("2026-01-05T10:00:00Z"),
                wordCount: 120,
                sourceAppName: "Mail",
                sourceBundleIdentifier: "com.apple.mail",
                cleanupGroupID: "writing-comms",
                cleanupGroupName: "Writing and comms",
                processingMode: .cleanUp,
                cleanupProviderID: .groq,
                cleanupModel: "llama-3.1-8b-instant"
            ),
            UsageEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                timestamp: usageSeedDate("2026-01-05T13:00:00Z"),
                wordCount: 90,
                sourceAppName: "Messages (iMessage)",
                sourceBundleIdentifier: "com.apple.MobileSMS",
                cleanupGroupID: "writing-comms",
                cleanupGroupName: "Writing and comms",
                processingMode: .cleanUp,
                cleanupProviderID: .customOpenAICompatibleChat,
                cleanupModel: "gpt-5.4-mini"
            ),
            UsageEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
                timestamp: usageSeedDate("2026-01-06T11:00:00Z"),
                wordCount: 80,
                sourceAppName: "Terminal",
                sourceBundleIdentifier: "com.apple.Terminal",
                cleanupGroupID: "terminal-workflows",
                cleanupGroupName: "Terminal workflows",
                processingMode: .raw
            ),
            UsageEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
                timestamp: usageSeedDate("2026-01-06T12:00:00Z"),
                wordCount: 40,
                sourceAppName: "Terminal",
                sourceBundleIdentifier: "com.apple.Terminal",
                cleanupGroupID: "terminal-workflows",
                cleanupGroupName: "Terminal workflows",
                processingMode: .raw
            ),
            UsageEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000105")!,
                timestamp: usageSeedDate("2026-01-06T15:00:00Z"),
                wordCount: 110,
                sourceAppName: "Ghostty",
                sourceBundleIdentifier: "com.mitchellh.ghostty",
                cleanupGroupID: "terminal-workflows",
                cleanupGroupName: "Terminal workflows",
                processingMode: .raw
            ),
            UsageEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000106")!,
                timestamp: usageSeedDate("2026-01-07T09:00:00Z"),
                wordCount: 130,
                sourceAppName: "Google Chrome",
                sourceBundleIdentifier: "com.google.Chrome",
                cleanupGroupID: "browser-research",
                cleanupGroupName: "Browser research",
                processingMode: .cleanUp,
                cleanupProviderID: .groq,
                cleanupModel: "llama-3.1-8b-instant"
            ),
            UsageEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000107")!,
                timestamp: usageSeedDate("2026-01-07T10:30:00Z"),
                wordCount: 95,
                sourceAppName: "Codex",
                sourceBundleIdentifier: "com.openai.codex",
                cleanupGroupID: "terminal-workflows",
                cleanupGroupName: "Terminal workflows",
                processingMode: .cleanUp,
                cleanupProviderID: .customOpenAICompatibleChat,
                cleanupModel: "gpt-5.4-mini"
            ),
            UsageEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000108")!,
                timestamp: usageSeedDate("2026-01-07T14:00:00Z"),
                wordCount: 45,
                sourceAppName: "Messages (iMessage)",
                sourceBundleIdentifier: "com.apple.MobileSMS",
                cleanupGroupID: "writing-comms",
                cleanupGroupName: "Writing and comms",
                processingMode: .cleanUp,
                cleanupProviderID: .customOpenAICompatibleChat,
                cleanupModel: "gpt-5.4-mini"
            )
        ]
        for event in events {
            _ = usageEventStore.record(event)
        }
    }

    private func usageSeedDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? Date(timeIntervalSince1970: 0)
    }

    private func configureE2EProviderOverrides() {
        let env = ProcessInfo.processInfo.environment
        if env["E2E_TRANSCRIPTION_PROVIDER"] == TranscriptionProviderID.openAI.rawValue {
            appState.selectedTranscriptionProviderID = .openAI
            appState.apiKeyState = .ready
            DiagnosticLog.write("E2E: provider=openai model=\(appState.selectedTranscriptionModel)")
            return
        }

        if env["E2E_TRANSCRIPTION_PROVIDER"] == TranscriptionProviderID.openAICompatible.rawValue {
            appState.selectedTranscriptionProviderID = .openAICompatible
            appState.customTranscriptionBaseURL = env["E2E_TRANSCRIPTION_BASE_URL"] ?? appState.customTranscriptionBaseURL
            appState.customTranscriptionModel = env["E2E_TRANSCRIPTION_MODEL"] ?? appState.customTranscriptionModel
            appState.apiKeyState = .ready
            DiagnosticLog.write(
                "E2E: provider=openai-compatible baseURL=\(appState.customTranscriptionBaseURL) model=\(appState.customTranscriptionModel)"
            )
            return
        }

        appState.selectedTranscriptionProviderID = .groq
        if let model = env["E2E_TRANSCRIPTION_MODEL"], !model.isEmpty {
            appState.selectedModel = model
        }
        if env["E2E_API_KEY"]?.isEmpty == false {
            appState.apiKeyState = .ready
        } else {
            appState.refreshApiKeyState()
        }
        DiagnosticLog.write("E2E: provider=groq model=\(appState.selectedModel)")
    }

    private func configureE2ECleanupOverrides() {
        let env = ProcessInfo.processInfo.environment
        guard let rawProvider = env["E2E_CLEANUP_PROVIDER"],
              !rawProvider.isEmpty,
              let providerID = TranscriptCleanupProviderID(rawValue: rawProvider) else {
            return
        }

        appState.transcriptCleanupProviderID = providerID
        guard providerID != .none else {
            appState.transcriptProcessingMode = .raw
            DiagnosticLog.write("E2E: cleanup provider=none")
            return
        }

        if let rawMode = env["E2E_CLEANUP_MODE"],
           !rawMode.isEmpty,
           let mode = TranscriptProcessingMode(rawValue: rawMode) {
            appState.transcriptProcessingMode = mode
        } else {
            appState.transcriptProcessingMode = .cleanUp
        }
        switch providerID {
        case .none:
            break
        case .groq:
            if let model = env["E2E_CLEANUP_MODEL"], !model.isEmpty {
                appState.transcriptCleanupModel = model
            }
            DiagnosticLog.write("E2E: cleanup provider=groq model=\(appState.transcriptCleanupModel)")
        case .openAI:
            if let model = env["E2E_CLEANUP_MODEL"], !model.isEmpty {
                appState.openAITranscriptCleanupModel = model
            }
            DiagnosticLog.write("E2E: cleanup provider=openai model=\(appState.openAITranscriptCleanupModel)")
        case .customOpenAICompatibleChat:
            appState.customTranscriptCleanupBaseURL = env["E2E_CLEANUP_BASE_URL"] ?? appState.customTranscriptCleanupBaseURL
            appState.customTranscriptCleanupModel = env["E2E_CLEANUP_MODEL"] ?? appState.customTranscriptCleanupModel
            DiagnosticLog.write(
                "E2E: cleanup provider=custom-openai-compatible-chat baseURL=\(appState.customTranscriptCleanupBaseURL) model=\(appState.customTranscriptCleanupModel)"
            )
        }
    }

    #if DEBUG
    private final class RecordingCueAcceptanceAudioStub: AudioRecording {
        var levelUpdateHandler: ((Float) -> Void)?

        private let onStartRecording: () -> Void
        private let onStopRecording: () -> Void

        init(
            onStartRecording: @escaping () -> Void,
            onStopRecording: @escaping () -> Void = {}
        ) {
            self.onStartRecording = onStartRecording
            self.onStopRecording = onStopRecording
        }

        func startRecording(deviceID: AudioDeviceID?) throws {
            onStartRecording()
        }

        func stopRecordingAsync(format: AudioFormat) async throws -> URL? {
            onStopRecording()
            return nil
        }

        func cancelRecording() {
        }
    }
    #endif

    private func prepareRecordingCueAcceptance() {
        #if DEBUG
        clearRecordingEvents()
        appState.soundEffectsEnabled = true
        appState.recordingStartSoundCue = .submarine
        appState.recordingEndSoundCue = .pop
        appState.updateAccessibilityState(isTrusted: true)
        appState.updateMicrophoneState(isReady: true)
        appState.apiKeyState = .ready
        appState.setStatus(.idle)

        let defaults = UserDefaults(suiteName: "com.neonwatty.Foil.UITests") ?? .standard
        let soundPlayer = SoundPlayer(defaults: defaults) { [weak self] systemSoundName in
            self?.appendRecordingEvent("startCue", detail: systemSoundName)
        }
        let audioStub = RecordingCueAcceptanceAudioStub { [weak self] in
            self?.appendRecordingEvent("audioRecorderStart")
        }
        let controller = RecordingController(
            audioRecorder: audioStub,
            appState: appState,
            playStartCueBeforeRecording: { [weak self] in
                let played = soundPlayer.playStartSound()
                if played {
                    self?.appendRecordingEvent("preRollScheduled")
                }
                return played
            },
            startCuePreRollNanoseconds: 300_000_000
        )
        onReplaceRecordingController(controller)
        writeStateSnapshot()
        DiagnosticLog.write("UITesting: recording cue acceptance prepared")
        #else
        DiagnosticLog.write("UITesting: recording cue acceptance skipped outside DEBUG")
        #endif
    }

    private func prepareHotkeySwitchingAcceptance() {
        #if DEBUG
        clearRecordingEvents()
        appState.soundEffectsEnabled = false
        appState.updateAccessibilityState(isTrusted: true)
        appState.updateMicrophoneState(isReady: true)
        appState.apiKeyState = .ready
        appState.recordingMode = .hold
        appState.setStatus(.idle)

        let audioStub = RecordingCueAcceptanceAudioStub(
            onStartRecording: { [weak self] in
                self?.appendRecordingEvent("audioRecorderStart")
            },
            onStopRecording: { [weak self] in
                self?.appendRecordingEvent("audioRecorderStop")
            }
        )
        let controller = RecordingController(
            audioRecorder: audioStub,
            appState: appState,
            playStartCueBeforeRecording: { false },
            startCuePreRollNanoseconds: 0
        )
        onReplaceRecordingController(controller)
        writeStateSnapshot()
        DiagnosticLog.write("UITesting: hotkey switching acceptance prepared")
        #else
        DiagnosticLog.write("UITesting: hotkey switching acceptance skipped outside DEBUG")
        #endif
    }

    // MARK: - Live microphone smoke

    private func configureLiveMicrophoneSmokeIfNeeded(args: [String]) {
        guard args.contains("--live-microphone-smoke") else { return }

        let env = ProcessInfo.processInfo.environment
        #if !DEBUG
        guard env["FOIL_ENABLE_RELEASE_LIVE_MICROPHONE_SMOKE"] == "1" else {
            DiagnosticLog.write("live microphone smoke: skipped outside DEBUG without explicit release gate")
            return
        }
        #endif

        let resultPath = env["LIVE_MICROPHONE_RESULT_PATH"] ?? "/tmp/foil-live-microphone-result.txt"
        let duration = TimeInterval(env["LIVE_MICROPHONE_DURATION_SECONDS"] ?? "") ?? 2
        let signingIdentity = env["LIVE_MICROPHONE_SIGNING_IDENTITY"] ?? "unknown"
        let inputRouteRequest = env["LIVE_MICROPHONE_INPUT_ROUTE"].flatMap { value in
            value.isEmpty ? nil : value
        } ?? "system-default"
        let appleVoiceText = env["LIVE_MICROPHONE_APPLE_VOICE_TEXT"].flatMap { text in
            text.isEmpty ? nil : text
        }
        let selectedInputDeviceUID = appState.selectedInputDeviceUID
        let liveMicrophoneAppState = appState
        try? FileManager.default.removeItem(atPath: resultPath)

        DiagnosticLog.write(
            "live microphone smoke: starting duration=\(duration) resultPath=\(resultPath) inputRouteRequest=\(inputRouteRequest) appleVoice=\(appleVoiceText != nil)"
        )
        Task.detached {
            let recorder = AudioRecorder()
            let levelLock = NSLock()
            var levelSamples: [Float] = []
            recorder.levelUpdateHandler = { level in
                levelLock.withLock {
                    levelSamples.append(level)
                }
            }
            let startedAt = Date()
            let appPath = Bundle.main.bundlePath
            var permissionStatus = Self.liveMicrophoneAuthorizationStatus()
            Self.writeLiveMicrophoneResult(
                path: resultPath,
                status: "started",
                detail: "Recorder start requested; waiting for stop result.",
                elapsed: 0,
                bytes: 0,
                appPath: appPath,
                signingIdentity: signingIdentity,
                microphonePermissionStatus: Self.microphonePermissionDescription(permissionStatus),
                recordingStarted: false,
                recordingStopped: false,
                appleVoiceText: appleVoiceText,
                inputRouteRequest: inputRouteRequest
            )
            if permissionStatus == .notDetermined {
                Self.writeLiveMicrophoneResult(
                    path: resultPath,
                    status: "permission_requested",
                    detail: "Microphone permission requested; waiting for macOS TCC response.",
                    elapsed: Date().timeIntervalSince(startedAt),
                    bytes: 0,
                    appPath: appPath,
                    signingIdentity: signingIdentity,
                    microphonePermissionStatus: Self.microphonePermissionDescription(permissionStatus),
                    recordingStarted: false,
                    recordingStopped: false,
                    appleVoiceText: appleVoiceText,
                    inputRouteRequest: inputRouteRequest
                )
                _ = await Self.requestMicrophoneAccessForLiveSmoke(timeoutSeconds: 15)
                permissionStatus = Self.liveMicrophoneAuthorizationStatus()
            }
            guard permissionStatus == .authorized else {
                Self.writeLiveMicrophoneResult(
                    path: resultPath,
                    status: "fail",
                    detail: "Microphone permission is \(Self.microphonePermissionDescription(permissionStatus)); grant access and rerun live microphone QA.",
                    elapsed: Date().timeIntervalSince(startedAt),
                    bytes: 0,
                    appPath: appPath,
                    signingIdentity: signingIdentity,
                    microphonePermissionStatus: Self.microphonePermissionDescription(permissionStatus),
                    recordingStarted: false,
                    recordingStopped: false,
                    appleVoiceText: appleVoiceText,
                    inputRouteRequest: inputRouteRequest
                )
                return
            }
            let inputDevices = AudioRecorder.availableInputDevices()
            let inputDevicesDescription = Self.liveMicrophoneInputDevicesDescription(inputDevices)
            guard !inputDevices.isEmpty else {
                Self.writeLiveMicrophoneResult(
                    path: resultPath,
                    status: "fail",
                    detail: "No input devices are available; live microphone QA requires a real or virtual microphone.",
                    elapsed: Date().timeIntervalSince(startedAt),
                    bytes: 0,
                    appPath: appPath,
                    signingIdentity: signingIdentity,
                    microphonePermissionStatus: Self.microphonePermissionDescription(permissionStatus),
                    recordingStarted: false,
                    recordingStopped: false,
                    appleVoiceText: appleVoiceText,
                    inputRouteRequest: inputRouteRequest,
                    availableInputDevices: inputDevicesDescription
                )
                return
            }

            let routeSelection = Self.liveMicrophoneRouteSelection(
                request: inputRouteRequest,
                selectedInputDeviceUID: selectedInputDeviceUID,
                inputDevices: inputDevices
            )
            guard routeSelection.failureDetail == nil else {
                Self.writeLiveMicrophoneResult(
                    path: resultPath,
                    status: "fail",
                    detail: routeSelection.failureDetail ?? "Requested input route could not be resolved.",
                    elapsed: Date().timeIntervalSince(startedAt),
                    bytes: 0,
                    appPath: appPath,
                    signingIdentity: signingIdentity,
                    microphonePermissionStatus: Self.microphonePermissionDescription(permissionStatus),
                    recordingStarted: false,
                    recordingStopped: false,
                    appleVoiceText: appleVoiceText,
                    inputRouteRequest: inputRouteRequest,
                    selectedInputDevice: routeSelection.device,
                    availableInputDevices: inputDevicesDescription
                )
                return
            }

            do {
                let deviceID = AudioRecorder.prepareInputDeviceForRecording(selectedUID: routeSelection.uid)
                try recorder.startRecording(deviceID: deviceID)
                await Self.setLiveMicrophoneUXRecording(appState: liveMicrophoneAppState, startedAt: startedAt)
                Self.writeLiveMicrophoneResult(
                    path: resultPath,
                    status: "recording",
                    detail: "Recorder started; deviceID=\(deviceID.map(String.init) ?? "systemDefault"); waiting to stop.",
                    elapsed: Date().timeIntervalSince(startedAt),
                    bytes: 0,
                    appPath: appPath,
                    signingIdentity: signingIdentity,
                    microphonePermissionStatus: Self.microphonePermissionDescription(permissionStatus),
                    recordingStarted: true,
                    recordingStopped: false,
                    appleVoiceText: appleVoiceText,
                    inputRouteRequest: inputRouteRequest,
                    selectedInputDevice: routeSelection.device,
                    preparedDeviceID: deviceID,
                    availableInputDevices: inputDevicesDescription
                )
                var appleVoiceProcess: Process?
                var appleVoiceStarted = false
                var appleVoiceExitStatus: Int32?
                if let appleVoiceText {
                    try await Task.sleep(for: .milliseconds(300))
                    appleVoiceProcess = Self.startAppleVoice(appleVoiceText)
                    appleVoiceStarted = appleVoiceProcess != nil
                }
                try await Task.sleep(for: .milliseconds(Int(duration * 1000)))
                if let appleVoiceProcess {
                    if appleVoiceProcess.isRunning {
                        appleVoiceProcess.terminate()
                    }
                    appleVoiceProcess.waitUntilExit()
                    appleVoiceExitStatus = appleVoiceProcess.terminationStatus
                }
                guard let audioURL = try await recorder.stopRecordingAsync(format: .wav) else {
                    let levels = Self.liveMicrophoneLevelSummary(samples: levelLock.withLock { levelSamples })
                    await Self.setLiveMicrophoneUXIdle(appState: liveMicrophoneAppState)
                    Self.writeLiveMicrophoneResult(
                        path: resultPath,
                        status: "fail",
                        detail: "No audio buffers were captured. Check microphone permission, selected input device, and input level.",
                        elapsed: Date().timeIntervalSince(startedAt),
                        bytes: 0,
                        appPath: appPath,
                        signingIdentity: signingIdentity,
                        microphonePermissionStatus: Self.microphonePermissionDescription(permissionStatus),
                        recordingStarted: true,
                        recordingStopped: true,
                        appleVoiceText: appleVoiceText,
                        inputRouteRequest: inputRouteRequest,
                        selectedInputDevice: routeSelection.device,
                        preparedDeviceID: deviceID,
                        availableInputDevices: inputDevicesDescription,
                        appleVoiceProcessStarted: appleVoiceStarted,
                        appleVoiceExitStatus: appleVoiceExitStatus,
                        levelSampleCount: levels.count,
                        peakLevel: levels.peak,
                        averageLevel: levels.average
                    )
                    return
                }
                let bytes = (try? audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let levels = Self.liveMicrophoneLevelSummary(samples: levelLock.withLock { levelSamples })
                let fileLevels = Self.liveMicrophoneAudioFileLevelSummary(url: audioURL)
                let observedPeakLevel = max(levels.peak, fileLevels.peak)
                let appleVoiceStartedOK = appleVoiceText == nil || appleVoiceStarted
                let minimumPeakLevel: Float = appleVoiceText == nil ? 0.001 : 0.02
                let capturedLevelOK = observedPeakLevel >= minimumPeakLevel
                let didPass = bytes > 0 && appleVoiceStartedOK && capturedLevelOK
                let capturedAudioPath = didPass ? "" : audioURL.path
                if didPass {
                    try? FileManager.default.removeItem(at: audioURL)
                }
                await Self.setLiveMicrophoneUXIdle(appState: liveMicrophoneAppState)
                Self.writeLiveMicrophoneResult(
                    path: resultPath,
                    status: didPass ? "pass" : "fail",
                    detail: Self.liveMicrophoneSuccessDetail(
                        bytes: bytes,
                        appleVoiceText: appleVoiceText,
                        appleVoiceStarted: appleVoiceStarted,
                        peakLevel: observedPeakLevel
                    ),
                    elapsed: Date().timeIntervalSince(startedAt),
                    bytes: bytes,
                    appPath: appPath,
                    signingIdentity: signingIdentity,
                    microphonePermissionStatus: Self.microphonePermissionDescription(permissionStatus),
                    recordingStarted: true,
                    recordingStopped: true,
                    appleVoiceText: appleVoiceText,
                    inputRouteRequest: inputRouteRequest,
                    selectedInputDevice: routeSelection.device,
                    preparedDeviceID: deviceID,
                    availableInputDevices: inputDevicesDescription,
                    appleVoiceProcessStarted: appleVoiceStarted,
                    appleVoiceExitStatus: appleVoiceExitStatus,
                    filePeakLevel: fileLevels.peak,
                    fileAverageLevel: fileLevels.average,
                    capturedAudioPath: capturedAudioPath,
                    levelSampleCount: levels.count,
                    peakLevel: levels.peak,
                    averageLevel: levels.average
                )
            } catch {
                recorder.cancelRecording()
                let levels = Self.liveMicrophoneLevelSummary(samples: levelLock.withLock { levelSamples })
                await Self.setLiveMicrophoneUXIdle(appState: liveMicrophoneAppState)
                Self.writeLiveMicrophoneResult(
                    path: resultPath,
                    status: "fail",
                    detail: "Recorder failed: \(error.localizedDescription)",
                    elapsed: Date().timeIntervalSince(startedAt),
                    bytes: 0,
                    appPath: appPath,
                    signingIdentity: signingIdentity,
                    microphonePermissionStatus: Self.microphonePermissionDescription(permissionStatus),
                    recordingStarted: false,
                    recordingStopped: false,
                    appleVoiceText: appleVoiceText,
                    inputRouteRequest: inputRouteRequest,
                    selectedInputDevice: routeSelection.device,
                    availableInputDevices: inputDevicesDescription,
                    levelSampleCount: levels.count,
                    peakLevel: levels.peak,
                    averageLevel: levels.average
                )
            }
        }
    }

    @MainActor
    private static func setLiveMicrophoneUXRecording(appState: AppState, startedAt: Date) {
        appState.recordingStartTime = startedAt
        appState.recordingDuration = 0
        appState.setStatus(.recording)
    }

    @MainActor
    private static func setLiveMicrophoneUXIdle(appState: AppState) {
        appState.recordingStartTime = nil
        appState.recordingDuration = 0
        if appState.status == .recording {
            appState.setStatus(.idle)
        }
        if appState.feedbackMessage == "Recording..." {
            appState.feedbackMessage = nil
        }
    }

    private func configureSimulatedTranscriptionIfNeeded(args: [String]) {
        guard args.contains("--simulate-success-after-launch")
                || args.contains("--simulate-failure-after-launch") else { return }
        let success = args.contains("--simulate-success-after-launch")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            simulateUITestTranscription(success: success)
        }
    }

    private func applyTransientUITestState(args: [String]) {
        if args.contains("--seed-transcribing") {
            appState.transcriptionStage = .transcribingAudio
            appState.setStatus(.transcribing)
        }
    }

    nonisolated private static func writeLiveMicrophoneResult(
        path: String,
        status: String,
        detail: String,
        elapsed: TimeInterval,
        bytes: Int,
        appPath: String,
        signingIdentity: String,
        microphonePermissionStatus: String,
        recordingStarted: Bool,
        recordingStopped: Bool,
        appleVoiceText: String? = nil,
        inputRouteRequest: String = "system-default",
        selectedInputDevice: AudioRecorder.AudioDevice? = nil,
        preparedDeviceID: AudioDeviceID? = nil,
        availableInputDevices: String = "",
        appleVoiceProcessStarted: Bool = false,
        appleVoiceExitStatus: Int32? = nil,
        filePeakLevel: Float = 0,
        fileAverageLevel: Float = 0,
        capturedAudioPath: String = "",
        levelSampleCount: Int = 0,
        peakLevel: Float = 0,
        averageLevel: Float = 0
    ) {
        let body = [
            "status=\(status)",
            "app_path=\(appPath)",
            "signing_identity=\(signingIdentity)",
            "microphone_permission_status=\(microphonePermissionStatus)",
            "recording_started=\(recordingStarted)",
            "recording_stopped=\(recordingStopped)",
            "input_route_request=\(inputRouteRequest)",
            "selected_input_uid=\(selectedInputDevice?.uid ?? "")",
            "selected_input_name=\(selectedInputDevice?.name ?? "")",
            "selected_input_transport=\(selectedInputDevice?.transport.displayName ?? "")",
            "selected_input_id=\(selectedInputDevice.map { String($0.id) } ?? "")",
            "prepared_device_id=\(preparedDeviceID.map(String.init) ?? "")",
            "available_input_devices=\(availableInputDevices)",
            "apple_voice_playback=\(appleVoiceText == nil ? "disabled" : "enabled")",
            "apple_voice_text=\(appleVoiceText ?? "")",
            "apple_voice_process_started=\(appleVoiceProcessStarted)",
            "apple_voice_exit_status=\(appleVoiceExitStatus.map(String.init) ?? "")",
            "level_sample_count=\(levelSampleCount)",
            "level_peak=\(String(format: "%.4f", peakLevel))",
            "level_average=\(String(format: "%.4f", averageLevel))",
            "file_level_peak=\(String(format: "%.4f", filePeakLevel))",
            "file_level_average=\(String(format: "%.4f", fileAverageLevel))",
            "captured_audio_path=\(capturedAudioPath)",
            "bytes=\(bytes)",
            "elapsed_seconds=\(String(format: "%.3f", elapsed))",
            "detail=\(detail)"
        ].joined(separator: "\n") + "\n"
        try? body.write(toFile: path, atomically: true, encoding: .utf8)
        DiagnosticLog.write("live microphone smoke: \(body.replacingOccurrences(of: "\n", with: " "))")
    }

    nonisolated private static func liveMicrophoneRouteSelection(
        request: String,
        selectedInputDeviceUID: String?,
        inputDevices: [AudioRecorder.AudioDevice]
    ) -> (uid: String?, device: AudioRecorder.AudioDevice?, failureDetail: String?) {
        switch request {
        case "built-in", "built_in", "builtin":
            guard let builtIn = inputDevices.first(where: { $0.transport == .builtIn }) else {
                return (
                    nil,
                    nil,
                    "Built-in microphone route was requested, but no built-in input device is available. Available inputs: \(liveMicrophoneInputDevicesDescription(inputDevices))"
                )
            }
            return (builtIn.uid, builtIn, nil)
        case "system-default", "system_default", "default":
            let selectedDevice = selectedInputDeviceUID.flatMap { uid in
                inputDevices.first { $0.uid == uid }
            }
            return (selectedInputDeviceUID, selectedDevice, nil)
        default:
            return (
                nil,
                nil,
                "Unknown live microphone input route '\(request)'. Use 'built-in' or 'system-default'."
            )
        }
    }

    nonisolated private static func liveMicrophoneInputDevicesDescription(_ devices: [AudioRecorder.AudioDevice]) -> String {
        guard !devices.isEmpty else { return "none" }
        return devices
            .map { "\($0.name)(uid=\($0.uid), id=\($0.id), transport=\($0.transport.displayName))" }
            .joined(separator: "; ")
    }

    nonisolated private static func startAppleVoice(_ text: String) -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [text]
        do {
            try process.run()
            DiagnosticLog.write("live microphone smoke: Apple voice started pid=\(process.processIdentifier)")
            return process
        } catch {
            DiagnosticLog.write("live microphone smoke: Apple voice failed error=\(error.localizedDescription)")
            return nil
        }
    }

    nonisolated private static func liveMicrophoneLevelSummary(samples: [Float]) -> (count: Int, peak: Float, average: Float) {
        guard !samples.isEmpty else {
            return (0, 0, 0)
        }
        let peak = samples.max() ?? 0
        let average = samples.reduce(Float(0), +) / Float(samples.count)
        return (samples.count, peak, average)
    }

    nonisolated private static func liveMicrophoneAudioFileLevelSummary(url: URL) -> (peak: Float, average: Float) {
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0,
                  let buffer = AVAudioPCMBuffer(
                      pcmFormat: file.processingFormat,
                      frameCapacity: AVAudioFrameCount(file.length)
                  ) else {
                return (0, 0)
            }
            try file.read(into: buffer)
            guard buffer.frameLength > 0,
                  let channelData = buffer.floatChannelData else {
                return (0, 0)
            }

            let channelCount = max(1, Int(buffer.format.channelCount))
            let frameCount = Int(buffer.frameLength)
            var peak: Float = 0
            var sumSquares: Float = 0
            var sampleCount = 0

            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    let sample = samples[frame]
                    peak = max(peak, abs(sample))
                    sumSquares += sample * sample
                }
                sampleCount += frameCount
            }

            guard sampleCount > 0 else { return (0, 0) }
            let rms = sqrt(sumSquares / Float(sampleCount))
            let normalizedPeak = min(max(peak / 0.35, 0), 1)
            let normalizedAverage = min(max(rms / 0.35, 0), 1)
            return (normalizedPeak, normalizedAverage)
        } catch {
            DiagnosticLog.write("live microphone smoke: failed to inspect captured audio level error=\(error.localizedDescription)")
            return (0, 0)
        }
    }

    nonisolated private static func liveMicrophoneSuccessDetail(
        bytes: Int,
        appleVoiceText: String?,
        appleVoiceStarted: Bool,
        peakLevel: Float
    ) -> String {
        guard bytes > 0 else {
            return "Captured audio file was empty."
        }
        if appleVoiceText != nil, !appleVoiceStarted {
            return "Apple voice playback was requested, but /usr/bin/say did not start."
        }
        if appleVoiceText != nil, peakLevel < 0.02 {
            return "Apple voice playback ran, but captured level peak was below threshold. Check speaker output, microphone route, and input level."
        }
        if appleVoiceText == nil, peakLevel < 0.001 {
            return "Captured audio file was non-empty, but the audio level was silent. Check microphone route and input level."
        }
        return appleVoiceText == nil ? "Captured microphone audio." : "Captured microphone audio while Apple voice playback was active."
    }

    nonisolated private static func requestMicrophoneAccessForLiveSmoke(timeoutSeconds: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false

            func resumeOnce(_ granted: Bool) {
                lock.withLock {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: granted)
                }
            }

            AVAudioApplication.requestRecordPermission { granted in
                DiagnosticLog.write("live microphone smoke: requestAccess granted=\(granted)")
                resumeOnce(granted)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                DiagnosticLog.write("live microphone smoke: requestAccess timed out")
                resumeOnce(false)
            }
        }
    }

    nonisolated private static func liveMicrophoneAuthorizationStatus() -> AVAuthorizationStatus {
        SystemSetupPermissionProvider.microphoneAuthorizationStatus(
            for: AVAudioApplication.shared.recordPermission
        )
    }

    nonisolated private static func microphonePermissionDescription(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            "authorized"
        case .denied:
            "denied"
        case .restricted:
            "restricted"
        case .notDetermined:
            "not_determined"
        @unknown default:
            "unknown"
        }
    }

    // MARK: - Automation smoke

    @objc private func runAutomationMockSuccess() {
        let target = PasteTarget.captureCurrentTarget()
        DiagnosticLog.write("automation smoke: requested target=\(String(describing: target))")
        Task { @MainActor in
            appState.asyncPasteEnabled = true
            appState.recordTargetCapture(target)
            #if DEBUG
            appState.mockTranscriptionEnabled = true
            #endif
            appState.clearError()
            appState.transcriptionStage = .transcribingAudio
            appState.setStatus(.transcribing)
            startTranscribingAnimation()
            try? await Task.sleep(for: .milliseconds(500))
            stopTranscribingAnimation()

            let text = "Mock transcription automation smoke"
            history.addSuccess(text: text, sourceAppName: target?.appName)
            appState.setStatus(.idle)

            pasteController.setPendingTarget(target)
            if target != nil {
                DiagnosticLog.write("ASYNC PATH: automation smoke pasting via pasteController target=\(target!.appName) pid=\(target!.pid)")
            }
            await pasteController.paste(text: text)
        }
    }

    @objc private func enqueueAutomationQueuedMock() {
        let target = PasteTarget.captureCurrentTarget()
        DiagnosticLog.write("automation queued smoke: enqueue requested target=\(String(describing: target))")
        Task { @MainActor in
            appState.queuedPasteEnabled = true
            appState.queuedPasteMode = .stepThrough
            onHotkeyChanged()
            appState.recordTargetCapture(target)
            #if DEBUG
            appState.mockTranscriptionEnabled = true
            #endif
            appState.clearError()
            let text = "Mock queued paste automation smoke"
            history.addSuccess(text: text, sourceAppName: target?.appName)
            queuedPasteQueue.enqueue(text: text, target: target, recordingStartTime: Date())
            appState.feedbackMessage = "Transcript queued"
            appState.floatingStatusTransientVisible = true
            appState.setStatus(.idle)
            DiagnosticLog.write("automation queued smoke: enqueued target=\(target?.appName ?? "nil") pending=\(queuedPasteQueue.pendingCount) blocked=\(queuedPasteQueue.blockedCount)")
        }
    }

    @objc private func deliverAutomationQueuedNext() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"
        DiagnosticLog.write("automation queued smoke: deliver next requested frontmost=\(frontmost)")
        Task { @MainActor in
            let delivery = await queuedPasteQueue.deliverNext()
            let after = NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"
            DiagnosticLog.write("automation queued smoke: deliver next result=\(delivery?.label ?? "nil") frontmostAfter=\(after) pending=\(queuedPasteQueue.pendingCount) blocked=\(queuedPasteQueue.blockedCount)")
        }
    }

    // MARK: - UI test windows

    private func showUITestWindow() {
        activateUITestApplication()
        let view = MenuBarView(
            appState: appState,
            queuedPasteQueue: queuedPasteQueue,
            history: history,
            onRetry: onRetry,
            onPasteLast: onPasteLast,
            onStartRecording: onStartRecording,
            onStopRecording: onStopRecording,
            onCancelRecording: onCancelRecording,
            onCancelTranscription: onCancelTranscription,
            onHotkeyChanged: onHotkeyChanged,
            onOpenFoil: { [weak self] in self?.showUITestAppShellWindow(selection: .home) },
            onOpenHistory: { [weak self] in self?.showUITestAppShellWindow(selection: .history) },
            onOpenSettings: { [weak self] in self?.showUITestAppShellWindow(selection: .general) },
            onOpenAccessibility: onOpenAccessibility,
            onOpenMicrophone: onOpenMicrophone,
            onCheckMicrophone: { [weak self] in self?.appState.updateMicrophoneState(isReady: true) },
            onRunSetupCheck: onRunSetupCheck,
            onSimulateSuccess: { [weak self] in self?.simulateUITestTranscription(success: true) },
            onSimulateFailure: { [weak self] in self?.simulateUITestTranscription(success: false) }
        )
        .accessibilityIdentifier("uiTest.controlCenter")
        .frame(width: 380, height: 560)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 580),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Foil UI Test"
        window.contentView = fixedHostingView(rootView: view, size: NSSize(width: 380, height: 560))
        window.center()
        window.makeKeyAndOrderFront(nil)
        activateUITestApplication()
        uiTestWindow = window
    }

    private func showUITestAppShellWindow(selection: FoilAppSection = .home) {
        activateUITestApplication()
        let view = FoilAppShellView(
            appState: appState,
            queuedPasteQueue: queuedPasteQueue,
            history: history,
            usageEventStore: usageEventStore,
            initialSelection: selection,
            onRetryRecord: { [weak self] record in self?.onRetryRecord(record) },
            onPasteText: { [weak self] text in self?.onPasteText(text) },
            onSaveAndRecleanVocabularyCorrection: historyRecleanUITestAction,
            onTransformTranscript: historyTransformUITestAction,
            onHotkeyChanged: onHotkeyChanged,
            onStartLocalWhisperServer: { _ in },
            onStopLocalWhisperServer: {},
            onStartRecording: onStartRecording,
            onStopRecording: onStopRecording,
            onCancelRecording: onCancelRecording,
            onCancelTranscription: onCancelTranscription,
            onPasteLast: onPasteLast
        )
        .frame(width: 940, height: 640)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppBrand.name
        window.contentView = fixedHostingView(rootView: view, size: NSSize(width: 940, height: 640))
        window.center()
        window.makeKeyAndOrderFront(nil)
        activateUITestApplication()
        uiTestAppShellWindow = window
    }

    private func showUITestHistoryWindow() {
        activateUITestApplication()
        let view = HistoryPopoverView(
            history: history,
            onRetry: { [weak self] record in self?.onRetryRecord(record) },
            onPaste: { [weak self] text in self?.onPasteText(text) },
            onSaveVocabularyTerm: { [weak self] term, note in
                self?.appState.addVocabularyTerm(term, note: note)
            },
            onSaveVocabularyCorrection: { [weak self] writtenAs, correctVersion, note, sourceRecordID, sourceAppName in
                self?.appState.addVocabularyCorrection(
                    writtenAs: writtenAs,
                    correctVersion: correctVersion,
                    note: note,
                    sourceRecordID: sourceRecordID,
                    sourceAppName: sourceAppName
                )
            },
            onSaveAndRecleanVocabularyCorrection: historyRecleanUITestAction,
            onTransformTranscript: historyTransformUITestAction,
            canSaveAndRecleanVocabularyCorrection: historyRecleanUITestAction != nil,
            canTransformHistoryTranscripts: historyTransformUITestAction != nil,
            showsHeader: true
        )
        .accessibilityIdentifier("history.testHost")
        .frame(width: 620, height: 560)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "History"
        window.contentView = fixedHostingView(rootView: view, size: NSSize(width: 620, height: 560))
        window.center()
        window.makeKeyAndOrderFront(nil)
        activateUITestApplication()
        uiTestHistoryWindow = window
    }

    private var historyRecleanUITestAction: ((String, String, String?, UUID, String?) async -> HistoryVocabularyRecleanResult)? {
        guard ProcessInfo.processInfo.arguments.contains("--seed-history-reclean-enabled") else {
            return nil
        }
        return { [weak self] writtenAs, correctVersion, note, sourceRecordID, sourceAppName in
            guard let self else { return .cleanupUnavailable }
            return await self.saveVocabularyCorrectionAndRecleanForUITesting(
                writtenAs: writtenAs,
                correctVersion: correctVersion,
                note: note,
                sourceRecordID: sourceRecordID,
                sourceAppName: sourceAppName
            )
        }
    }

    private func saveVocabularyCorrectionAndRecleanForUITesting(
        writtenAs: String,
        correctVersion: String,
        note: String?,
        sourceRecordID: UUID,
        sourceAppName: String?
    ) async -> HistoryVocabularyRecleanResult {
        guard appState.addVocabularyCorrection(
            writtenAs: writtenAs,
            correctVersion: correctVersion,
            note: note,
            sourceRecordID: sourceRecordID,
            sourceAppName: sourceAppName
        ) != nil else {
            return .saveRejected
        }
        guard history.records.contains(where: { $0.id == sourceRecordID && !$0.isFailure }) else {
            return .cleanupFailed
        }

        let corrected = correctVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        history.updateSuccess(id: sourceRecordID, text: "Re-cleaned History transcript uses \(corrected).")
        return .updated
    }

    private var historyTransformUITestAction: ((HistoryTransformKind, UUID, String, String?) async -> HistoryTransformResult)? {
        guard ProcessInfo.processInfo.arguments.contains("--seed-history-transform-enabled") else {
            return nil
        }
        return { [weak self] transformKind, sourceRecordID, text, sourceAppName in
            guard let self else { return .cleanupUnavailable }
            return await self.transformHistoryRecordForUITesting(
                transformKind: transformKind,
                sourceRecordID: sourceRecordID,
                text: text,
                sourceAppName: sourceAppName
            )
        }
    }

    private func transformHistoryRecordForUITesting(
        transformKind: HistoryTransformKind,
        sourceRecordID: UUID,
        text: String,
        sourceAppName: String?
    ) async -> HistoryTransformResult {
        guard history.records.contains(where: { $0.id == sourceRecordID && !$0.isFailure }) else {
            return .transformFailed
        }

        let transformedText: String
        switch transformKind {
        case .polish:
            transformedText = "Polish transform: \(text)"
        case .bulletize:
            transformedText = """
            - Alpha action from \(text)
            - Beta action preserves the original transcript context.
            """
        case .summarize:
            transformedText = "Summary: \(text)"
        }

        history.addTransformResult(
            text: transformedText,
            sourceRecordID: sourceRecordID,
            transformKind: transformKind,
            sourceAppName: sourceAppName
        )
        return .added
    }

    private func activateUITestApplication() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureUITestCommandNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openHistoryForUITest),
            name: UITestingController.openHistoryNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openHelpForUITest),
            name: UITestingController.openHelpNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(runSetupCheckForUITest),
            name: UITestingController.runSetupCheckNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleHistoryCommandForUITest(_:)),
            name: UITestingController.historyCommandNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOnboardingCommandForUITest(_:)),
            name: UITestingController.onboardingCommandNotification,
            object: nil
        )
    }

    private func configureUITestCommandFileRelay() {
        guard let commandInboxURL = Self.commandInboxURL else { return }
        try? FileManager.default.removeItem(at: commandInboxURL)
        uiTestCommandFileTimer?.invalidate()
        uiTestCommandFileTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollUITestCommandFile(at: commandInboxURL)
            }
        }
    }

    private func pollUITestCommandFile(at url: URL) {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = payload["id"] as? String,
              id != lastUITestCommandFileID,
              let notificationName = payload["notification"] as? String
        else {
            return
        }

        lastUITestCommandFileID = id
        let userInfo = payload["userInfo"] as? [String: Any]
        if notificationName == Self.historyCommandNotification.rawValue {
            handleHistoryCommandForUITest(
                Notification(name: Self.historyCommandNotification, object: nil, userInfo: userInfo)
            )
        } else if notificationName == Self.onboardingCommandNotification.rawValue {
            handleOnboardingCommandForUITest(
                Notification(name: Self.onboardingCommandNotification, object: nil, userInfo: userInfo)
            )
        } else if notificationName == Self.appCommandNotification.rawValue {
            handleAppCommandForUITest(
                Notification(name: Self.appCommandNotification, object: nil, userInfo: userInfo)
            )
        }
    }

    @objc private func openHistoryForUITest() {
        showUITestHistoryWindow()
    }

    @objc private func openHelpForUITest() {
        guard let url = URL(string: "https://github.com/usefoil/foil#troubleshooting") else {
            return
        }
        if let path = ProcessInfo.processInfo.environment["FOIL_UITEST_OPENED_URL_PATH"],
           !path.isEmpty {
            try? url.absoluteString.write(toFile: path, atomically: true, encoding: .utf8)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func runSetupCheckForUITest() {
        onRunSetupCheck()
    }

    @objc private func handleHistoryCommandForUITest(_ notification: Notification) {
        let command = notification.userInfo?["command"] as? String ?? "<missing>"
        DiagnosticLog.write("UITesting: received history command=\(command)")
        NotificationCenter.default.post(
            name: .foilHistoryUITestCommandRelay,
            object: nil,
            userInfo: notification.userInfo
        )
    }

    @objc private func handleOnboardingCommandForUITest(_ notification: Notification) {
        let command = notification.userInfo?["command"] as? String ?? "<missing>"
        DiagnosticLog.write("UITesting: received onboarding command=\(command)")
        NotificationCenter.default.post(
            name: .foilOnboardingUITestCommandRelay,
            object: nil,
            userInfo: notification.userInfo
        )
    }

    @objc private func handleAppCommandForUITest(_ notification: Notification) {
        let command = notification.userInfo?["command"] as? String ?? "<missing>"
        DiagnosticLog.write("UITesting: received app command=\(command)")
        switch command {
        case "selectOpenAIProvider":
            appState.selectedTranscriptionProviderPresetID = .openAIWhisper
        case "selectLocalProvider":
            appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        case "testProviderConnection":
            Task { @MainActor in
                await appState.testSelectedProviderConnection()
            }
        case "cancelTranscription":
            onCancelTranscription()
        case "clearRecordingEvents":
            clearRecordingEvents()
        case "prepareRecordingCueAcceptance":
            prepareRecordingCueAcceptance()
        case "prepareHotkeySwitchingAcceptance":
            prepareHotkeySwitchingAcceptance()
        case "seedCleanupFallbackWarning":
            appState.feedbackMessage = "Cleanup failed; pasted raw transcript."
            appState.floatingStatusTransientVisible = true
            appState.setStatus(.idle)
        case "setDefaultCleanupMode":
            let rawMode = notification.userInfo?["mode"] as? String ?? ""
            if let mode = TranscriptProcessingMode(rawValue: rawMode)?.normalizedActiveMode {
                appState.transcriptProcessingMode = mode
                writeStateSnapshot()
            }
        case "setDefaultCleanupPrompt":
            let prompt = notification.userInfo?["prompt"] as? String ?? ""
            appState.setCustomPrompt(prompt, for: .cleanUp)
            writeStateSnapshot()
        case "resetDefaultCleanupPrompt":
            appState.resetCustomPrompt(for: .cleanUp)
            writeStateSnapshot()
        case "resolveCleanupGroup":
            recordCleanupGroupResolutionForUITest(notification.userInfo)
        case "selectRecordingHotkey":
            if let rawValue = notification.userInfo?["choice"] as? String,
               let choice = HotkeyMonitor.HotkeyChoice(rawValue: rawValue) {
                appState.hotkeyChoice = choice
                if choice == .custom {
                    appState.customHotkeyKeyCode = 0x31
                    appState.customHotkeyModifiers = 0
                    appState.customHotkeyLabel = "Space"
                }
                appState.recordingMode = .hold
                onHotkeyChanged()
                writeStateSnapshot()
            }
        case "simulateSelectedHotkeyCycle":
            onSimulateSelectedHotkeyCycle()
        case "startRecording":
            onStartRecording()
        case "stopRecording":
            onStopRecording()
        default:
            break
        }
    }

    private func recordCleanupGroupResolutionForUITest(_ userInfo: [AnyHashable: Any]?) {
        let appContext = CleanupAppContext(
            displayName: userInfo?["displayName"] as? String,
            bundleIdentifier: userInfo?["bundleIdentifier"] as? String,
            appPath: userInfo?["appPath"] as? String
        )
        let resolution = appState.resolveCleanupGroup(for: appContext)
        let group = resolution.group
        appendRecordingEvent(
            "cleanupGroupResolution",
            detail: [
                "displayName=\(appContext.displayName ?? "")",
                "bundleIdentifier=\(appContext.bundleIdentifier ?? "")",
                "appPath=\(appContext.appPath ?? "")",
                "groupID=\(group.id)",
                "groupName=\(group.name)",
                "isDefault=\(group.isDefault)",
                "appMatcherCount=\(group.appMatchers.count)",
                "processingMode=\(group.processingMode.rawValue)",
                "providerID=\(resolution.provider.id.rawValue)"
            ].joined(separator: " ")
        )
    }

    func writeStateSnapshot() {
        let session = appState.sessionPresentation(
            hotkeyLabel: hotkeyLabel,
            hasRetryableFailure: history.records.contains { $0.isFailure },
            hasLastSuccess: history.records.contains { !$0.isFailure }
        )
        let snapshot = StateSnapshot(
            statusText: appState.statusText,
            sessionTitle: session.title,
            sessionDetail: session.detail,
            accessibilityText: permissionText(for: appState.accessibilityState),
            accessibilityActionTitle: actionTitle(for: appState.accessibilityState, readyTitle: nil, unknownTitle: "Open Settings", needsActionTitle: "Open Settings"),
            microphoneText: permissionText(for: appState.microphoneState),
            microphoneActionTitle: actionTitle(for: appState.microphoneState, readyTitle: nil, unknownTitle: "Check", needsActionTitle: "Open Settings"),
            apiKeyText: permissionText(for: appState.apiKeyState),
            apiKeyActionTitle: actionTitle(for: appState.apiKeyState, readyTitle: nil, unknownTitle: "Add Key", needsActionTitle: "Add Key"),
            canStartRecording: appState.canStartRecordingControl,
            recordingEvents: recordingEvents
        )

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: Self.stateSnapshotURL, options: Data.WritingOptions.atomic)
        } catch {
            DiagnosticLog.write("UITesting: failed to write state snapshot: \(error)")
        }
    }

    private func appendRecordingEvent(_ name: String, detail: String? = nil) {
        recordingEvents.append(
            RecordingEventSnapshot(
                name: name,
                detail: detail,
                uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
            )
        )
        writeStateSnapshot()
    }

    private func clearRecordingEvents() {
        recordingEvents.removeAll()
        writeStateSnapshot()
    }

    private var hotkeyLabel: String {
        switch appState.hotkeyChoice {
        case .rightCommand: "Right Command"
        case .rightOption: "Right Option"
        case .globeFn: "Globe/Fn"
        case .custom: appState.customHotkeyLabel.isEmpty ? "Custom" : appState.customHotkeyLabel
        }
    }

    private func permissionText(for state: AppState.PermissionState) -> String {
        switch state {
        case .ready:
            "Ready"
        case .needsAction(let message):
            message
        case .unknown:
            "Not checked"
        }
    }

    private func actionTitle(
        for state: AppState.PermissionState,
        readyTitle: String?,
        unknownTitle: String,
        needsActionTitle: String
    ) -> String? {
        switch state {
        case .ready:
            readyTitle
        case .unknown:
            unknownTitle
        case .needsAction:
            needsActionTitle
        }
    }

    // MARK: - Simulate transcription (UI testing)

    func simulateUITestTranscription(success: Bool) {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        Task { @MainActor in
            appState.clearError()
            appState.setStatus(.recording)
            // Use inline state mutation for the UI simulation -- does not go through RecordingController
            appState.recordingStartTime = Date()
            appState.recordingDuration = 0
            try? await Task.sleep(for: .milliseconds(300))
            appState.recordingStartTime = nil
            appState.recordingDuration = 0
            appState.transcriptionStage = .transcribingAudio
            appState.setStatus(.transcribing)
            startTranscribingAnimation()
            try? await Task.sleep(for: .milliseconds(1_200))
            appState.transcriptionStage = .cleaningTranscript
            try? await Task.sleep(for: .milliseconds(1_200))
            appState.transcriptionStage = .pasting
            try? await Task.sleep(for: .milliseconds(1_200))
            stopTranscribingAnimation()

            if success {
                let text = simulatedSuccessTranscriptText()
                appState.setStatus(.idle)
                if appState.queuedPasteEnabled {
                    let target = PasteTarget(
                        windowElement: nil,
                        windowID: nil,
                        pid: ProcessInfo.processInfo.processIdentifier,
                        appName: "Foil UI Test"
                    )
                    appState.recordTargetCapture(target)
                    history.addSuccess(text: text, sourceAppName: target.appName)
                    queuedPasteQueue.enqueue(text: text, target: target, recordingStartTime: Date())
                    appState.feedbackMessage = "Transcript queued"
                } else if appState.asyncPasteEnabled {
                    let target = PasteTarget(
                        windowElement: nil,
                        windowID: nil,
                        pid: ProcessInfo.processInfo.processIdentifier,
                        appName: "Foil UI Test"
                    )
                    appState.recordTargetCapture(target)
                    history.addSuccess(text: text, sourceAppName: target.appName)
                    pasteController.setPendingTarget(target)
                    await pasteController.paste(text: text)
                } else {
                    history.addSuccess(text: text)
                    await pasteController.pasteDirectly(text: text)
                }
            } else {
                history.addFailure(error: "Simulated transcription failure", audioFileURL: nil)
                appState.showError("Simulated transcription failure")
            }
        }
    }

    private func simulatedSuccessTranscriptText() -> String {
        switch appState.effectiveTranscriptProcessingMode {
        case .raw, .cleanUp, .rewriteClearly, .bulletize, .numbered, .summarize:
            "Mock async paste transcript"
        }
    }

    // MARK: - Helpers

    private func fixedHostingView<Content: View>(rootView: Content, size: NSSize) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        return hostingView
    }

}

import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct FoilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                appState: appDelegate.appState,
                queuedPasteQueue: appDelegate.queuedPasteQueue,
                history: appDelegate.history,
                onRetry: { [weak appDelegate] in appDelegate?.retryLast() },
                onRetryRecord: { [weak appDelegate] record in appDelegate?.retryRecord(record) },
                onPasteLast: { [weak appDelegate] in appDelegate?.pasteLastSuccess() },
                onPasteText: { [weak appDelegate] text in appDelegate?.paste(text: text) },
                onStartRecording: { [weak appDelegate] in appDelegate?.startRecordingFromControl() },
                onStopRecording: { [weak appDelegate] in appDelegate?.stopRecordingFromControl() },
                onCancelRecording: { [weak appDelegate] in appDelegate?.cancelRecordingFromControl() },
                onCancelTranscription: { [weak appDelegate] in appDelegate?.cancelTranscriptionFromControl() },
                onHotkeyChanged: { [weak appDelegate] in appDelegate?.applyHotkeyConfig() },
                onOpenSettings: { [weak appDelegate] in appDelegate?.showSettingsWindow() },
                onOpenAccessibility: { [weak appDelegate] in appDelegate?.openAccessibilitySettings() },
                onOpenMicrophone: { [weak appDelegate] in appDelegate?.openMicrophoneSettings() },
                onCheckMicrophone: { [weak appDelegate] in appDelegate?.checkMicrophonePermission() },
                onRunSetupCheck: { [weak appDelegate] in appDelegate?.runSetupCheck() },
                onCopySetupReport: { [weak appDelegate] in appDelegate?.copySetupReportToClipboard() }
            )
        } label: {
            appDelegate.menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Window("\(AppBrand.name) Setup", id: "api-key-setup") {
            ApiKeySetupView(
                provider: appDelegate.appState.selectedTranscriptionProvider,
                onSaved: { [weak appDelegate] in
                    appDelegate?.appState.refreshApiKeyState()
                },
                validateApiKey: { [weak appDelegate] key in
                    guard let appDelegate else { return }
                    try await appDelegate.validateSelectedProviderApiKey(key)
                }
            )
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("History", id: "history") {
            HistoryPopoverView(
                history: appDelegate.history,
                onRetry: { [weak appDelegate] record in appDelegate?.retryRecord(record) },
                onPaste: { [weak appDelegate] text in appDelegate?.paste(text: text) },
                showsHeader: true
            )
        }
        .defaultSize(width: 620, height: 560)

        Settings {
            SettingsView(
                appState: appDelegate.appState,
                history: appDelegate.history,
                onHotkeyChanged: { [weak appDelegate] in appDelegate?.applyHotkeyConfig() },
                onCopySetupReport: { [weak appDelegate] in appDelegate?.copySetupReportToClipboard() },
                onExportDiagnostics: { [weak appDelegate] in appDelegate?.exportDiagnostics() }
            )
        }
        .commands {
            CommandGroup(after: .help) {
                Button("Copy Setup Report") {
                    appDelegate.copySetupReportToClipboard()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

                Button("Export Diagnostics...") {
                    appDelegate.exportDiagnostics()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }
        }
    }
}

protocol SetupPermissionProviding {
    var accessibilityTrusted: Bool { get }
    var microphoneAuthorizationStatus: AVAuthorizationStatus { get }
    func requestMicrophoneAccess() async -> MicrophoneAccessRequestResult
}

enum MicrophoneAccessRequestResult: Equatable {
    case granted
    case denied
    case timedOut

    var isReady: Bool {
        self == .granted
    }
}

struct SystemSetupPermissionProvider: SetupPermissionProviding {
    private let microphoneRequestTimeout: TimeInterval = 15

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var microphoneAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestMicrophoneAccess() async -> MicrophoneAccessRequestResult {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false

            func resumeOnce(_ result: MicrophoneAccessRequestResult) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: result)
            }

            AVCaptureDevice.requestAccess(for: .audio) { granted in
                resumeOnce(granted ? .granted : .denied)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + microphoneRequestTimeout) {
                DiagnosticLog.write("MicrophonePermission: requestAccess timed out after \(microphoneRequestTimeout)s")
                resumeOnce(.timedOut)
            }
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    let history: TranscriptionHistory

    private let hotkeyMonitor = HotkeyMonitor()
    private let audioRecorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
    private let textInserter = TextInserter()
    private let soundPlayer = SoundPlayer()
    private let singleInstanceGuard: SingleInstanceGuarding
    private let setupPermissionProvider: SetupPermissionProviding
    lazy var queuedPasteQueue = QueuedPasteQueue { [weak self] text, target in
        guard let self, let pasteController = self.pasteController else {
            return .clipboardFallback
        }
        return await pasteController.pasteQueued(text: text, target: target)
    }
    private lazy var browserMediaController = BrowserMediaController(
        isEnabled: { [weak self] in self?.appState.pauseBrowserMediaWhileRecording == true }
    )
    private var retryingRecordID: UUID?

    private var sparkleUpdater: SparkleUpdater!
    private var recordingController: RecordingController!
    private var transcriptionController: TranscriptionController!
    private var pasteController: PasteController!
    private var transcribingTimer: Timer?
    private var floatingStatusPanel: NSPanel?
    private var floatingStatusSyncTimer: Timer?
    private var transientSuccessAutoHideTimer: Timer?
    private var setupRefreshTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var uiTestingController: UITestingController?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    override convenience init() {
        self.init(singleInstanceGuard: SingleInstanceGuard())
    }

    init(
        singleInstanceGuard: SingleInstanceGuarding,
        setupPermissionProvider: SetupPermissionProviding = SystemSetupPermissionProvider()
    ) {
        self.singleInstanceGuard = singleInstanceGuard
        self.setupPermissionProvider = setupPermissionProvider
        self.appState = AppState()
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("FoilUITests", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.history = TranscriptionHistory(storageDirectory: dir)
        } else {
            self.history = TranscriptionHistory()
        }
        super.init()
    }
    // MARK: - Menu bar label

    @ViewBuilder
    var menuBarLabel: some View {
        switch appState.status {
        case .recording:
            HStack(spacing: 4) {
                Image(systemName: "waveform.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.red, .red)
                Text(appState.formattedRecordingDuration)
                    .monospacedDigit()
            }
        case .transcribing:
            HStack(spacing: 4) {
                Image(systemName: appState.menuBarIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                Text("Sending")
            }
        case .error:
            Image(systemName: appState.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
        case .idle:
            switch appState.transientResult {
            case .pasted:
                Image(systemName: appState.menuBarIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
            case .clipboardFallback:
                Image(systemName: appState.menuBarIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            case nil:
                Image(systemName: appState.menuBarIcon)
            }
        }
    }

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent multiple instances: if another copy is already running, activate it and quit.
        // Skip during UI testing (app is launched by the test harness) and during
        // unit/integration tests (the test runner hosts the app process, so the
        // real app may also be running alongside).
        let isTesting = Self.isTestingProcess()
        if Self.shouldRunSingleInstanceGuard(), singleInstanceGuard.activateExistingInstanceIfRunning() {
            // terminate is deferred to the next run loop tick because calling it
            // during applicationDidFinishLaunching can cause AppKit issues.
            // Safe here: no applicationShouldTerminate override can cancel it.
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }

        DiagnosticLog.write("applicationDidFinishLaunching")
        if isTesting {
            NSApp.setActivationPolicy(.regular)
        }
        _ = SparkleUpdater.shared
        DiagnosticLog.write("applicationDidFinishLaunching: updater ready")
        recordingController = RecordingController(
            audioRecorder: audioRecorder,
            appState: appState,
            playStartCueBeforeRecording: { [weak self] in
                self?.soundPlayer.playStartSound()
            }
        )
        recordingController.delegate = self
        transcriptionController = TranscriptionController(transcriptionService: transcriptionService, appState: appState)
        transcriptionController.delegate = self
        pasteController = PasteController(textInserter: textInserter, appState: appState)
        pasteController.delegate = self
        DiagnosticLog.write("applicationDidFinishLaunching: controllers ready")
        let uiTestingCtrl = UITestingController(
            appState: appState,
            queuedPasteQueue: queuedPasteQueue,
            history: history,
            pasteController: pasteController,
            startTranscribingAnimation: { [weak self] in self?.startTranscribingAnimation() },
            stopTranscribingAnimation: { [weak self] in self?.stopTranscribingAnimation() },
            onRetry: { [weak self] in self?.retryLast() },
            onPasteLast: { [weak self] in self?.pasteLastSuccess() },
            onStartRecording: { [weak self] in self?.startRecordingFromControl() },
            onStopRecording: { [weak self] in self?.stopRecordingFromControl() },
            onCancelRecording: { [weak self] in self?.cancelRecordingFromControl() },
            onCancelTranscription: { [weak self] in self?.cancelTranscriptionFromControl() },
            onHotkeyChanged: { [weak self] in self?.applyHotkeyConfigAndStartIfPossible() },
            onOpenAccessibility: { [weak self] in self?.openAccessibilitySettings() },
            onOpenMicrophone: { [weak self] in self?.openMicrophoneSettings() },
            onRunSetupCheck: { [weak self] in self?.runSetupCheck() },
            onRetryRecord: { [weak self] record in self?.retryRecord(record) },
            onPasteText: { [weak self] text in self?.paste(text: text) },
            onReplaceRecordingController: { [weak self] controller in
                self?.replaceRecordingController(with: controller)
            }
        )
        uiTestingController = uiTestingCtrl
        uiTestingCtrl.configureUITestingIfNeeded()
        uiTestingCtrl.configureAutomationSmokeIfNeeded()
        uiTestingCtrl.configureE2ETranscribeIfNeeded()
        DiagnosticLog.write("applicationDidFinishLaunching: ui testing configured")
        wireHotkeyMonitor()
        applyHotkeyConfig()
        DiagnosticLog.write("applicationDidFinishLaunching: hotkey configured")
        startFloatingStatusSync()
        let shouldDisplayOnboarding = shouldShowOnboarding(isTesting: isTesting)
        if isTesting || shouldDisplayOnboarding {
            DiagnosticLog.write("applicationDidFinishLaunching: setup-first mode, skipping initial hotkey monitor")
            if !ProcessInfo.processInfo.arguments.contains("--seed-transcribing") {
                appState.setStatus(.idle)
            }
        } else {
            DiagnosticLog.write("applicationDidFinishLaunching: starting hotkey monitor")
            startHotkeyMonitorWithRetry()
        }
        refreshSetupHealth()
        DiagnosticLog.write("applicationDidFinishLaunching: setup health refreshed")
        if shouldDisplayOnboarding {
            showOnboarding()
        }
        if UserDefaults.standard.bool(forKey: "notificationsEnabled") {
            Task { await NotificationManager.shared.requestAuthorization() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    func exportDiagnostics() {
        DiagnosticLog.write("diagnosticsExport: save panel opened")
        let panel = NSSavePanel()
        panel.title = "Export Diagnostics"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(AppBrand.name)-Diagnostics-\(Self.diagnosticsFilenameTimestamp()).txt"

        guard panel.runModal() == .OK, let url = panel.url else {
            DiagnosticLog.write("diagnosticsExport: cancelled")
            return
        }

        let text = DiagnosticLog.exportText(appState: appState)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            DiagnosticLog.write("diagnosticsExport: wrote file=\(url.lastPathComponent) bytes=\(text.utf8.count)")
        } catch {
            DiagnosticLog.write("diagnosticsExport: failed error=\(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Diagnostics export failed"
            alert.informativeText = "\(AppBrand.name) could not write the diagnostics file. Choose another location and try again."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    func copySetupReportToClipboard() {
        let text = DiagnosticLog.setupReportText(appState: appState)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appState.feedbackMessage = "Setup report copied"
        DiagnosticLog.write("setupReport: copiedToClipboard bytes=\(text.utf8.count)")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !Self.isTestingProcess(), !Self.isAutomationSmokeProcess() else { return }
        refreshSetupHealth()
        if accessibilityTrusted() {
            retryHotkeyMonitorAfterPermissionChange()
        }
    }

    static func isTestingProcess(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        arguments.contains("--ui-testing")
            || environment["XCTestConfigurationFilePath"] != nil
            || arguments.contains { $0.localizedCaseInsensitiveContains(".xctest") }
    }

    static func isAutomationSmokeProcess(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("--automation-smoke")
    }

    static func shouldRunSingleInstanceGuard(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        !isTestingProcess(arguments: arguments, environment: environment)
            && !isAutomationSmokeProcess(arguments: arguments)
    }

    private static func diagnosticsFilenameTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func shouldShowOnboarding(isTesting: Bool) -> Bool {
        if isTesting {
            return ProcessInfo.processInfo.arguments.contains("--show-onboarding")
        }
        if Self.isAutomationSmokeProcess() {
            return false
        }
        return !hasCompletedOnboarding
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView(
            appState: appState,
            onOpenAccessibility: { [weak self] in self?.openAccessibilitySettings() },
            onOpenMicrophone: { [weak self] in self?.openMicrophoneSettings() },
            onCheckMicrophone: { [weak self] in self?.checkMicrophonePermission() },
            onRefreshSetupHealth: { [weak self] in self?.refreshSetupHealth() },
            onOpenSettings: { [weak self] in self?.showSettingsWindow(initialTab: .transcription) },
            onComplete: { [weak self] in
                guard let self else { return }
                self.hasCompletedOnboarding = true
                if !Self.isTestingProcess(), !self.hotkeyMonitor.isRunning {
                    self.startHotkeyMonitorWithRetry()
                }
                let window = self.onboardingWindow
                self.onboardingWindow = nil
                DispatchQueue.main.async {
                    window?.orderOut(nil)
                    window?.close()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to \(AppBrand.name)"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    func showSettingsWindow(initialTab: SettingsView.Tab = .general) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            appState: appState,
            history: history,
            initialTab: initialTab,
            onHotkeyChanged: { [weak self] in self?.applyHotkeyConfig() },
            onCopySetupReport: { [weak self] in self?.copySetupReportToClipboard() },
            onExportDiagnostics: { [weak self] in self?.exportDiagnostics() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Floating status

    private final class FloatingStatusPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private func startFloatingStatusSync() {
        floatingStatusSyncTimer?.invalidate()
        floatingStatusSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncFloatingStatus()
            }
        }
        syncFloatingStatus()
    }

    private func syncFloatingStatus() {
        guard appState.shouldShowFloatingStatus else {
            floatingStatusPanel?.orderOut(nil)
            return
        }

        let panel = floatingStatusPanel ?? makeFloatingStatusPanel()
        if floatingStatusPanel == nil {
            floatingStatusPanel = panel
        }
        positionFloatingStatusPanel(panel)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func makeFloatingStatusPanel() -> NSPanel {
        let size = NSSize(width: 340, height: 96)
        let panel = FloatingStatusPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "\(AppBrand.name) Floating Status"
        panel.setAccessibilityIdentifier("floatingStatus.window")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(
            rootView: FloatingStatusView(
                appState: appState,
                onDismiss: { [weak self] in
                    self?.appState.hideFloatingStatus()
                    self?.syncFloatingStatus()
                }
            )
        )
        return panel
    }

    private func positionFloatingStatusPanel(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else { return }
        let margin: CGFloat = 18
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - margin,
            y: visibleFrame.maxY - size.height - margin
        )
        panel.setFrameOrigin(origin)
    }

    private func recordPaste(_ delivery: PasteDelivery) {
        appState.recordPaste(delivery)
        if delivery != .clipboardFallback {
            scheduleTransientSuccessAutoHide()
        }
    }

    private func scheduleTransientSuccessAutoHide() {
        transientSuccessAutoHideTimer?.invalidate()
        transientSuccessAutoHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.appState.expireTransientSuccess()
                self?.syncFloatingStatus()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        floatingStatusSyncTimer?.invalidate()
        transientSuccessAutoHideTimer?.invalidate()
        recordingController?.invalidateTimers()
    }

    // MARK: - Hotkey configuration

    func applyHotkeyConfig() {
        let deliveryShortcutEnabled = appState.queuedPasteEnabled
            && !appState.queuedPasteDeliveryShortcutConflictsWithRecordingHotkey
        hotkeyMonitor.configureQueuedPasteDeliveryShortcut(
            AppState.queuedPasteDeliveryShortcut,
            enabled: deliveryShortcutEnabled
        )
        if appState.queuedPasteDeliveryShortcutConflictsWithRecordingHotkey {
            DiagnosticLog.write("QueuedPaste.hotkey: disabled conflict shortcut=\(appState.queuedPasteDeliveryShortcutLabel)")
        }
        hotkeyMonitor.configure(
            hotkeyChoice: appState.hotkeyChoice,
            recordingMode: appState.recordingMode
        )
        if appState.hotkeyChoice == .custom {
            hotkeyMonitor.configureCustomKey(
                keyCode: appState.customHotkeyKeyCode,
                modifiers: appState.customHotkeyModifiers
            )
        }
    }

    private func applyHotkeyConfigAndStartIfPossible() {
        applyHotkeyConfig()
        retryHotkeyMonitorAfterPermissionChange()
    }

    // MARK: - Transcribing animation

    private func startTranscribingAnimation() {
        appState.transcribingIconFrame = 0
        transcribingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.appState.transcribingIconFrame = (self.appState.transcribingIconFrame + 1) % 2
            }
        }
    }

    private func stopTranscribingAnimation() {
        transcribingTimer?.invalidate()
        transcribingTimer = nil
        appState.transcribingIconFrame = 0
    }

    // MARK: - Retry

    func retryLast() {
        guard let record = history.retryableRecord else { return }
        retryRecord(record)
    }

    func pasteLastSuccess() {
        guard let text = history.records.first(where: { !$0.isFailure })?.text else { return }
        paste(text: text)
    }

    func paste(text: String) {
        Task {
            await pasteController.pasteDirectly(text: text)
        }
    }

    func startRecordingFromControl() {
        captureTargetThenStartRecording()
    }

    func stopRecordingFromControl() {
        recordingController.stopRecording()
    }

    func cancelRecordingFromControl() {
        recordingController.cancelRecording()
    }

    func cancelTranscriptionFromControl() {
        guard appState.status == .transcribing else { return }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        retryingRecordID = nil
        stopTranscribingAnimation()
        pasteController.clearPendingTarget()
        appState.setStatus(.idle)
        appState.feedbackMessage = "Transcription cancelled"
        appState.floatingStatusTransientVisible = true
        DiagnosticLog.write("transcription: cancelled by user")
    }

    func replaceRecordingController(with newController: RecordingController) {
        recordingController.invalidateTimers()
        recordingController = newController
        recordingController.delegate = self
    }

    // MARK: - Wiring

    private func wireHotkeyMonitor() {
        hotkeyMonitor.onRecordingStarted = { [weak self] in
            self?.captureTargetThenStartRecording()
        }
        hotkeyMonitor.onRecordingStopped = { [weak self] in
            self?.recordingController.stopRecording()
        }
        hotkeyMonitor.onRecordingCancelled = { [weak self] in
            self?.recordingController.cancelRecording()
        }
        hotkeyMonitor.onQueuedPasteDeliveryRequested = { [weak self] in
            self?.deliverQueuedPasteFromHotkey()
        }
    }

    func deliverQueuedPasteFromHotkey() {
        Task { @MainActor in
            let controller = QueuedPasteDeliveryController(
                appState: appState,
                queue: queuedPasteQueue,
                shortcut: AppState.queuedPasteDeliveryShortcut
            )
            await controller.deliverFromHotkey()
        }
    }

    private func captureTargetThenStartRecording() {
        pasteController.captureTarget()
        let capturedTarget = pasteController.pendingTarget
        DiagnosticLog.write("captureTargetThenStartRecording: asyncEnabled=\(appState.asyncPasteEnabled) capturedTarget=\(String(describing: capturedTarget))")
        appState.recordTargetCapture(capturedTarget)
        appState.clearError()
        recordingController.startRecording()
    }

    // MARK: - Transcription flow (now delegated to TranscriptionController)

    private func startHotkeyMonitorWithRetry() {
        let initialAccessibilityTrusted = accessibilityTrusted()
        DiagnosticLog.write("AccessibilityTrust: launch initial=\(initialAccessibilityTrusted)")
        appState.updateAccessibilityState(isTrusted: initialAccessibilityTrusted)
        if hotkeyMonitor.start() {
            DiagnosticLog.write("HotkeyMonitor: start succeeded")
            appState.updateAccessibilityState(isTrusted: true)
            appState.setStatus(.idle)
            return
        }

        let postFailureAccessibilityTrusted = accessibilityTrusted()
        DiagnosticLog.write("AccessibilityTrust: after event tap failure=\(postFailureAccessibilityTrusted)")
        guard !postFailureAccessibilityTrusted else {
            DiagnosticLog.write("HotkeyMonitor: start failed despite Accessibility trust; retrying")
            appState.updateAccessibilityState(isTrusted: true)
            Task { @MainActor in
                for attempt in 1...5 {
                    do {
                        try await Task.sleep(for: .milliseconds(400))
                    } catch {
                        return
                    }
                    if hotkeyMonitor.start() {
                        DiagnosticLog.write("HotkeyMonitor: trusted retry succeeded attempt=\(attempt)")
                        appState.updateAccessibilityState(isTrusted: true)
                        appState.setStatus(.idle)
                        return
                    }
                }
                DiagnosticLog.write("HotkeyMonitor: trusted retry exhausted")
                appState.updateAccessibilityState(isTrusted: true)
                appState.showError("Failed to start hotkey monitor -- restart \(AppBrand.name)")
            }
            return
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let promptedAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        DiagnosticLog.write("AccessibilityTrust: prompt requested result=\(promptedAccessibilityTrusted)")
        appState.updateAccessibilityState(isTrusted: false)
        appState.setStatus(.error("Enable Accessibility in Settings"))

        Task {
            while !accessibilityTrusted() {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
            DiagnosticLog.write("AccessibilityTrust: polling observed trusted=true")
            if hotkeyMonitor.start() {
                appState.updateAccessibilityState(isTrusted: true)
                appState.setStatus(.idle)
            } else {
                appState.updateAccessibilityState(isTrusted: false, message: "Restart \(AppBrand.name)")
                appState.showError("Failed to start -- try restarting \(AppBrand.name)")
            }
        }
    }

    func refreshSetupHealth() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let isAutomationSmoke = Self.isAutomationSmokeProcess()
        defer {
            if isUITesting {
                uiTestingController?.writeStateSnapshot()
            }
        }
        if isUITesting {
            if ProcessInfo.processInfo.arguments.contains("--seed-setup-unknown") {
                appState.accessibilityState = .unknown
                appState.microphoneState = .unknown
                appState.apiKeyState = .unknown
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--seed-setup-failures") {
                appState.updateAccessibilityState(isTrusted: false)
                appState.updateMicrophoneState(isReady: false)
                appState.apiKeyState = .needsAction("Add Groq API key")
                appState.failSetupCheck("Enable Accessibility")
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--seed-microphone-unknown") {
                appState.updateAccessibilityState(isTrusted: true)
                appState.microphoneState = .unknown
                appState.apiKeyState = .ready
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--seed-microphone-denied") {
                appState.updateAccessibilityState(isTrusted: true)
                appState.updateMicrophoneState(isReady: false, message: "Allow microphone access")
                appState.apiKeyState = .ready
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--seed-permissions-ready-api-missing") {
                appState.updateAccessibilityState(isTrusted: true)
                appState.updateMicrophoneState(isReady: true)
                appState.apiKeyState = .needsAction("Add Groq API key")
                return
            }
            appState.updateAccessibilityState(isTrusted: true)
            appState.updateMicrophoneState(isReady: true)
            appState.apiKeyState = .ready
            return
        }
        let trusted = accessibilityTrusted()
        DiagnosticLog.write("SetupHealth: accessibilityTrusted=\(trusted)")
        let microphoneStatus = setupPermissionProvider.microphoneAuthorizationStatus
        appState.applySetupHealth(accessibilityTrusted: trusted, microphoneAuthorizationStatus: microphoneStatus)
        switch microphoneStatus {
        case .authorized:
            DiagnosticLog.write("SetupHealth: microphone=authorized")
        case .denied, .restricted:
            DiagnosticLog.write("SetupHealth: microphone=denied")
        case .notDetermined:
            DiagnosticLog.write("SetupHealth: microphone=notDetermined")
        @unknown default:
            DiagnosticLog.write("SetupHealth: microphone=unknown")
        }
        DiagnosticLog.write("SetupHealth: refreshing API key state")
        if isAutomationSmoke {
            appState.apiKeyState = .ready
            DiagnosticLog.write("SetupHealth: automation smoke skipping API key keychain refresh")
            DiagnosticLog.write("SetupHealth: API key state refreshed")
            return
        }
        appState.refreshApiKeyState()
        DiagnosticLog.write("SetupHealth: API key state refreshed")
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
        startSetupRefreshPolling()
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
        startSetupRefreshPolling()
    }

    private func startSetupRefreshPolling() {
        guard !Self.isTestingProcess() else { return }
        setupRefreshTask?.cancel()
        setupRefreshTask = Task { @MainActor in
            for _ in 0..<60 {
                if Task.isCancelled { return }
                refreshSetupHealth()
                if accessibilityTrusted() {
                    retryHotkeyMonitorAfterPermissionChange()
                }
                if appState.areSystemPermissionsReady {
                    return
                }
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func retryHotkeyMonitorAfterPermissionChange() {
        guard !hotkeyMonitor.isRunning else { return }
        guard appState.status == .idle || appState.isError else { return }
        if hotkeyMonitor.start() {
            DiagnosticLog.write("HotkeyMonitor: permission refresh start succeeded")
            appState.updateAccessibilityState(isTrusted: true)
            appState.clearError()
        }
    }

    func checkMicrophonePermission() {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            appState.updateMicrophoneState(isReady: true)
            DiagnosticLog.write("MicrophonePermission: ui-testing ready=true")
            return
        }

        Task { @MainActor in
            let result = await requestMicrophoneAccessIfNeeded()
            refreshSetupHealth()
            appState.updateMicrophoneState(
                isReady: result.isReady,
                message: microphoneRecoveryMessage(for: result)
            )
            DiagnosticLog.write("MicrophonePermission: checked ready=\(result.isReady)")
        }
    }

    func runSetupCheck() {
        guard !appState.isSetupCheckRunning else { return }
        guard appState.status == .idle || appState.isError else {
            appState.failSetupCheck("Wait until recording finishes")
            return
        }

        appState.startSetupCheck()

        Task { @MainActor in
            refreshSetupHealth()

            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                appState.completeSetupCheck()
                return
            }

            appState.refreshApiKeyState()
            if appState.selectedTranscriptionProvider.requiresAPIKey && !appState.hasApiKey {
                appState.refreshApiKeyState()
                appState.failSetupCheck("Add \(appState.selectedTranscriptionProvider.displayName) API key")
                return
            }
            let apiKey = KeychainHelper.readApiKey(for: appState.selectedTranscriptionProviderID)
            var setupSuccessDetail = "Ready to record"

            do {
                if appState.selectedTranscriptionProviderPresetID == .customOpenAICompatible,
                   appState.customTranscriptionBaseURLValue == nil {
                    appState.failSetupCheck("Invalid OpenAI-compatible base URL")
                    return
                }
                let requiredModels = requiredModelsForSetupCheck()
                let validation = try await transcriptionService.withProvider(appState.selectedTranscriptionProvider).validateProviderConfiguration(
                    apiKey: apiKey,
                    requiredModels: requiredModels
                )
                if validation == .reachableWithoutModelValidation {
                    DiagnosticLog.write("setupCheck: provider reachable but model validation skipped")
                    setupSuccessDetail = "Server reachable; model availability was not checked"
                }
                appState.apiKeyState = .ready
            } catch TranscriptionService.TranscriptionError.invalidApiKey {
                appState.apiKeyState = .needsAction("Invalid \(appState.selectedTranscriptionProvider.displayName) API key")
                appState.failSetupCheck("Invalid \(appState.selectedTranscriptionProvider.displayName) API key")
                return
            } catch TranscriptionService.TranscriptionError.invalidProviderURL {
                appState.failSetupCheck("Invalid OpenAI-compatible base URL")
                return
            } catch {
                let message = setupCheckErrorMessage(from: error)
                appState.failSetupCheck(message)
                return
            }

            guard accessibilityTrusted() else {
                appState.updateAccessibilityState(isTrusted: false)
                appState.failSetupCheck("Enable Accessibility")
                return
            }
            appState.updateAccessibilityState(isTrusted: true)

            let microphoneResult = await requestMicrophoneAccessIfNeeded()
            guard microphoneResult.isReady else {
                let recoveryMessage = microphoneRecoveryMessage(for: microphoneResult)
                appState.updateMicrophoneState(isReady: false, message: recoveryMessage)
                appState.failSetupCheck(recoveryMessage)
                return
            }
            appState.updateMicrophoneState(isReady: true)

            do {
                try audioRecorder.startRecording()
                try await Task.sleep(for: .milliseconds(250))
                let testRecordingURL = try await audioRecorder.stopRecordingAsync(format: .wav)
                if let testRecordingURL {
                    try? FileManager.default.removeItem(at: testRecordingURL)
                }
                appState.completeSetupCheck(detail: setupSuccessDetail)
            } catch is CancellationError {
                audioRecorder.cancelRecording()
                appState.failSetupCheck("Setup check cancelled")
            } catch {
                audioRecorder.cancelRecording()
                DiagnosticLog.write("setupCheck: microphone engine failed error=\(error.localizedDescription)")
                appState.failSetupCheck("Microphone unavailable")
            }
        }
    }

    func validateSelectedProviderApiKey(_ key: String) async throws {
        _ = try await transcriptionService
            .withProvider(appState.selectedTranscriptionProvider)
            .validateProviderConfiguration(
                apiKey: key,
                requiredModels: requiredModelsForSetupCheck()
            )
    }

    private func requiredModelsForSetupCheck() -> [String] {
        var models = [appState.selectedTranscriptionModel]
        if appState.effectiveTranscriptProcessingMode != .raw {
            models.append(appState.transcriptCleanupModel)
        }
        return Array(Set(models))
    }

    private func setupCheckErrorMessage(from error: Error) -> String {
        if appState.selectedTranscriptionProvider.id == .openAICompatible {
            if error is URLError {
                return "Could not reach OpenAI-compatible transcription server"
            }
            if let transcriptionError = error as? TranscriptionService.TranscriptionError,
               transcriptionError == .invalidResponse {
                return "OpenAI-compatible transcription server returned an invalid response"
            }
        }
        return transcriptionController.errorMessage(from: error)
    }

    private func accessibilityTrusted() -> Bool {
        setupPermissionProvider.accessibilityTrusted
    }

    private func requestMicrophoneAccessIfNeeded() async -> MicrophoneAccessRequestResult {
        let status = setupPermissionProvider.microphoneAuthorizationStatus
        DiagnosticLog.write("MicrophonePermission: authorizationStatus=\(status.rawValue)")
        switch status {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            let result = await setupPermissionProvider.requestMicrophoneAccess()
            switch result {
            case .granted:
                DiagnosticLog.write("MicrophonePermission: requestAccess granted=true")
            case .denied:
                DiagnosticLog.write("MicrophonePermission: requestAccess granted=false")
            case .timedOut:
                DiagnosticLog.write("MicrophonePermission: requestAccess timedOut=true")
            }
            return result
        @unknown default:
            return .denied
        }
    }

    private func microphoneRecoveryMessage(for result: MicrophoneAccessRequestResult) -> String {
        switch result {
        case .granted:
            return "Microphone access granted"
        case .denied:
            return "Allow microphone access"
        case .timedOut:
            return "Microphone prompt did not finish; reopen Foil or reset Microphone privacy"
        }
    }

    func retryRecord(_ record: TranscriptionRecord) {
        guard appState.status == .idle || appState.isError else { return }
        guard let audioURL = record.audioFileURL else {
            appState.showError("Recording no longer available for retry")
            return
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            appState.showError("Recording file was deleted -- cannot retry")
            return
        }

        appState.clearError()
        appState.transcriptionStage = .transcribingAudio
        appState.setStatus(.transcribing)
        appState.feedbackMessage = "Retrying transcription..."
        startTranscribingAnimation()

        // Tag the record ID so TranscriptionControllerDelegate callbacks know this is a retry
        retryingRecordID = record.id
        transcriptionTask = Task { @MainActor in
            await transcriptionController.retryTranscription(record: record)
        }
    }
}

// MARK: - TranscriptionControllerDelegate

extension AppDelegate: TranscriptionControllerDelegate {
    func transcriptionController(
        _ controller: TranscriptionController,
        didStartTranscribing audioURL: URL
    ) {
        DiagnosticLog.write("AppDelegate: transcriptionController didStartTranscribing=\(audioURL.lastPathComponent)")
        // Only set transcribing state if we're not already in it (retry path sets it earlier)
        if appState.status != .transcribing {
            soundPlayer.playStopSound()
            appState.transcriptionStage = .transcribingAudio
            appState.setStatus(.transcribing)
            startTranscribingAnimation()
        }

        if UserDefaults.standard.bool(forKey: "notificationsEnabled") {
            NotificationManager.shared.postTranscriptionStarted()
        }

        let useMockTranscription: Bool
        #if DEBUG
        useMockTranscription = appState.mockTranscriptionEnabled
        #else
        useMockTranscription = false
        #endif
        if useMockTranscription {
            appState.feedbackMessage = "Mock transcription..."
        }
    }

    func transcriptionController(
        _ controller: TranscriptionController,
        didTranscribe text: String,
        audioURL: URL,
        cleanupFailed: Bool
    ) {
        DiagnosticLog.write("AppDelegate: transcriptionController didTranscribe textLength=\(text.count) cleanupFailed=\(cleanupFailed)")
        transcriptionTask = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--e2e-transcribe") {
            try? text.write(toFile: "/tmp/foil-e2e-result.txt", atomically: true, encoding: .utf8)
        }
        #endif
        stopTranscribingAnimation()
        appState.feedbackMessage = "Transcription ready"

        if let retryID = retryingRecordID {
            // Retry path: resolve the existing history record
            history.resolveRetry(id: retryID, text: text)
            retryingRecordID = nil
            appState.transcriptionStage = .pasting
            Task {
                await pasteController.pasteDirectly(text: text)
                if cleanupFailed {
                    appState.feedbackMessage = "Cleanup failed; raw transcript used"
                }
                if UserDefaults.standard.bool(forKey: "notificationsEnabled") {
                    NotificationManager.shared.postTranscriptionComplete(preview: text)
                }
                appState.setStatus(.idle)
            }
        } else {
            // Normal flow: add new success record, handle paste routing
            history.addSuccess(text: text)

            DiagnosticLog.write("paste decision: delegating to pasteController asyncOn=\(appState.asyncPasteEnabled) queuedOn=\(appState.queuedPasteEnabled) pendingTarget=\(String(describing: pasteController.pendingTarget))")
            appState.transcriptionStage = .pasting

            Task {
                if appState.queuedPasteEnabled {
                    let context = pasteController.consumePendingContext()
                    queuedPasteQueue.enqueue(
                        text: text,
                        target: context.target,
                        recordingStartTime: context.recordingStartTime ?? Date()
                    )
                    appState.feedbackMessage = "Transcript queued"
                    appState.floatingStatusTransientVisible = true
                } else {
                    await pasteController.paste(text: text)
                }
                if cleanupFailed {
                    appState.feedbackMessage = "Cleanup failed; raw transcript used"
                }
                if UserDefaults.standard.bool(forKey: "notificationsEnabled") {
                    NotificationManager.shared.postTranscriptionComplete(preview: text)
                }
                appState.setStatus(.idle)
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
    }

    func transcriptionController(
        _ controller: TranscriptionController,
        didFail error: Error,
        errorMessage: String,
        audioURL: URL,
        format: AudioFormat
    ) {
        DiagnosticLog.write("AppDelegate: transcriptionController didFail errorMessage=\(errorMessage)")
        transcriptionTask = nil
        stopTranscribingAnimation()

        if let retryID = retryingRecordID {
            // Retry path: update the existing history record
            history.resolveRetryFailure(id: retryID, error: errorMessage)
            retryingRecordID = nil
        } else if error is NoApiKeyError {
            // No API key: clear pending state, don't preserve audio
            pasteController.clearPendingTarget()
            appState.refreshApiKeyState()
            try? FileManager.default.removeItem(at: audioURL)
            history.addFailure(error: "No API key", audioFileURL: nil)
        } else {
            // Normal failure: preserve audio for retry
            pasteController.clearPendingTarget()
            history.addFailure(error: errorMessage, audioFileURL: audioURL)
            // Do NOT delete audio file -- preserved for retry
        }

        appState.showError(errorMessage)
        if UserDefaults.standard.bool(forKey: "notificationsEnabled") {
            NotificationManager.shared.postTranscriptionFailed(errorMessage: errorMessage)
        }
    }
}

// MARK: - RecordingControllerDelegate

extension AppDelegate: RecordingControllerDelegate {
    func recordingControllerDidStart(_ controller: RecordingController) {
        DiagnosticLog.write("AppDelegate: recordingControllerDidStart")
        appState.updateMicrophoneState(isReady: true)
        postBuiltInMicBluetoothGuidanceIfNeeded()
        if let browserMediaSessionID = browserMediaController.recordingDidStart() {
            Task {
                await browserMediaController.pausePlayingMedia(for: browserMediaSessionID)
            }
        }
    }

    func recordingController(
        _ controller: RecordingController,
        didStopWithURL audioURL: URL,
        format: AudioFormat
    ) {
        DiagnosticLog.write("AppDelegate: recordingController didStopWithURL=\(audioURL.lastPathComponent)")
        browserMediaController.recordingDidEnd(reason: .stopped)
        transcriptionTask = Task { @MainActor in
            await transcriptionController.transcribe(audioURL: audioURL, format: format)
        }
    }

    func recordingControllerDidStopWithNoAudio(_ controller: RecordingController) {
        DiagnosticLog.write("AppDelegate: recordingControllerDidStopWithNoAudio")
        browserMediaController.recordingDidEnd(reason: .noAudio)
        stopTranscribingAnimation()
        appState.setStatus(.idle)
    }

    func recordingControllerDidCancel(_ controller: RecordingController) {
        DiagnosticLog.write("AppDelegate: recordingControllerDidCancel")
        browserMediaController.recordingDidEnd(reason: .cancelled)
        appState.setStatus(.idle)
        appState.feedbackMessage = "Recording cancelled"
        pasteController.clearPendingTarget()
    }

    func recordingController(_ controller: RecordingController, didFailWithError error: Error) {
        DiagnosticLog.write("AppDelegate: recordingController didFailWithError=\(error)")
        browserMediaController.recordingDidEnd(reason: .failed)
        pasteController.clearPendingTarget()
        appState.updateMicrophoneState(isReady: false, message: "Allow microphone access")
        appState.showError("Microphone unavailable")
    }

    private func postBuiltInMicBluetoothGuidanceIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else {
            return
        }
        let availableInputDevices = AudioRecorder.availableInputDevices()
        let selectedInputDevice = appState.selectedInputDeviceUID.flatMap { uid in
            availableInputDevices.first { $0.uid == uid }
        } ?? AudioRecorder.effectiveInputDevice(forUID: nil)
        let hasShownNotice = UserDefaults.standard.bool(forKey: BluetoothMicGuidance.shownDefaultsKey)
        guard BluetoothMicGuidance.shouldShowNotice(
            selectedInputDevice: selectedInputDevice,
            availableInputDevices: availableInputDevices,
            hasShownNotice: hasShownNotice
        ) else {
            return
        }

        UserDefaults.standard.set(true, forKey: BluetoothMicGuidance.shownDefaultsKey)
        DiagnosticLog.write("BluetoothMicGuidance: posting built-in mic Bluetooth guidance")
        NotificationManager.shared.postBuiltInMicBluetoothGuidance()
    }
}

// MARK: - PasteControllerDelegate

extension AppDelegate: PasteControllerDelegate {
    func pasteController(_ controller: PasteController, didPaste text: String, delivery: PasteDelivery) {
        recordPaste(delivery)
    }
}

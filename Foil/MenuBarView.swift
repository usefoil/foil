import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Bindable var queuedPasteQueue: QueuedPasteQueue
    var history: TranscriptionHistory
    var onRetry: (() -> Void)?
    var onRetryRecord: ((TranscriptionRecord) -> Void)?
    var onPasteLast: (() -> Void)?
    var onPasteText: ((String) -> Void)?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onCancelTranscription: (() -> Void)?
    var onHotkeyChanged: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onOpenMicrophone: (() -> Void)?
    var onCheckMicrophone: (() -> Void)?
    var onRunSetupCheck: (() -> Void)?
    var onCopySetupReport: (() -> Void)?
    var onSimulateSuccess: (() -> Void)?
    var onSimulateFailure: (() -> Void)?

    @Environment(\.openWindow) private var openWindow

    private var lastSuccess: TranscriptionRecord? {
        history.records.first { !$0.isFailure }
    }

    private var recentSuccesses: [TranscriptionRecord] {
        history.recentSuccessfulRecords(limit: 3)
    }

    private var session: AppState.SessionPresentation {
        appState.sessionPresentation(
            hotkeyLabel: hotkeyLabel,
            hasRetryableFailure: history.retryableRecord != nil,
            hasLastSuccess: lastSuccess?.text != nil
        )
    }

    private var apiKeyRecoveryDetail: String {
        appState.selectedTranscriptionProvider.requiresAPIKey
            ? "Add your \(appState.selectedTranscriptionProvider.displayName) API key to enable transcription."
            : "API key optional for this provider."
    }

    private var microphoneActionTitle: String? {
        switch appState.microphoneState {
        case .ready:
            nil
        case .unknown:
            "Check"
        case .needsAction:
            "Open Settings"
        }
    }

    private var microphoneAction: (() -> Void)? {
        switch appState.microphoneState {
        case .ready:
            nil
        case .unknown:
            onCheckMicrophone
        case .needsAction:
            onOpenMicrophone
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbarActions
            sessionStrip
            if appState.needsSetupAttention {
                setupPanel
            }
            if shouldShowFeedbackPanel {
                feedbackPanel
            }
            if shouldShowQueuedPasteSection {
                queuedPasteSection
            }
            recordingControlsSection
            recentTranscriptionsSection
            Divider()
                .opacity(0.55)
            AppVersionFooter(accessibilityIdentifier: "menu.appVersionFooter")
        }
        .accessibilityIdentifier("menu.controlCenter")
        .padding(14)
        .frame(width: 360)
        .onAppear {
            if !isUITesting {
                appState.refreshApiKeyState()
            }
        }
    }

    private var toolbarActions: some View {
        HStack(spacing: 8) {
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .labelStyle(.titleAndIcon)
            .accessibilityIdentifier("menu.settingsButton")
            .help("Open Settings")

            Button {
                openHistory()
            } label: {
                Label("History", systemImage: "clock")
            }
            .labelStyle(.titleAndIcon)
            .accessibilityLabel("History")
            .accessibilityIdentifier("menu.historyButton")
            .help("Open History")

            Button {
                openTroubleshooting()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel("Help")
            .accessibilityIdentifier("menu.helpButton")
            .help("Open troubleshooting")

            Button {
                copySetupReport()
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .accessibilityLabel("Copy Setup Report")
            .accessibilityIdentifier("menu.copySetupReportButton")
            .help("Copy Setup Report")

            Spacer()

            if history.retryableRecord != nil {
                Button {
                    onRetry?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Retry Last Failure")
                .help("Retry Last Failure")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .accessibilityLabel("Quit \(AppBrand.name)")
            .help("Quit \(AppBrand.name)")
        }
        .buttonStyle(.borderless)
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Setup")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(
                    appState.needsSetupAttention ? "Needs attention" : "Ready",
                    systemImage: appState.needsSetupAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(appState.needsSetupAttention ? .orange : .green)
                .accessibilityIdentifier("menu.setup.summary")
            }

            permissionRow(
                title: "Accessibility",
                state: appState.accessibilityState,
                actionTitle: "Open Settings",
                recoveryDetail: accessibilityRecoveryDetail,
                action: onOpenAccessibility
            )
            permissionRow(
                title: "Microphone",
                state: appState.microphoneState,
                actionTitle: microphoneActionTitle,
                recoveryDetail: microphoneRecoveryDetail,
                action: microphoneAction
            )
            permissionRow(
                title: "\(appState.selectedTranscriptionProvider.displayName) API key",
                state: appState.apiKeyState,
                actionTitle: "Add Key",
                recoveryDetail: apiKeyRecoveryDetail,
                action: { openWindow(id: "api-key-setup") }
            )

            Divider()
                .opacity(0.5)

            setupCheckRow
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("menu.setup.panel")
    }

    private var setupCheckRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Label(setupCheckTitle, systemImage: setupCheckIcon)
                    .foregroundStyle(setupCheckColor)
                    .accessibilityIdentifier("menu.setup.test.label")
                Spacer()
                Text(setupCheckDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("menu.setup.test.state")
                Button(setupCheckButtonTitle) {
                    onRunSetupCheck?()
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 48, minHeight: 18)
                .disabled(appState.isSetupCheckRunning)
                .accessibilityIdentifier("menu.setup.test.action")
            }
            .font(.caption)

            if let recoveryDetail = setupCheckRecoveryDetail {
                Text(recoveryDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("menu.setup.test.recovery")
            }
        }
    }

    private func permissionRow(
        title: String,
        state: AppState.PermissionState,
        actionTitle: String?,
        recoveryDetail: String,
        action: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Label(title, systemImage: permissionIcon(for: state))
                    .foregroundStyle(permissionColor(for: state))
                    .accessibilityIdentifier("menu.setup.\(title).label")
                Spacer()
                Text(permissionText(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("menu.setup.\(title).state")
                if let actionTitle, let action {
                    Button(actionTitle) {
                        action()
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 48, minHeight: 18)
                    .accessibilityIdentifier("menu.setup.\(title).action")
                }
            }
            .font(.caption)

            if permissionNeedsRecovery(state) {
                Text(recoveryDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("menu.setup.\(title).recovery")
            }
        }
    }

    private var sessionStrip: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(sessionColor.opacity(0.14))
                Image(systemName: session.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(sessionColor)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(2)
                        .accessibilityIdentifier("menu.status.title")
                    if let timerText = session.timerText {
                        Text(timerText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("menu.status.timer")
                    }
                }
                Text(session.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("menu.status.detail")
                if appState.isApproachingTimeLimit {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(appState.formattedRemainingTime) remaining")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .accessibilityIdentifier("menu.status.timeLimitWarning")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let action = session.primaryAction {
                Button(action.title) {
                    performSessionAction(action)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("menu.status.action")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(sessionColor.opacity(0.18), lineWidth: 1)
        }
        .accessibilityIdentifier("menu.sessionStrip")
    }

    private var feedbackPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let target = appState.capturedTargetName {
                Label("Target: \(target)", systemImage: "scope")
                    .accessibilityIdentifier("menu.feedback.target")
            } else if appState.asyncPasteEnabled {
                Label("Target will be captured when recording starts", systemImage: "scope")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("menu.feedback.targetHelp")
            }

            if let message = appState.feedbackMessage {
                Label(message, systemImage: feedbackIcon)
                    .accessibilityIdentifier("menu.feedback.message")
            }

            if let clipboard = appState.clipboardFeedback {
                Label(clipboard, systemImage: "clipboard")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("menu.feedback.clipboard")
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var shouldShowFeedbackPanel: Bool {
        appState.capturedTargetName != nil
            || appState.feedbackMessage != nil
            || appState.clipboardFeedback != nil
            || (appState.asyncPasteEnabled && appState.status == .recording)
            || (appState.queuedPasteEnabled && appState.status == .recording)
    }

    private var shouldShowQueuedPasteSection: Bool {
        appState.queuedPasteEnabled || queuedPasteQueue.hasItems
    }

    private var queuedPasteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Paste Queue", systemImage: "tray.full")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(queueCountSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("menu.queuedPaste.count")
            }

            if queuedPasteQueue.hasItems {
                HStack(spacing: 8) {
                    Button {
                        Task { await queuedPasteQueue.deliverNext() }
                    } label: {
                        Label("Paste Next", systemImage: "arrow.down.doc")
                    }
                    .disabled(queuedPasteQueue.pendingCount == 0)
                    .accessibilityIdentifier("menu.queuedPaste.pasteNextButton")

                    Button {
                        Task { await queuedPasteQueue.drain() }
                    } label: {
                        Label("Drain", systemImage: "forward.end")
                    }
                    .disabled(queuedPasteQueue.pendingCount == 0)
                    .accessibilityIdentifier("menu.queuedPaste.drainButton")
                }
                .buttonStyle(.borderless)

                ForEach(queuedPasteQueue.items.prefix(4)) { item in
                    queuedPasteRow(item)
                }
            } else {
                Text(appState.queuedPasteEnabled ? "Queued transcripts will appear here." : "Queued paste is off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("menu.queuedPaste.empty")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("menu.queuedPaste.section")
    }

    private var queueCountSummary: String {
        if queuedPasteQueue.pendingCount == 0 && queuedPasteQueue.blockedCount == 0 {
            return "0 queued"
        }
        if queuedPasteQueue.blockedCount == 0 {
            return "\(queuedPasteQueue.pendingCount) queued"
        }
        return "\(queuedPasteQueue.pendingCount) queued, \(queuedPasteQueue.blockedCount) need attention"
    }

    private func queuedPasteRow(_ item: QueuedPasteItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.targetName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(item.status.displayName)
                    .font(.caption2)
                    .foregroundStyle(statusColor(for: item.status))
            }

            Text(item.previewText)
                .font(.caption)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let failureReason = item.failureReason {
                Text(failureReason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button {
                    copy(item.text)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("menu.queuedPaste.copyButton")

                Button {
                    Task { await queuedPasteQueue.retry(id: item.id) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .disabled(!item.canDeliver)
                .accessibilityIdentifier("menu.queuedPaste.retryButton")

                Button {
                    queuedPasteQueue.remove(id: item.id)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .accessibilityIdentifier("menu.queuedPaste.removeButton")
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
        }
        .padding(8)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("menu.queuedPaste.item")
    }

    private var recentTranscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Transcriptions")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    openHistory()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("menu.lastResult.openHistoryButton")
                .buttonStyle(.borderless)
                .help("Open History")
            }

            if recentSuccesses.isEmpty {
                Text("No successful transcriptions yet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("menu.lastResult.empty")
            } else {
                ForEach(Array(recentSuccesses.enumerated()), id: \.element.id) { index, record in
                    recentTranscriptionRow(record, isLatest: index == 0)
                }
            }

            if let summary = appState.lastPasteSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("menu.lastPaste.summary")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func recentTranscriptionRow(_ record: TranscriptionRecord, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: isLatest ? 6 : 4) {
            if let text = record.text {
                Text(text)
                    .font(isLatest ? .body : .caption)
                    .lineLimit(isLatest ? 3 : 2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(isLatest ? "menu.lastResult.text" : "menu.recentResult.text")

                HStack(spacing: 8) {
                    Button {
                        copy(text)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier(isLatest ? "menu.lastResult.copyButton" : "menu.recentResult.copyButton")

                    if isLatest {
                        Button {
                            onPasteLast?()
                        } label: {
                            Label("Paste Again", systemImage: "arrow.turn.down.left")
                        }
                        .accessibilityIdentifier("menu.lastResult.pasteAgainButton")
                    }

                    Spacer()
                    Text(record.relativeTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(isLatest ? 0 : 7)
        .background {
            if !isLatest {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.background.opacity(0.45))
            }
        }
        .accessibilityIdentifier(isLatest ? "menu.lastResult.row" : "menu.recentResult.row")
    }

    private var recordingControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Record")
                .font(.subheadline.weight(.semibold))
            recordingControls
            if let blocker = recordingBlocker {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(blocker.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("menu.recording.blockedReason")
                    Spacer()
                    if let actionTitle = blocker.actionTitle, let action = blocker.action {
                        Button(actionTitle) {
                            action()
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("menu.recording.blockedAction")
                    }
                }
            }
        }
        .accessibilityIdentifier("menu.recording.section")
    }

    private var recordingControls: some View {
        HStack(spacing: 8) {
            Button {
                onStartRecording?()
            } label: {
                Label("Start", systemImage: "record.circle")
            }
            .disabled(!appState.canStartRecordingControl)
            .keyboardShortcut("r", modifiers: [.command])
            .accessibilityLabel("Start recording")
            .accessibilityHint("Begins recording audio for transcription.")
            .accessibilityIdentifier("menu.recording.startButton")
            .help("Start recording")

            Button {
                onStopRecording?()
            } label: {
                Label("Stop", systemImage: "stop.circle")
            }
            .disabled(!appState.canStopRecordingControl)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityLabel("Stop recording")
            .accessibilityHint("Stops recording and starts transcription.")
            .accessibilityIdentifier("menu.recording.stopButton")
            .help("Stop recording and transcribe")

            Button(role: .cancel) {
                if appState.canCancelTranscriptionControl {
                    onCancelTranscription?()
                } else {
                    onCancelRecording?()
                }
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .disabled(!appState.canCancelRecordingControl && !appState.canCancelTranscriptionControl)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(appState.canCancelTranscriptionControl ? "Cancel transcription" : "Cancel recording")
            .accessibilityHint(appState.canCancelTranscriptionControl ? "Stops waiting for the current transcription." : "Stops recording without transcription.")
            .accessibilityIdentifier("menu.recording.cancelButton")
            .help(appState.canCancelTranscriptionControl ? "Cancel transcription" : "Cancel recording")
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu.recording.controls")
    }

    private var recordingBlocker: (detail: String, actionTitle: String?, action: (() -> Void)?)? {
        guard appState.status == .idle, !appState.canStartRecordingControl else { return nil }

        if appState.accessibilityState != .ready {
            return (
                "Enable Accessibility before recording.",
                "Open Settings",
                onOpenAccessibility
            )
        }

        if appState.microphoneState != .ready {
            switch appState.microphoneState {
            case .unknown:
                return (
                    "Check microphone access before recording.",
                    "Check",
                    onCheckMicrophone
                )
            case .needsAction(let message):
                return (
                    microphoneBlockedReason(for: message),
                    "Open Settings",
                    onOpenMicrophone
                )
            case .ready:
                break
            }
        }

        if appState.apiKeyState != .ready {
            return (
                appState.selectedTranscriptionProvider.requiresAPIKey
                    ? "Add your \(appState.selectedTranscriptionProvider.displayName) API key before recording."
                    : "Finish provider setup before recording.",
                "Add Key",
                { openWindow(id: "api-key-setup") }
            )
        }

        return nil
    }

    private var sessionColor: Color {
        switch session.tone {
        case .neutral:
            .accentColor
        case .active:
            .red
        case .progress:
            .blue
        case .success:
            .green
        case .warning:
            .orange
        }
    }

    private func statusColor(for status: QueuedPasteStatus) -> Color {
        switch status {
        case .pending:
            .blue
        case .pasted:
            .green
        case .failed, .needsManualPaste:
            .orange
        }
    }

    private func performSessionAction(_ action: AppState.SessionAction) {
        switch action {
        case .retry:
            onRetry?()
        case .openAccessibility:
            onOpenAccessibility?()
        case .openMicrophone:
            onOpenMicrophone?()
        case .addKey:
            openWindow(id: "api-key-setup")
        case .pasteAgain:
            onPasteLast?()
        case .copy:
            if let text = lastSuccess?.text {
                copy(text)
            }
        }
    }

    private var feedbackIcon: String {
        switch appState.status {
        case .idle:
            "checkmark.circle"
        case .recording:
            "record.circle"
        case .transcribing:
            "arrow.triangle.2.circlepath"
        case .error:
            "exclamationmark.triangle"
        }
    }

    private func permissionIcon(for state: AppState.PermissionState) -> String {
        switch state {
        case .ready:
            "checkmark.circle.fill"
        case .needsAction:
            "exclamationmark.triangle.fill"
        case .unknown:
            "questionmark.circle"
        }
    }

    private func permissionColor(for state: AppState.PermissionState) -> Color {
        switch state {
        case .ready:
            .green
        case .needsAction:
            .orange
        case .unknown:
            .secondary
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

    private func permissionNeedsRecovery(_ state: AppState.PermissionState) -> Bool {
        if case .needsAction = state { return true }
        return false
    }

    private var microphoneRecoveryDetail: String {
        switch appState.microphoneState {
        case .needsAction(let message) where message == AppState.noMicrophoneDetectedMessage:
            "Connect a microphone or choose an available input in Sound settings."
        case .needsAction(let message) where message == AppState.selectedMicrophoneUnavailableMessage:
            "Open Recording settings and choose System Default or another available input."
        case .needsAction(let message) where message == AppState.microphonePromptTimedOutMessage:
            "Open Microphone privacy, allow \(AppBrand.name), then return to \(AppBrand.name)."
        default:
            "Open Microphone privacy and allow \(AppBrand.name)."
        }
    }

    private func microphoneBlockedReason(for message: String) -> String {
        if message == AppState.noMicrophoneDetectedMessage {
            return "Connect or select a working microphone before recording."
        }
        if message == AppState.selectedMicrophoneUnavailableMessage {
            return "Choose System Default or another available input before recording."
        }
        if message == AppState.microphonePromptTimedOutMessage {
            return "\(AppState.microphonePromptTimedOutMessage) before recording."
        }
        return "Allow microphone access before recording."
    }

    private var setupCheckTitle: String {
        switch appState.setupCheckState {
        case .idle, .running:
            "Test Setup"
        case .passed:
            "Setup Tested"
        case .failed:
            "Setup Check Failed"
        }
    }

    private var setupCheckDetail: String {
        switch appState.setupCheckState {
        case .idle:
            "Run local check"
        case .running:
            "Checking..."
        case .passed:
            appState.setupCheckSuccessDetail
        case .failed(let message):
            message
        }
    }

    private var setupCheckButtonTitle: String {
        switch appState.setupCheckState {
        case .failed:
            "Retry"
        case .running:
            "Checking"
        default:
            "Test"
        }
    }

    private var setupCheckIcon: String {
        switch appState.setupCheckState {
        case .idle:
            "checklist"
        case .running:
            "arrow.triangle.2.circlepath"
        case .passed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var setupCheckColor: Color {
        switch appState.setupCheckState {
        case .passed:
            .green
        case .failed:
            .orange
        case .idle, .running:
            .secondary
        }
    }

    private var setupCheckRecoveryDetail: String? {
        guard case .failed(let message) = appState.setupCheckState else { return nil }
        if message.localizedCaseInsensitiveContains("api key") {
            return "Add a \(appState.selectedTranscriptionProvider.displayName) API key, then run the setup test again."
        }
        if message.localizedCaseInsensitiveContains("accessibility") {
            return accessibilityRecoveryDetail
        }
        if message.localizedCaseInsensitiveContains("microphone") {
            return "Check Microphone privacy or audio input, then rerun the test."
        }
        return "Resolve the setup item above, then rerun the test."
    }

    private var accessibilityRecoveryDetail: String {
        #if DEBUG
        AppState.accessibilityRecoveryDetail(isDebugBuild: true)
        #else
        AppState.accessibilityRecoveryDetail(isDebugBuild: false)
        #endif
    }

    private var hotkeyLabel: String {
        switch appState.hotkeyChoice {
        case .rightCommand: "Right Command"
        case .rightOption: "Right Option"
        case .globeFn: "Globe/Fn"
        case .custom: appState.customHotkeyLabel.isEmpty ? "Custom" : appState.customHotkeyLabel
        }
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copySetupReport() {
        if let onCopySetupReport {
            onCopySetupReport()
        } else {
            copy(DiagnosticLog.setupReportText(appState: appState))
        }
    }

    private func openTroubleshooting() {
        let urlString = "https://github.com/usefoil/foil#troubleshooting"
        if isUITesting,
           let path = ProcessInfo.processInfo.environment["FOIL_UITEST_OPENED_URL_PATH"] {
            try? urlString.write(toFile: path, atomically: true, encoding: .utf8)
            return
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openHistory() {
        if let onOpenHistory {
            onOpenHistory()
        } else {
            openWindow(id: "history")
        }
    }

    private func openSettings() {
        if let onOpenSettings {
            onOpenSettings()
        } else {
            NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

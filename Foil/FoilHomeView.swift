import AppKit
import SwiftUI

struct FoilHomeView: View {
    @Bindable var appState: AppState
    @Bindable var queuedPasteQueue: QueuedPasteQueue
    var history: TranscriptionHistory
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onCancelTranscription: (() -> Void)?
    var onPasteLast: (() -> Void)?

    private var session: AppState.SessionPresentation {
        appState.sessionPresentation(
            hotkeyLabel: hotkeyLabel,
            hasRetryableFailure: history.retryableRecord != nil,
            hasLastSuccess: history.lastRecoverableText != nil
        )
    }

    private var recentSuccesses: [TranscriptionRecord] {
        history.recentSuccessfulRecords(limit: 4)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statusPanel
                if appState.needsSetupAttention {
                    setupHealthPanel
                }
                recentTranscriptsPanel
            }
            .padding(28)
        }
        .background(FoilTheme.windowBackground)
        .accessibilityIdentifier("appShell.home")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            FoilCylinderMark(size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("Home")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FoilTheme.deepTeal)
                Text(appState.dictationInstruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusPanel: some View {
        appPanel(accessibilityIdentifier: "appShell.home.status") {
            VStack(alignment: .leading, spacing: 14) {
                Label(session.title, systemImage: session.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FoilTheme.deepTeal)
                    .accessibilityIdentifier("appShell.home.statusTitle")
                Text(session.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(primaryControlTitle) {
                        runPrimaryControl()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FoilTheme.deepTeal)
                    .disabled(!primaryControlEnabled)
                    .accessibilityIdentifier("appShell.home.primaryControl")

                    Button("Copy last result") {
                        if let text = history.lastRecoverableText { copy(text) }
                    }
                    .disabled(history.lastRecoverableText == nil)
                    .accessibilityIdentifier("appShell.home.copyLastResultButton")

                    Button("Paste Last") {
                        onPasteLast?()
                    }
                    .disabled(history.lastRecoverableText == nil)
                    .accessibilityIdentifier("appShell.home.pasteLastButton")
                }

                Button("Setup and dictation practice") {
                    NotificationCenter.default.post(name: AppState.resumeSetupNotification, object: nil)
                }
                .accessibilityIdentifier("appShell.home.resumeSetupButton")

                HStack {
                    Label(appState.effectiveTranscriptionMode.displayName, systemImage: "waveform")
                    Spacer()
                    Button("Transcription settings") { FoilAppSection.request(.transcription) }
                }
                .font(.callout)

                if appState.effectiveTranscriptionMode == .managedLocal {
                    let coordinator = appState.managedLocalModels
                    let localStatus = ManagedLocalPresentation.status(
                        coordinatorState: coordinator?.state,
                        selectedID: coordinator?.selectedID,
                        activeID: coordinator?.activeID,
                        candidateID: coordinator?.candidateID,
                        recovery: coordinator?.recovery ?? [],
                        externalError: appState.managedLocalRestoreError
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localStatus.title).font(.caption.weight(.semibold))
                        Text(localStatus.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("appShell.home.managedLocalStatus")
                }

                DisclosureGroup("Text cleanup") {
                CleanupGroupStatusView(
                    group: appState.defaultCleanupGroup,
                    effectiveMode: appState.effectiveTranscriptProcessingMode,
                    title: "Default cleanup group",
                    accessibilityIdentifier: "appShell.home.cleanupGroupStatus",
                    descriptionAccessibilityIdentifier: "appShell.home.cleanupGroupDescription"
                )
                Button("Customize cleanup") { FoilAppSection.request(.cleanup) }
                }
                .accessibilityIdentifier("appShell.home.cleanupDisclosure")
            }
        }
    }

    private var setupHealthPanel: some View {
        appPanel(accessibilityIdentifier: "appShell.home.setupHealth") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Setup health")
                    .font(.headline)
                    .foregroundStyle(FoilTheme.deepTeal)
                healthRow(title: "Accessibility", state: appState.accessibilityState)
                healthRow(title: "Microphone", state: appState.microphoneState)
                if appState.selectedTranscriptionProvider.requiresAPIKey {
                    healthRow(title: "API Key", state: appState.apiKeyState)
                }
                if appState.effectiveTranscriptionMode == .managedLocal {
                    healthRow(
                        title: "Local model",
                        state: appState.managedLocalRuntime.session?.isRunning == true
                            ? .ready
                            : .needsAction("Restore or install a verified model")
                    )
                }
                HStack {
                    if appState.accessibilityState != .ready {
                        Button("Enable insertion") { openPrivacy("Privacy_Accessibility") }
                    }
                    if appState.microphoneState != .ready {
                        Button("Microphone access") { openPrivacy("Privacy_Microphone") }
                    }
                    Button("Set up transcription") { FoilAppSection.request(.transcription) }
                }
            }
        }
    }

    private var recentTranscriptsPanel: some View {
        appPanel(accessibilityIdentifier: "appShell.home.recentTranscripts") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent transcripts")
                        .font(.headline)
                        .foregroundStyle(FoilTheme.deepTeal)
                    Spacer()
                    Button("Open History") { FoilAppSection.request(.history) }
                    if queuedPasteQueue.pendingCount > 0 || queuedPasteQueue.blockedCount > 0 {
                        Text("\(queuedPasteQueue.pendingCount) queued")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FoilTheme.midTeal)
                    }
                }

                if recentSuccesses.isEmpty {
                    Text(history.isPersistenceEnabled ? "Your first transcript will appear here. Try your shortcut in a text field." : "New history is off. Copy last result stays available until Foil quits or you clear history.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                } else {
                    ForEach(recentSuccesses) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.text ?? "")
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            HStack {
                                Text(record.relativeTimestamp)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Copy") { copy(record.text ?? "") }
                                    .accessibilityLabel("Copy transcript from \(record.relativeTimestamp)")
                            }
                        }
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
            }
        }
    }

    private func appPanel<Content: View>(
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 162, alignment: .topLeading)
            .background(FoilTheme.panelBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(FoilTheme.separator)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func healthRow(title: String, state: AppState.PermissionState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: healthImage(for: state))
                .foregroundStyle(healthColor(for: state))
            Text("\(title) \(healthText(for: state))")
                .font(.subheadline)
            Spacer()
        }
    }

    private func healthText(for state: AppState.PermissionState) -> String {
        switch state {
        case .ready: "Ready"
        case .needsAction(let message): message
        case .unknown: "Not checked"
        }
    }

    private func healthImage(for state: AppState.PermissionState) -> String {
        switch state {
        case .ready: "checkmark.circle.fill"
        case .needsAction: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private func healthColor(for state: AppState.PermissionState) -> Color {
        switch state {
        case .ready: FoilTheme.statusSuccess
        case .needsAction: FoilTheme.statusWarning
        case .unknown: .secondary
        }
    }

    private var primaryControlTitle: String {
        if appState.canStopRecordingControl { return "Stop" }
        if appState.canCancelTranscriptionControl { return "Cancel" }
        return "Record"
    }

    private var primaryControlEnabled: Bool {
        appState.canStartRecordingControl || appState.canStopRecordingControl || appState.canCancelTranscriptionControl
    }

    private func runPrimaryControl() {
        if appState.canStopRecordingControl {
            onStopRecording?()
        } else if appState.canCancelTranscriptionControl {
            onCancelTranscription?()
        } else {
            onStartRecording?()
        }
    }

    private var hotkeyLabel: String {
        switch appState.hotkeyChoice {
        case .rightCommand: "Right Command"
        case .rightOption: "Right Option"
        case .globeFn: "Globe/Fn"
        case .custom: appState.customHotkeyLabel.isEmpty ? "Custom" : appState.customHotkeyLabel
        }
    }
}

struct CleanupGroupStatusView: View {
    var group: CleanupGroup
    var effectiveMode: TranscriptProcessingMode
    var title: String
    var accessibilityIdentifier: String
    var descriptionAccessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: group.processingMode == .raw ? "text.quote" : "wand.and.stars")
                    .foregroundStyle(FoilTheme.midTeal)
                Text(group.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .accessibilityIdentifier(accessibilityIdentifier)

            Text(descriptionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(descriptionAccessibilityIdentifier)
        }
    }

    private var descriptionText: String {
        guard effectiveMode == group.processingMode else {
            return "\(group.processingMode.displayName) is configured, but cleanup is unavailable. Recordings will paste raw transcripts."
        }
        if group.processingMode == .raw {
            return "Unassigned apps paste raw transcripts."
        }
        return "\(group.cleanupProviderID.displayName) · \(group.cleanupModel)"
    }
}

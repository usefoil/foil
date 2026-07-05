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
            hasLastSuccess: history.successfulRecords.isEmpty == false
        )
    }

    private var recentSuccesses: [TranscriptionRecord] {
        history.recentSuccessfulRecords(limit: 4)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], alignment: .leading, spacing: 16) {
                    statusPanel
                    setupHealthPanel
                    recentTranscriptsPanel
                        .gridCellColumns(2)
                }
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
                Text("Right Command captures speech and pastes the transcript into your current app.")
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

                    Button("Paste Last") {
                        onPasteLast?()
                    }
                    .disabled(history.successfulRecords.isEmpty)
                    .accessibilityIdentifier("appShell.home.pasteLastButton")
                }

                CleanupGroupStatusView(
                    group: appState.defaultCleanupGroup,
                    effectiveMode: appState.effectiveTranscriptProcessingMode,
                    title: "Default cleanup group",
                    accessibilityIdentifier: "appShell.home.cleanupGroupStatus",
                    descriptionAccessibilityIdentifier: "appShell.home.cleanupGroupDescription"
                )
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
                healthRow(title: "API Key", state: appState.apiKeyState)
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
                    if queuedPasteQueue.pendingCount > 0 || queuedPasteQueue.blockedCount > 0 {
                        Text("\(queuedPasteQueue.pendingCount) queued")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FoilTheme.midTeal)
                    }
                }

                if recentSuccesses.isEmpty {
                    Text("No recent transcripts")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                } else {
                    ForEach(recentSuccesses) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.text ?? "")
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            Text(record.relativeTimestamp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
            .accessibilityIdentifier(accessibilityIdentifier)
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
        case .needsAction: "Needs attention"
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
        case .ready: FoilTheme.midTeal
        case .needsAction: .orange
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

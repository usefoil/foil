import SwiftUI

struct FoilAppShellView: View {
    @Bindable var appState: AppState
    @Bindable var queuedPasteQueue: QueuedPasteQueue
    var history: TranscriptionHistory
    var usageEventStore: UsageEventStore
    var onRetryRecord: ((TranscriptionRecord) -> Void)?
    var onPasteText: ((String) -> Void)?
    var onSaveAndRecleanVocabularyCorrection: ((String, String, String?, UUID, String?) async -> HistoryVocabularyRecleanResult)?
    var onTransformTranscript: ((HistoryTransformKind, UUID, String, String?) async -> HistoryTransformResult)?
    var onHotkeyChanged: (() -> Void)?
    var onCopySetupReport: (() -> Void)?
    var onExportDiagnostics: (() -> Void)?
    var onStartLocalWhisperServer: ((LocalWhisperSetupModelID) -> Void)?
    var onStopLocalWhisperServer: (() -> Void)?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onCancelTranscription: (() -> Void)?
    var onPasteLast: (() -> Void)?

    @State private var selection: FoilAppSection

    init(
        appState: AppState,
        queuedPasteQueue: QueuedPasteQueue,
        history: TranscriptionHistory,
        usageEventStore: UsageEventStore,
        initialSelection: FoilAppSection = .home,
        onRetryRecord: ((TranscriptionRecord) -> Void)? = nil,
        onPasteText: ((String) -> Void)? = nil,
        onSaveAndRecleanVocabularyCorrection: ((String, String, String?, UUID, String?) async -> HistoryVocabularyRecleanResult)? = nil,
        onTransformTranscript: ((HistoryTransformKind, UUID, String, String?) async -> HistoryTransformResult)? = nil,
        onHotkeyChanged: (() -> Void)? = nil,
        onCopySetupReport: (() -> Void)? = nil,
        onExportDiagnostics: (() -> Void)? = nil,
        onStartLocalWhisperServer: ((LocalWhisperSetupModelID) -> Void)? = nil,
        onStopLocalWhisperServer: (() -> Void)? = nil,
        onStartRecording: (() -> Void)? = nil,
        onStopRecording: (() -> Void)? = nil,
        onCancelRecording: (() -> Void)? = nil,
        onCancelTranscription: (() -> Void)? = nil,
        onPasteLast: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.queuedPasteQueue = queuedPasteQueue
        self.history = history
        self.usageEventStore = usageEventStore
        self.onRetryRecord = onRetryRecord
        self.onPasteText = onPasteText
        self.onSaveAndRecleanVocabularyCorrection = onSaveAndRecleanVocabularyCorrection
        self.onTransformTranscript = onTransformTranscript
        self.onHotkeyChanged = onHotkeyChanged
        self.onCopySetupReport = onCopySetupReport
        self.onExportDiagnostics = onExportDiagnostics
        self.onStartLocalWhisperServer = onStartLocalWhisperServer
        self.onStopLocalWhisperServer = onStopLocalWhisperServer
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
        self.onCancelRecording = onCancelRecording
        self.onCancelTranscription = onCancelTranscription
        self.onPasteLast = onPasteLast
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        HStack(spacing: 0) {
            FoilSidebarView(selection: $selection)

            Divider()
                .background(FoilTheme.separator)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(FoilTheme.windowBackground)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appShell.root")
        .onAppear(perform: applyPendingSelectionRequest)
        .onReceive(NotificationCenter.default.publisher(for: FoilAppSection.selectionRequestedNotification)) { notification in
            guard let rawValue = notification.userInfo?["section"] as? String,
                  let requestedSelection = FoilAppSection(rawValue: rawValue) else {
                return
            }
            selection = requestedSelection
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .home:
            FoilHomeView(
                appState: appState,
                queuedPasteQueue: queuedPasteQueue,
                history: history,
                onStartRecording: onStartRecording,
                onStopRecording: onStopRecording,
                onCancelRecording: onCancelRecording,
                onCancelTranscription: onCancelTranscription,
                onPasteLast: onPasteLast
            )
        case .insights:
            UsageInsightsView(
                appState: appState,
                usageEventStore: usageEventStore
            )
            .accessibilityIdentifier("appShell.insights")
        case .history:
            HistoryPopoverView(
                history: history,
                onRetry: onRetryRecord,
                onPaste: onPasteText,
                onSaveVocabularyTerm: { [appState] term, note in
                    appState.addVocabularyTerm(term, note: note)
                },
                onSaveVocabularyCorrection: { [appState] writtenAs, correctVersion, note, sourceRecordID, sourceAppName in
                    appState.addVocabularyCorrection(
                        writtenAs: writtenAs,
                        correctVersion: correctVersion,
                        note: note,
                        sourceRecordID: sourceRecordID,
                        sourceAppName: sourceAppName
                    )
                },
                onSaveAndRecleanVocabularyCorrection: onSaveAndRecleanVocabularyCorrection,
                onTransformTranscript: onTransformTranscript,
                canSaveAndRecleanVocabularyCorrection: appState.canRecleanHistoryTranscripts,
                canTransformHistoryTranscripts: appState.canTransformHistoryTranscripts,
                showsHeader: true
            )
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FoilTheme.windowBackground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("appShell.history")
        case .general, .recording, .transcription, .cleanup, .paste, .storage, .whatsNew, .experimental:
            SettingsView(
                appState: appState,
                history: history,
                usageEventStore: usageEventStore,
                initialTab: settingsTab(for: selection),
                onHotkeyChanged: onHotkeyChanged,
                onCopySetupReport: onCopySetupReport,
                onExportDiagnostics: onExportDiagnostics,
                onStartLocalWhisperServer: onStartLocalWhisperServer,
                onStopLocalWhisperServer: onStopLocalWhisperServer,
                showsTabStrip: false,
                usesFixedFrame: false
            )
            .id(selection)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FoilTheme.windowBackground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("appShell.preferences")
        }
    }

    private func settingsTab(for section: FoilAppSection) -> SettingsView.Tab {
        switch section {
        case .home, .insights, .history:
            .general
        case .general:
            .general
        case .recording:
            .recording
        case .transcription:
            .transcription
        case .cleanup:
            .cleanup
        case .paste:
            .paste
        case .storage:
            .privacy
        case .whatsNew:
            .whatsNew
        case .experimental:
            .experimental
        }
    }

    private func applyPendingSelectionRequest() {
        guard let requestedSelection = FoilAppSection.takePendingRequest() else {
            return
        }
        selection = requestedSelection
    }
}

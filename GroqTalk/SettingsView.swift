import AppKit
import SwiftUI

struct SettingsView: View {
    enum Tab: Hashable, CaseIterable {
        case general
        case recording
        case transcription
        case paste
        case privacy
        case experimental

        var title: String {
            switch self {
            case .general: "General"
            case .recording: "Recording"
            case .transcription: "Transcription"
            case .paste: "Paste"
            case .privacy: "Storage"
            case .experimental: "Experimental"
            }
        }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .recording: "mic"
            case .transcription: "waveform"
            case .paste: "text.cursor"
            case .privacy: "lock"
            case .experimental: "testtube.2"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .general: "settings.tab.general"
            case .recording: "settings.tab.recording"
            case .transcription: "settings.tab.transcription"
            case .paste: "settings.tab.paste"
            case .privacy: "settings.tab.privacy"
            case .experimental: "settings.tab.experimental"
            }
        }
    }

    enum ExperimentalCopy {
        static let pasteRoutingPurpose = "Auto-pastes back into the app you started from while you keep working elsewhere."
        static let pasteTargetTitle = "Return to starting app"
        static let pasteTargetOnDescription = "After transcribing, refocuses the app where recording began and pastes there."
        static let pasteTargetOffDescription = "Pastes into the app active when transcription finishes."
        static let backgroundPasteTitle = "Try background paste"
        static let backgroundPasteDescription = "Uses a lower-level paste route. Leave off unless normal paste fails."
    }

    @Bindable var appState: AppState
    var history: TranscriptionHistory
    var onHotkeyChanged: (() -> Void)?

    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: Tab
    @State private var isShowingClearHistoryConfirmation = false
    @State private var launchAtLoginManager = LaunchAtLoginManager()
    @State private var notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
    private var sparkleUpdater: SparkleUpdater { SparkleUpdater.shared }
    private let soundPreviewPlayer = SoundPlayer()

    init(
        appState: AppState,
        history: TranscriptionHistory,
        initialTab: Tab = .general,
        onHotkeyChanged: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.history = history
        self.onHotkeyChanged = onHotkeyChanged
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 14) {
            settingsTabStrip

            selectedSettingsPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("settings.root")
        .scenePadding()
        .frame(width: 680, height: 430)
        .alert("Clear History?", isPresented: $isShowingClearHistoryConfirmation) {
            Button("Clear History", role: .destructive) {
                history.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all stored transcripts and any retained failed-audio retry files from this Mac.")
        }
    }

    private var settingsTabStrip: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background {
                    if selectedTab == tab {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                    }
                }
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .accessibilityValue(selectedTab == tab ? "Selected" : "")
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var selectedSettingsPane: some View {
        switch selectedTab {
        case .general:
            generalSettings
        case .recording:
            recordingSettings
        case .transcription:
            transcriptionSettings
        case .paste:
            pasteSettings
        case .privacy:
            privacySettings
        case .experimental:
            experimentalSettings
        }
    }

    private var generalSettings: some View {
        Form {
            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLoginManager.isEnabled },
                set: { launchAtLoginManager.setEnabled($0) }
            ))
            .accessibilityIdentifier("settings.launchAtLoginToggle")
            Toggle("Show Notifications", isOn: $notificationsEnabled)
                .accessibilityIdentifier("settings.notificationsToggle")
                .onChange(of: notificationsEnabled) { _, enabled in
                    UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
                    if enabled {
                        Task {
                            let granted = await NotificationManager.shared.requestAuthorization()
                            if !granted {
                                notificationsEnabled = false
                                UserDefaults.standard.set(false, forKey: "notificationsEnabled")
                            }
                        }
                    }
                }
            Toggle("Sound effects", isOn: $appState.soundEffectsEnabled)
                .accessibilityIdentifier("settings.soundEffectsToggle")
            Toggle("Show floating status", isOn: $appState.showFloatingStatus)
                .accessibilityIdentifier("settings.floatingStatusToggle")

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { sparkleUpdater.automaticallyChecksForUpdates },
                    set: { sparkleUpdater.automaticallyChecksForUpdates = $0 }
                ))

                Button("Check for Updates…") {
                    sparkleUpdater.checkForUpdates()
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
    }

    private var recordingSettings: some View {
        Form {
            Picker("Hotkey", selection: $appState.hotkeyChoice) {
                ForEach(HotkeyMonitor.HotkeyChoice.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .accessibilityIdentifier("settings.hotkeyPicker")
            .onChange(of: appState.hotkeyChoice) { _, _ in onHotkeyChanged?() }

            if appState.hotkeyChoice == .custom {
                KeyRecorderView(
                    keyCode: $appState.customHotkeyKeyCode,
                    modifiers: $appState.customHotkeyModifiers,
                    label: $appState.customHotkeyLabel
                )
                .onChange(of: appState.customHotkeyKeyCode) { _, _ in onHotkeyChanged?() }
            }

            Picker("Mode", selection: $appState.recordingMode) {
                Text("Hold to record").tag(HotkeyMonitor.RecordingMode.hold)
                Text("Toggle").tag(HotkeyMonitor.RecordingMode.toggle)
            }
            .accessibilityIdentifier("settings.recordingModePicker")
            .onChange(of: appState.recordingMode) { _, _ in onHotkeyChanged?() }

            Section("Recording Sounds") {
                soundCuePicker(
                    title: "Start",
                    selection: $appState.recordingStartSoundCue,
                    previewHelp: "Preview start sound",
                    pickerIdentifier: "settings.recordingStartSoundPicker",
                    previewIdentifier: "settings.recordingStartSoundPreviewButton"
                )

                soundCuePicker(
                    title: "End",
                    selection: $appState.recordingEndSoundCue,
                    previewHelp: "Preview end sound",
                    pickerIdentifier: "settings.recordingEndSoundPicker",
                    previewIdentifier: "settings.recordingEndSoundPreviewButton"
                )
            }

            Picker("Audio format", selection: $appState.selectedAudioFormat) {
                Text("M4A").tag(AudioFormat.m4a)
                Text("WAV").tag(AudioFormat.wav)
                Text("FLAC").tag(AudioFormat.flac)
            }

            Picker("Input Device", selection: $appState.selectedInputDeviceUID) {
                Text("System Default").tag(nil as String?)
                ForEach(AudioRecorder.availableInputDevices()) { device in
                    Text(device.name).tag(Optional(device.uid))
                }
            }
            .accessibilityIdentifier("settings.inputDevicePicker")
        }
        .formStyle(.grouped)
    }

    private func soundCuePicker(
        title: String,
        selection: Binding<RecordingSoundCue>,
        previewHelp: String,
        pickerIdentifier: String,
        previewIdentifier: String
    ) -> some View {
        HStack {
            Picker(title, selection: selection) {
                ForEach(RecordingSoundCue.allCases) { cue in
                    Text(cue.displayName).tag(cue)
                }
            }
            .accessibilityIdentifier(pickerIdentifier)

            Spacer()

            Button {
                soundPreviewPlayer.preview(selection.wrappedValue)
            } label: {
                Label("Preview", systemImage: "play.fill")
            }
            .help(previewHelp)
            .accessibilityIdentifier(previewIdentifier)
        }
    }

    private var transcriptionSettings: some View {
        Form {
            Picker("Provider", selection: $appState.selectedTranscriptionProviderPresetID) {
                Text("Groq").tag(TranscriptionProviderPresetID.groq)
                Text("Local whisper.cpp").tag(TranscriptionProviderPresetID.localWhisperCPP)
                Text("Custom OpenAI-compatible").tag(TranscriptionProviderPresetID.customOpenAICompatible)
            }
            .accessibilityIdentifier("settings.transcriptionProviderPicker")
            .onChange(of: appState.selectedTranscriptionProviderPresetID) { _, _ in
                appState.refreshApiKeyState()
            }

            Section("Credentials") {
                HStack {
                    Text("\(appState.selectedTranscriptionProvider.displayName) API key")
                    Spacer()
                    Label(apiKeyStatusLabel, systemImage: apiKeyStatusImage)
                        .foregroundStyle(apiKeyStatusColor)
                    Button("Change...") {
                        openWindow(id: "api-key-setup")
                    }
                    .accessibilityIdentifier("settings.changeApiKeyButton")
                }

                if appState.selectedTranscriptionProvider.id == .openAICompatible {
                    HStack {
                        Button("Test connection") {
                            Task {
                                await appState.testSelectedProviderConnection()
                            }
                        }
                        .disabled(appState.providerConnectionTestState.isRunning)
                        .accessibilityIdentifier("settings.testProviderConnectionButton")

                        providerConnectionStatus
                    }
                }
            }

            Section("Model") {
                if appState.selectedTranscriptionProviderPresetID == .groq {
                    Picker("Whisper model", selection: $appState.selectedModel) {
                        Text("Large V3 Turbo").tag("whisper-large-v3-turbo")
                        Text("Large V3").tag("whisper-large-v3")
                    }
                } else if appState.selectedTranscriptionProviderPresetID == .localWhisperCPP {
                    LabeledContent("Base URL", value: "http://127.0.0.1:8080/v1")
                    LabeledContent("Model", value: "whisper-1")
                    Text("Install whisper.cpp, download a model, then start whisper-server on 127.0.0.1:8080 with --inference-path /v1/audio/transcriptions. API key is optional; use a dummy value such as local only if your server expects one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.localProviderHelp")
                } else {
                    TextField("Base URL", text: $appState.customTranscriptionBaseURL)
                        .accessibilityIdentifier("settings.customTranscriptionBaseURL")
                    TextField("Model", text: $appState.customTranscriptionModel)
                        .accessibilityIdentifier("settings.customTranscriptionModel")
                    Text("API key is optional for custom OpenAI-compatible transcription servers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.customProviderHelp")
                }

                Picker("Speech language", selection: $appState.selectedLanguage) {
                    ForEach(Language.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            Section("Cleanup") {
                if appState.supportsSelectedTranscriptProcessing {
                    Picker("After transcription", selection: $appState.transcriptProcessingMode) {
                        ForEach(TranscriptProcessingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("settings.transcriptProcessingPicker")

                    if appState.transcriptProcessingMode != .raw {
                        Picker("Cleanup model", selection: $appState.transcriptCleanupModel) {
                            Text("Llama 3.3 70B Versatile").tag("llama-3.3-70b-versatile")
                            Text("Llama 3.1 8B Instant").tag("llama-3.1-8b-instant")
                        }
                        .accessibilityIdentifier("settings.cleanupModelPicker")
                    }
                } else {
                    Text("Cleanup requires a Groq-compatible chat provider. Custom transcription currently uses raw transcripts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.transcriptProcessingUnavailable")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var apiKeyStatusLabel: String {
        if appState.hasApiKey { return "Saved" }
        return appState.selectedTranscriptionProvider.requiresAPIKey ? "Missing" : "Optional"
    }

    private var apiKeyStatusImage: String {
        if appState.hasApiKey { return "checkmark.circle.fill" }
        return appState.selectedTranscriptionProvider.requiresAPIKey ? "exclamationmark.circle" : "minus.circle"
    }

    private var apiKeyStatusColor: Color {
        if appState.hasApiKey { return .green }
        return appState.selectedTranscriptionProvider.requiresAPIKey ? .orange : .secondary
    }

    @ViewBuilder
    private var providerConnectionStatus: some View {
        switch appState.providerConnectionTestState {
        case .idle:
            Text("Not tested")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.providerConnectionStatus")
        case .running:
            ProgressView("Testing...")
                .controlSize(.small)
                .accessibilityIdentifier("settings.providerConnectionStatus")
        case .succeeded(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("settings.providerConnectionStatus")
        case .warning(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("settings.providerConnectionStatus")
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityIdentifier("settings.providerConnectionStatus")
        }
    }

    private var pasteSettings: some View {
        Form {
            Toggle("Keep final text on clipboard", isOn: $appState.keepOnClipboard)
                .accessibilityIdentifier("settings.keepClipboardToggle")
        }
        .formStyle(.grouped)
    }

    private var privacySettings: some View {
        Form {
            Section("Local Data") {
                Picker("History retention", selection: retentionBinding) {
                    Text("Off").tag(0)
                    Text("Last 100 records").tag(100)
                    Text("Last 500 records").tag(500)
                    Text("Last 1000 records").tag(1000)
                }
                .accessibilityIdentifier("settings.historyRetentionPicker")
                LabeledContent("Stored records", value: "\(history.records.count)")
                LabeledContent("Retained failed audio", value: "\(history.retainedFailedAudioCount)")
                Text("History is stored locally on this Mac. Successful audio files are deleted after transcription. When transcription fails, the failed audio may be retained locally only so you can retry it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                Button("Open App Data Folder") {
                    openAppDataFolder()
                }
                .accessibilityIdentifier("settings.openDataFolderButton")
            }

            Section("Clear Local Data") {
                Button("Clear History", role: .destructive) {
                    isShowingClearHistoryConfirmation = true
                }
                .accessibilityIdentifier("settings.clearHistoryButton")
                .disabled(history.records.isEmpty)
                Button("Clear Failed Audio", role: .destructive) {
                    history.clearRetainedFailedAudio()
                }
                .accessibilityIdentifier("settings.clearRetainedAudioButton")
                .disabled(history.retainedFailedAudioCount == 0)
            }
        }
        .formStyle(.grouped)
    }

    private var experimentalSettings: some View {
        Form {
            Section("Paste Routing") {
                Text(ExperimentalCopy.pasteRoutingPurpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(ExperimentalCopy.pasteTargetTitle, isOn: $appState.asyncPasteEnabled)
                    .accessibilityIdentifier("settings.asyncPasteToggle")
                Text(appState.asyncPasteEnabled ? ExperimentalCopy.pasteTargetOnDescription : ExperimentalCopy.pasteTargetOffDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(ExperimentalCopy.backgroundPasteTitle, isOn: $appState.experimentalSkyLightPasteEnabled)
                    .accessibilityIdentifier("settings.experimentalSkyLightPasteToggle")
                Text(ExperimentalCopy.backgroundPasteDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Browser Media") {
                Toggle("Pause browser media while recording", isOn: $appState.pauseBrowserMediaWhileRecording)
                    .accessibilityIdentifier("settings.pauseBrowserMediaToggle")
                Text("Experimental. Chrome and Chromium only. Chrome must allow JavaScript from Apple Events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            Section("Debug") {
                Toggle("Mock transcription", isOn: $appState.mockTranscriptionEnabled)
                    .accessibilityIdentifier("settings.mockToggle")
            }
            #endif
        }
        .formStyle(.grouped)
    }

    private var retentionBinding: Binding<Int> {
        Binding(
            get: { history.isPersistenceEnabled ? history.retentionLimit : 0 },
            set: { value in
                if value == 0 {
                    history.isPersistenceEnabled = false
                } else {
                    history.isPersistenceEnabled = true
                    history.retentionLimit = value
                }
            }
        )
    }

    private func openAppDataFolder() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }
        let dir = appSupport.appendingPathComponent("GroqTalk", isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}

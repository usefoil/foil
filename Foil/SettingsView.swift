import AppKit
import SwiftUI

struct SettingsView: View {
    enum Tab: Hashable, CaseIterable {
        case general
        case recording
        case transcription
        case paste
        case privacy
        case whatsNew
        case experimental

        var title: String {
            switch self {
            case .general: "General"
            case .recording: "Recording"
            case .transcription: "Transcription"
            case .paste: "Paste"
            case .privacy: "Storage"
            case .whatsNew: "What's New"
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
            case .whatsNew: "sparkles"
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
            case .whatsNew: "settings.tab.whatsNew"
            case .experimental: "settings.tab.experimental"
            }
        }
    }

    enum ExperimentalCopy {
        static let pasteRoutingPurpose = "Auto-pastes back into the app you started from while you keep working elsewhere."
        static let pasteTargetTitle = "Return to starting app"
        static let pasteTargetOnDescription = "After transcribing, refocuses the app where recording began and pastes there."
        static let pasteTargetOffDescription = "Pastes into the app active when transcription finishes."
        static let queuedPasteTitle = "Queue transcriptions for later paste"
        static let queuedPasteDescription = "Completed transcripts wait in the menu until you paste them. Delivery may briefly switch apps or windows."
        static let queuedPasteShortcutConflict = "Delivery shortcut conflicts with the custom recording shortcut."
        static let backgroundPasteTitle = "Try background paste"
        static let backgroundPasteDescription = "Uses a lower-level paste route. Leave off unless normal paste fails."
    }

    enum RecordingCopy {
        static let builtInMicBluetoothGuidance = "AirPods stay connected for listening, but Foil records from your MacBook microphone to avoid Bluetooth audio quality drops."
        static let builtInMicBluetoothNotificationTitle = "Using MacBook mic"
        static let builtInMicBluetoothNotificationBody = "AirPods stay connected for listening while Foil records from your MacBook microphone."

        static func systemDefaultBluetoothFallback(defaultInputName: String, fallbackInputName: String) -> String {
            "System Default currently points to \(defaultInputName). Foil will record from \(fallbackInputName) when possible so your headphones can stay on the listening route."
        }

        static func bluetoothInputWarning(deviceName: String) -> String {
            "Using \(deviceName) as the microphone can reduce other audio quality or volume while recording. Choose System Default, the Mac microphone, or another known non-Bluetooth input to keep playback unchanged."
        }
    }

    @Bindable var appState: AppState
    var history: TranscriptionHistory
    var onHotkeyChanged: (() -> Void)?
    var onCopySetupReport: (() -> Void)?
    var onExportDiagnostics: (() -> Void)?

    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: Tab
    @State private var isShowingClearHistoryConfirmation = false
    @State private var launchAtLoginManager = LaunchAtLoginManager()
    @State private var notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
    @State private var selectedLocalWhisperSetupModelID = LocalWhisperSetupModel.recommendedDefaultID
    @State private var customCleanupAPIKey = ""
    private var sparkleUpdater: SparkleUpdater { SparkleUpdater.shared }
    private let soundPreviewPlayer = SoundPlayer()

    init(
        appState: AppState,
        history: TranscriptionHistory,
        initialTab: Tab = .general,
        onHotkeyChanged: (() -> Void)? = nil,
        onCopySetupReport: (() -> Void)? = nil,
        onExportDiagnostics: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.history = history
        self.onHotkeyChanged = onHotkeyChanged
        self.onCopySetupReport = onCopySetupReport
        self.onExportDiagnostics = onExportDiagnostics
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 14) {
            settingsTabStrip

            selectedSettingsPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            AppVersionFooter(accessibilityIdentifier: "settings.appVersionFooter")
        }
        .accessibilityIdentifier("settings.root")
        .scenePadding()
        .frame(width: 680, height: 452)
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
        case .whatsNew:
            whatsNewSettings
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
                ForEach(availableInputDevices) { device in
                    Text(device.name).tag(Optional(device.uid))
                }
            }
            .accessibilityIdentifier("settings.inputDevicePicker")

            if BluetoothMicGuidance.shouldShowSettingsGuidance(
                selectedInputDevice: effectiveInputDevice,
                availableInputDevices: availableInputDevices
            ) {
                Text(RecordingCopy.builtInMicBluetoothGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.builtInMicBluetoothGuidance")
            }

            if let fallbackDevice = BluetoothMicGuidance.automaticFallbackDevice(
                selectedInputDeviceUID: appState.selectedInputDeviceUID,
                effectiveInputDevice: effectiveInputDevice,
                availableInputDevices: availableInputDevices
            ), let inputDevice = effectiveInputDevice {
                Label {
                    Text(RecordingCopy.systemDefaultBluetoothFallback(
                        defaultInputName: inputDevice.name,
                        fallbackInputName: fallbackDevice.name
                    ))
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.systemDefaultBluetoothFallback")
            } else if BluetoothMicGuidance.shouldWarnAboutBluetoothInput(
                selectedInputDeviceUID: appState.selectedInputDeviceUID,
                effectiveInputDevice: effectiveInputDevice,
                availableInputDevices: availableInputDevices
            ), let inputDevice = effectiveInputDevice {
                Label {
                    Text(RecordingCopy.bluetoothInputWarning(deviceName: inputDevice.name))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("settings.bluetoothInputWarning")
            }

            Section("Other Audio") {
                Toggle("Pause supported browser media while recording", isOn: $appState.pauseBrowserMediaWhileRecording)
                    .accessibilityIdentifier("settings.pauseBrowserMediaToggle")
                Text("Off by default. When enabled, Foil attempts to pause playing Chrome and Chromium tabs while recording. Other apps and system audio are not controlled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private var effectiveInputDevice: AudioRecorder.AudioDevice? {
        if let uid = appState.selectedInputDeviceUID {
            return availableInputDevices.first { $0.uid == uid }
        }
        return AudioRecorder.effectiveInputDevice(forUID: nil)
    }

    private var availableInputDevices: [AudioRecorder.AudioDevice] {
        AudioRecorder.availableInputDevices()
    }

    private var transcriptionSettings: some View {
        Form {
            Picker("Provider", selection: $appState.selectedTranscriptionProviderPresetID) {
                Text("Groq").tag(TranscriptionProviderPresetID.groq)
                Text("OpenAI Whisper").tag(TranscriptionProviderPresetID.openAIWhisper)
                Text("Local whisper.cpp").tag(TranscriptionProviderPresetID.localWhisperCPP)
                Text("Custom OpenAI-compatible").tag(TranscriptionProviderPresetID.customOpenAICompatible)
            }
            .accessibilityIdentifier("settings.transcriptionProviderPicker")
            .onChange(of: appState.selectedTranscriptionProviderPresetID) { _, _ in
                appState.refreshApiKeyState()
            }

            Text(providerPrivacySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.providerPrivacySummary")

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
                    Text(providerConnectionHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.providerConnectionHelp")
                }
            }

            Section("Model") {
                if appState.selectedTranscriptionProviderPresetID == .groq {
                    Picker("Whisper model", selection: $appState.selectedModel) {
                        Text("Large V3 Turbo").tag("whisper-large-v3-turbo")
                        Text("Large V3").tag("whisper-large-v3")
                    }
                } else if appState.selectedTranscriptionProviderPresetID == .openAIWhisper {
                    LabeledContent("Base URL", value: "https://api.openai.com/v1")
                    LabeledContent("Model", value: "whisper-1")
                    Text("Audio is sent to OpenAI's cloud transcription endpoint using your OpenAI API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.openAIProviderHelp")
                } else if appState.selectedTranscriptionProviderPresetID == .localWhisperCPP {
                    LabeledContent("Base URL", value: "http://127.0.0.1:8080/v1")
                    LabeledContent("Model", value: "whisper-1")
                    Text("Install whisper.cpp, download a model, then start whisper-server on 127.0.0.1:8080 with --inference-path /v1/audio/transcriptions. API key is optional; use a dummy value such as local only if your server expects one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.localProviderHelp")
                    localWhisperSetupHelper
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
                Picker("After transcription", selection: $appState.transcriptProcessingMode) {
                    ForEach(TranscriptProcessingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .accessibilityIdentifier("settings.transcriptProcessingPicker")

                if appState.transcriptProcessingMode != .raw {
                    cleanupProviderSettings
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var cleanupProviderSettings: some View {
        Picker("Cleanup provider", selection: $appState.transcriptCleanupProviderID) {
            ForEach(availableCleanupProviderIDs) { providerID in
                Text(providerID.displayName).tag(providerID)
            }
        }
        .accessibilityIdentifier("settings.cleanupProviderPicker")

        Text("Cleanup uses the selected chat endpoint. Foil will not send local/custom transcripts to Groq unless you choose Groq here.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("settings.cleanupRoutingHelp")

        switch appState.transcriptCleanupProviderID {
        case .groq:
            groqCleanupModelPicker
        case .customOpenAICompatibleChat:
            customChatCleanupSettings
        case .none:
            Text("Foil will paste raw transcripts until a cleanup provider is selected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.transcriptProcessingUnavailable")
        }
    }

    private var availableCleanupProviderIDs: [TranscriptCleanupProviderID] {
        switch appState.selectedTranscriptionProviderPresetID {
        case .groq:
            [.groq, .none, .customOpenAICompatibleChat]
        case .openAIWhisper, .localWhisperCPP, .customOpenAICompatible:
            [.none, .customOpenAICompatibleChat]
        }
    }

    private var groqCleanupModelPicker: some View {
        Picker("Cleanup model", selection: $appState.transcriptCleanupModel) {
            Text("Llama 3.3 70B Versatile").tag("llama-3.3-70b-versatile")
            Text("Llama 3.1 8B Instant").tag("llama-3.1-8b-instant")
        }
        .accessibilityIdentifier("settings.cleanupModelPicker")
    }

    private var customChatCleanupSettings: some View {
        Group {
            TextField("Chat base URL", text: $appState.customTranscriptCleanupBaseURL)
                .accessibilityIdentifier("settings.customTranscriptCleanupBaseURL")
            TextField("Chat model", text: $appState.customTranscriptCleanupModel)
                .accessibilityIdentifier("settings.customTranscriptCleanupModel")

            HStack {
                Button("Test cleanup connection") {
                    Task {
                        await appState.testSelectedCleanupProviderConnection()
                    }
                }
                .disabled(appState.cleanupConnectionTestState.isRunning)
                .accessibilityIdentifier("settings.testCleanupConnectionButton")

                cleanupConnectionStatus
            }

            Text("API key is optional. If your endpoint requires one, save it for custom cleanup before testing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.customCleanupHelp")

            SecureField("Optional cleanup API key", text: $customCleanupAPIKey)
                .accessibilityIdentifier("settings.customCleanupAPIKey")

            HStack {
                Button("Save cleanup key") {
                    saveCustomCleanupAPIKey()
                }
                .disabled(customCleanupAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("settings.saveCustomCleanupAPIKeyButton")

                Button("Delete cleanup key") {
                    KeychainHelper.deleteCleanupApiKey(for: .customOpenAICompatibleChat)
                    customCleanupAPIKey = ""
                }
                .accessibilityIdentifier("settings.deleteCustomCleanupAPIKeyButton")
            }
        }
    }

    private var selectedLocalWhisperSetupModel: LocalWhisperSetupModel {
        LocalWhisperSetupModel.option(id: selectedLocalWhisperSetupModelID)
    }

    private var providerPrivacySummary: String {
        switch appState.selectedTranscriptionProviderPresetID {
        case .groq:
            "Audio is sent to Groq for transcription. Optional cleanup uses Groq chat models when enabled."
        case .openAIWhisper:
            "Audio is sent to OpenAI for Whisper transcription. Cleanup is off unless you choose a separate custom chat endpoint."
        case .localWhisperCPP:
            "Audio stays on this Mac when whisper.cpp is running at the local 127.0.0.1 endpoint shown below."
        case .customOpenAICompatible:
            "Audio is sent to the OpenAI-compatible endpoint you configure below. Use an endpoint you trust."
        }
    }

    private var selectedLocalWhisperSetupCommands: LocalWhisperSetupCommands {
        LocalWhisperSetupCommands(model: selectedLocalWhisperSetupModel)
    }

    private var localWhisperSetupHelper: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Picker("Local model", selection: $selectedLocalWhisperSetupModelID) {
                ForEach(LocalWhisperSetupModel.all) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            .accessibilityIdentifier("settings.localWhisperSetupModelPicker")

            Text("\(selectedLocalWhisperSetupModel.languageScope). \(selectedLocalWhisperSetupModel.diskGuidance). \(selectedLocalWhisperSetupModel.performanceGuidance)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.localWhisperSetupModelGuidance")

            Text(selectedLocalWhisperSetupCommands.modelSelectionExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.localWhisperSetupModelExplanation")

            commandBlock(
                title: "Install whisper.cpp",
                command: selectedLocalWhisperSetupCommands.cloneCommand,
                identifier: "settings.localWhisperCloneCommand"
            )

            commandBlock(
                title: "Build server",
                command: selectedLocalWhisperSetupCommands.buildCommand,
                identifier: "settings.localWhisperBuildCommand"
            )

            commandBlock(
                title: "Download model",
                command: selectedLocalWhisperSetupCommands.downloadCommand,
                identifier: "settings.localWhisperDownloadCommand"
            )

            commandBlock(
                title: "Start server",
                command: selectedLocalWhisperSetupCommands.startServerCommand,
                identifier: "settings.localWhisperStartServerCommand"
            )
        }
    }

    private func commandBlock(title: String, command: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button("Copy") {
                    copyToPasteboard(command)
                }
                .accessibilityIdentifier("\(identifier).copyButton")
            }

            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(command)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copySetupReport() {
        if let onCopySetupReport {
            onCopySetupReport()
        } else {
            copyToPasteboard(DiagnosticLog.setupReportText(appState: appState))
        }
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

    @ViewBuilder
    private var cleanupConnectionStatus: some View {
        switch appState.cleanupConnectionTestState {
        case .idle:
            EmptyView()
        case .running:
            ProgressView()
                .controlSize(.small)
                .accessibilityIdentifier("settings.cleanupConnectionProgress")
        case .succeeded(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("settings.cleanupConnectionSucceeded")
        case .warning(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("settings.cleanupConnectionWarning")
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityIdentifier("settings.cleanupConnectionFailed")
        }
    }

    private func saveCustomCleanupAPIKey() {
        do {
            try KeychainHelper.saveCleanupApiKey(customCleanupAPIKey, for: .customOpenAICompatibleChat)
            customCleanupAPIKey = ""
        } catch {
            appState.cleanupConnectionTestState = .failed("Could not save cleanup API key: \(error.localizedDescription)")
        }
    }

    private var providerConnectionHelp: String {
        switch appState.selectedTranscriptionProviderPresetID {
        case .localWhisperCPP:
            "Start the local whisper-server first. If the test cannot reach it, copy the Start server command below and run it in Terminal."
        case .openAIWhisper:
            "Use Add API Key to save and test your OpenAI key before recording."
        case .customOpenAICompatible:
            "Use Test connection after changing the base URL or model. The server must expose /v1/audio/transcriptions."
        case .groq:
            ""
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
                Text("History is stored locally on this Mac. Successful audio files are deleted after transcription. Failed audio may be retained in Application Support only so you can retry it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                Button("Open App Data Folder") {
                    openAppDataFolder()
                }
                .accessibilityIdentifier("settings.openDataFolderButton")
            }

            Section("Support") {
                Button {
                    copySetupReport()
                } label: {
                    Label("Copy Setup Report", systemImage: "doc.on.clipboard")
                }
                .accessibilityIdentifier("settings.copySetupReportButton")

                Button {
                    onExportDiagnostics?()
                } label: {
                    Label("Export Diagnostics...", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("settings.exportDiagnosticsButton")
                .disabled(onExportDiagnostics == nil)
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

    private var whatsNewSettings: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ReleaseNotes.recent) { note in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(note.title)
                                    .font(.headline)
                                Text(note.date)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(note.highlights, id: \.self) { highlight in
                                    Label(highlight, systemImage: "checkmark.circle")
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .labelStyle(.titleAndIcon)
                                }
                            }
                        }
                        .accessibilityIdentifier("settings.whatsNew.release.\(note.id)")

                        if note.id != ReleaseNotes.recent.last?.id {
                            Divider()
                        }
                    }
                }
                .accessibilityIdentifier("settings.whatsNew.list")
            } header: {
                Text("What's New")
            } footer: {
                Text("Release notes are bundled with Foil and updated during release prep.")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.whatsNew")
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
                Toggle(ExperimentalCopy.queuedPasteTitle, isOn: $appState.queuedPasteEnabled)
                    .accessibilityIdentifier("settings.queuedPasteToggle")
                    .onChange(of: appState.queuedPasteEnabled) { _, _ in onHotkeyChanged?() }
                Text(ExperimentalCopy.queuedPasteDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if appState.queuedPasteEnabled {
                    Picker("Queue mode", selection: $appState.queuedPasteMode) {
                        ForEach(QueuedPasteMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("settings.queuedPasteModePicker")

                    Text("Delivery shortcut: \(appState.queuedPasteDeliveryShortcutLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.queuedPasteDeliveryShortcut")

                    if appState.queuedPasteDeliveryShortcutConflictsWithRecordingHotkey {
                        Label(ExperimentalCopy.queuedPasteShortcutConflict, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("settings.queuedPasteDeliveryShortcutConflict")
                    }
                }
                Toggle(ExperimentalCopy.backgroundPasteTitle, isOn: $appState.experimentalSkyLightPasteEnabled)
                    .accessibilityIdentifier("settings.experimentalSkyLightPasteToggle")
                Text(ExperimentalCopy.backgroundPasteDescription)
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
        let dir = appSupport.appendingPathComponent(AppBrand.applicationSupportDirectoryName, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}

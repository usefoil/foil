import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    enum Tab: Hashable, CaseIterable {
        case general
        case recording
        case transcription
        case cleanup
        case paste
        case privacy
        case whatsNew
        case experimental

        var title: String {
            switch self {
            case .general: "General"
            case .recording: "Recording"
            case .transcription: "Transcription"
            case .cleanup: "Cleanup"
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
            case .cleanup: "wand.and.stars"
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
            case .cleanup: "settings.tab.cleanup"
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
        static let localBridgeTitle = "Foil Local Bridge"
        static let localBridgeDescription = "Pairs an iPhone with this Mac for local bridge fixtures. No production credentials are shared."
        static let pairIPhoneTitle = "Pair iPhone"
        static let approveFixtureIPhoneTitle = "Approve fixture iPhone"
        static let runMockBridgeRequestTitle = "Run mock request"
        static let revokeIPhoneTitle = "Revoke iPhone"
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
    var usageEventStore: UsageEventStore
    var onHotkeyChanged: (() -> Void)?
    var onCopySetupReport: (() -> Void)?
    var onExportDiagnostics: (() -> Void)?
    var onStartLocalWhisperServer: ((LocalWhisperSetupModelID) -> Void)?
    var showsTabStrip: Bool
    var usesFixedFrame: Bool

    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: Tab
    @State private var isShowingClearHistoryConfirmation = false
    @State private var launchAtLoginManager = LaunchAtLoginManager()
    @State private var notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
    @State private var selectedLocalWhisperSetupModelID = LocalWhisperSetupModel.recommendedDefaultID
    @State private var openAICleanupAPIKey = ""
    @State private var customCleanupAPIKey = ""
    @State private var selectedCleanupGroupID = CleanupGroup.defaultGroupID
    @State private var usageMetricsRefreshCounter = 0
    @State private var vocabularyWrittenAs = ""
    @State private var vocabularyCorrectVersion = ""
    @State private var vocabularyNote = ""
    private var sparkleUpdater: SparkleUpdater { SparkleUpdater.shared }
    private let soundPreviewPlayer = SoundPlayer()

    init(
        appState: AppState,
        history: TranscriptionHistory,
        usageEventStore: UsageEventStore = UsageEventStore(),
        initialTab: Tab = .general,
        onHotkeyChanged: (() -> Void)? = nil,
        onCopySetupReport: (() -> Void)? = nil,
        onExportDiagnostics: (() -> Void)? = nil,
        onStartLocalWhisperServer: ((LocalWhisperSetupModelID) -> Void)? = nil,
        showsTabStrip: Bool = true,
        usesFixedFrame: Bool = true
    ) {
        self.appState = appState
        self.history = history
        self.usageEventStore = usageEventStore
        self.onHotkeyChanged = onHotkeyChanged
        self.onCopySetupReport = onCopySetupReport
        self.onExportDiagnostics = onExportDiagnostics
        self.onStartLocalWhisperServer = onStartLocalWhisperServer
        self.showsTabStrip = showsTabStrip
        self.usesFixedFrame = usesFixedFrame
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 14) {
            if showsTabStrip {
                settingsTabStrip
            }

            selectedSettingsPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsTabStrip {
                AppVersionFooter(accessibilityIdentifier: "settings.appVersionFooter")
            }
        }
        .accessibilityIdentifier("settings.root")
        .scenePadding()
        .frame(
            width: usesFixedFrame ? 760 : nil,
            height: usesFixedFrame ? 452 : nil
        )
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
        case .cleanup:
            cleanupSettings
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
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(AppBrand.succinctVersionDisplay)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .accessibilityIdentifier("settings.general.versionRow")
            }

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

                checkForUpdatesButton(accessibilityIdentifier: "settings.general.checkForUpdatesButton")
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
                if let missingSelectedInputDeviceUID {
                    Text("Unavailable microphone").tag(Optional(missingSelectedInputDeviceUID))
                }
                ForEach(availableInputDevices) { device in
                    Text(device.name).tag(Optional(device.uid))
                }
            }
            .accessibilityIdentifier("settings.inputDevicePicker")

            if availableInputDevices.isEmpty {
                Label {
                    Text("No microphone detected. Connect an input device, then reopen Recording settings or run Test Setup.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("settings.noMicrophoneDetected")
            } else if missingSelectedInputDeviceUID != nil {
                Label {
                    Text("The previously selected microphone is unavailable. Foil will use a safe available input for recording when possible.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("settings.selectedInputUnavailable")
            }

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

    private var missingSelectedInputDeviceUID: String? {
        guard let uid = appState.selectedInputDeviceUID else { return nil }
        return availableInputDevices.contains { $0.uid == uid } ? nil : uid
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

            if appState.selectedTranscriptionProviderPresetID == .localWhisperCPP {
                Section("Local Server") {
                    providerConnectionTestRow
                    Text(providerConnectionHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.providerConnectionHelp")
                }
            } else {
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
                        providerConnectionTestRow
                        Text(providerConnectionHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.providerConnectionHelp")
                    }
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
                    Text("Install whisper.cpp, download a model, then start whisper-server on 127.0.0.1:8080 with --inference-path /v1/audio/transcriptions. Foil sends this local preset without credentials.")
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

        }
        .formStyle(.grouped)
    }

    private var cleanupSettings: some View {
        HStack(alignment: .top, spacing: 14) {
            cleanupGroupList

            Divider()

            ScrollView {
                cleanupGroupDetail
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
            }
        }
        .accessibilityIdentifier("settings.cleanupGroups.root")
        .onAppear {
            ensureSelectedCleanupGroupExists()
        }
        .onChange(of: appState.cleanupGroups.map(\.id)) { _, _ in
            ensureSelectedCleanupGroupExists()
        }
    }

    private var cleanupGroupList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Groups")
                    .font(.headline)
                Spacer()
                Button {
                    let group = appState.createCleanupGroup(named: uniqueCleanupGroupName())
                    selectedCleanupGroupID = group.id
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add cleanup group")
                .accessibilityLabel("Add cleanup group")
                .accessibilityIdentifier("settings.cleanupGroups.addGroupButton")
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(appState.cleanupGroups) { group in
                    Button {
                        selectedCleanupGroupID = group.id
                    } label: {
                        cleanupGroupListRow(group)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.cleanupGroups.groupRow.\(group.id)")
                }
            }

            HStack(spacing: 8) {
                Button {
                    moveSelectedCleanupGroup(delta: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveSelectedCleanupGroup(delta: -1))
                .help("Move group up")
                .accessibilityLabel("Move group up")
                .accessibilityIdentifier("settings.cleanupGroups.moveUpButton")

                Button {
                    moveSelectedCleanupGroup(delta: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveSelectedCleanupGroup(delta: 1))
                .help("Move group down")
                .accessibilityLabel("Move group down")
                .accessibilityIdentifier("settings.cleanupGroups.moveDownButton")

                Spacer()

                Button(role: .destructive) {
                    guard appState.deleteCleanupGroup(id: selectedCleanupGroupID) else { return }
                    selectedCleanupGroupID = CleanupGroup.defaultGroupID
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedCleanupGroup.isDefault)
                .help("Delete cleanup group")
                .accessibilityLabel("Delete cleanup group")
                .accessibilityIdentifier("settings.cleanupGroups.deleteGroupButton")
            }
            .buttonStyle(.borderless)

            Text("Default handles apps that are not assigned to another group.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 218, alignment: .topLeading)
    }

    private func cleanupGroupListRow(_ group: CleanupGroup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: group.isDefault ? "tray" : "rectangle.stack")
                .foregroundStyle(group.id == selectedCleanupGroupID ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.callout.weight(group.id == selectedCleanupGroupID ? .semibold : .regular))
                    .lineLimit(1)
                Text(cleanupGroupSummary(group))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if group.id == selectedCleanupGroupID {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
            }
        }
    }

    private var cleanupGroupDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            cleanupGroupHeader(selectedCleanupGroup)

            Divider()

            cleanupGroupProcessingSettings(selectedCleanupGroup)

            if selectedCleanupGroup.processingMode.usesCleanupProvider {
                cleanupGroupProviderSettings(selectedCleanupGroup)
                cleanupGroupPromptSettings(selectedCleanupGroup)
            }

            cleanupGroupAppMembership(selectedCleanupGroup)

            Divider()

            vocabularySettings(isCleanupEnabled: selectedCleanupGroup.processingMode.usesCleanupProvider)
        }
        .accessibilityIdentifier("settings.cleanupGroups.detail")
    }

    private func cleanupGroupHeader(_ group: CleanupGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if group.isDefault {
                LabeledContent("Name", value: group.name)
                    .accessibilityIdentifier("settings.cleanupGroups.defaultName")
            } else {
                TextField("Group name", text: cleanupGroupNameBinding(group.id))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("settings.cleanupGroups.nameField")
            }

            Toggle("Enabled", isOn: cleanupGroupEnabledBinding(group.id))
                .disabled(group.isDefault)
                .accessibilityIdentifier("settings.cleanupGroups.enabledToggle")

            Text(group.isDefault ? "Applies when the recording app is not assigned to another group." : "Applies when one of this group's apps is the recording target.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cleanupGroupProcessingSettings(_ group: CleanupGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cleanup")
                .font(.headline)
            Picker("Mode", selection: cleanupGroupModeBinding(group.id)) {
                ForEach(TranscriptProcessingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .accessibilityIdentifier("settings.cleanupGroups.modePicker")

            Text(group.processingMode.activeModeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.cleanupGroups.modeDescription")
        }
    }

    @ViewBuilder
    private func cleanupGroupProviderSettings(_ group: CleanupGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider")
                .font(.headline)
            Picker("Cleanup provider", selection: cleanupGroupProviderBinding(group.id)) {
                ForEach(availableCleanupProviderIDs) { providerID in
                    Text(providerID.displayName).tag(providerID)
                }
            }
            .accessibilityIdentifier("settings.cleanupGroups.providerPicker")

            switch group.cleanupProviderID {
            case .groq:
                Picker("Model", selection: cleanupGroupModelBinding(group.id)) {
                    Text("Llama 3.1 8B Instant").tag("llama-3.1-8b-instant")
                    Text("Llama 3.3 70B Versatile").tag("llama-3.3-70b-versatile")
                }
                .accessibilityIdentifier("settings.cleanupGroups.groqModelPicker")
            case .openAI:
                Picker("Model", selection: cleanupGroupModelBinding(group.id)) {
                    Text("GPT-5.4 mini").tag("gpt-5.4-mini")
                    Text("GPT-5.4").tag("gpt-5.4")
                    Text("GPT-5.5").tag("gpt-5.5")
                }
                .accessibilityIdentifier("settings.cleanupGroups.openAIModelPicker")
                cleanupOpenAIKeySettings
            case .customOpenAICompatibleChat:
                TextField("Chat base URL", text: cleanupGroupBaseURLBinding(group.id))
                    .accessibilityIdentifier("settings.cleanupGroups.customBaseURLField")
                TextField("Chat model", text: cleanupGroupModelBinding(group.id))
                    .accessibilityIdentifier("settings.cleanupGroups.customModelField")
                cleanupCustomKeySettings
            case .none:
                Text("This group will paste raw transcripts until a cleanup provider is selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.cleanupGroups.noProviderHelp")
            }
        }
    }

    private func cleanupGroupPromptSettings(_ group: CleanupGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Prompt")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    appState.updateCleanupGroup(id: group.id) { updatedGroup in
                        updatedGroup.customPrompt = nil
                    }
                }
                .accessibilityIdentifier("settings.cleanupGroups.resetPromptButton")
            }

            TextEditor(text: cleanupGroupPromptBinding(group.id))
                .font(.body)
                .frame(minHeight: 92)
                .accessibilityIdentifier("settings.cleanupGroups.promptEditor")
        }
    }

    private func cleanupGroupAppMembership(_ group: CleanupGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Apps")
                    .font(.headline)
                Spacer()
                Button {
                    chooseAppForCleanupGroup(group.id)
                } label: {
                    Label("Choose .app...", systemImage: "folder")
                }
                .accessibilityIdentifier("settings.cleanupGroups.chooseAppButton")
            }

            if group.isDefault {
                Text("Unassigned apps use this group automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.cleanupGroups.defaultAppsHelp")
            } else {
                cleanupGroupAssignedApps(group)
                recentAppsPicker(group)
                runningAppsPicker(group)
            }
        }
    }

    @ViewBuilder
    private func cleanupGroupAssignedApps(_ group: CleanupGroup) -> some View {
        if group.appMatchers.isEmpty {
            Text("No apps assigned.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.cleanupGroups.emptyApps")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.appMatchers) { matcher in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(matcher.displayName)
                                .font(.callout)
                                .lineLimit(1)
                            Text(appMatcherDetail(matcher))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            if let membershipKey = matcher.membershipKey {
                                appState.removeAppMatcher(membershipKey: membershipKey, fromCleanupGroupID: group.id)
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(matcher.displayName)")
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("settings.cleanupGroups.assignedAppRow")
                }
            }
        }
    }

    private func recentAppsPicker(_ group: CleanupGroup) -> some View {
        return VStack(alignment: .leading, spacing: 6) {
            Text("Recently used apps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if recentAppCandidates.isEmpty {
                Text("No recent apps yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.cleanupGroups.emptyRecentApps")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(recentAppCandidates.prefix(12)) { candidate in
                            cleanupAppCandidateRow(
                                candidate,
                                group: group,
                                addButtonIdentifier: "settings.cleanupGroups.recentAppAddButton.\(candidate.id)"
                            )
                        }
                    }
                }
                .frame(maxHeight: 126)
            }
        }
        .accessibilityIdentifier("settings.cleanupGroups.recentApps")
    }

    private func runningAppsPicker(_ group: CleanupGroup) -> some View {
        let recentCandidateIDs = Set(recentAppCandidates.map(\.id))
        let candidates = runningAppCandidates.filter { !recentCandidateIDs.contains($0.id) }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Running apps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if candidates.isEmpty {
                Text("No running apps available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(candidates.prefix(12)) { candidate in
                            cleanupAppCandidateRow(
                                candidate,
                                group: group,
                                addButtonIdentifier: "settings.cleanupGroups.runningAppAddButton.\(candidate.id)"
                            )
                        }
                    }
                }
                .frame(maxHeight: 126)
            }
        }
        .accessibilityIdentifier("settings.cleanupGroups.runningApps")
    }

    private func cleanupAppCandidateRow(
        _ candidate: CleanupAppCandidate,
        group: CleanupGroup,
        addButtonIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName)
                    .font(.callout)
                    .lineLimit(1)
                Text(candidate.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Add") {
                appState.addAppMatcher(candidate.matcher, toCleanupGroupID: group.id)
            }
            .disabled(group.appMatchers.contains { $0.membershipKey == candidate.matcher.membershipKey })
            .accessibilityIdentifier(addButtonIdentifier)
        }
    }

    private var cleanupOpenAIKeySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("OpenAI API key", text: $openAICleanupAPIKey)
                .accessibilityIdentifier("settings.cleanupGroups.openAIAPIKey")
            HStack {
                Button("Save OpenAI key") {
                    saveOpenAICleanupAPIKey()
                }
                .disabled(openAICleanupAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("settings.cleanupGroups.saveOpenAIAPIKeyButton")

                Button("Delete OpenAI key") {
                    KeychainHelper.delete(for: .openAI)
                    openAICleanupAPIKey = ""
                }
                .accessibilityIdentifier("settings.cleanupGroups.deleteOpenAIAPIKeyButton")
            }
        }
    }

    private var cleanupCustomKeySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("Optional cleanup API key", text: $customCleanupAPIKey)
                .accessibilityIdentifier("settings.cleanupGroups.customAPIKey")
            HStack {
                Button("Save cleanup key") {
                    saveCustomCleanupAPIKey()
                }
                .disabled(customCleanupAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("settings.cleanupGroups.saveCustomAPIKeyButton")

                Button("Delete cleanup key") {
                    KeychainHelper.deleteCleanupApiKey(for: .customOpenAICompatibleChat)
                    customCleanupAPIKey = ""
                }
                .accessibilityIdentifier("settings.cleanupGroups.deleteCustomAPIKeyButton")
            }
        }
    }

    private var availableCleanupProviderIDs: [TranscriptCleanupProviderID] {
        [.groq, .openAI, .none, .customOpenAICompatibleChat]
    }

    private var selectedCleanupGroup: CleanupGroup {
        appState.cleanupGroups.first { $0.id == selectedCleanupGroupID }
            ?? appState.defaultCleanupGroup
    }

    private func ensureSelectedCleanupGroupExists() {
        guard !appState.cleanupGroups.contains(where: { $0.id == selectedCleanupGroupID }) else { return }
        selectedCleanupGroupID = appState.defaultCleanupGroup.id
    }

    private func uniqueCleanupGroupName() -> String {
        let baseName = "New group"
        let existingNames = Set(appState.cleanupGroups.map { $0.name.lowercased() })
        guard existingNames.contains(baseName.lowercased()) else { return baseName }
        var suffix = 2
        while existingNames.contains("\(baseName) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }

    private func cleanupGroupSummary(_ group: CleanupGroup) -> String {
        let mode = group.processingMode == .raw ? "Raw" : group.cleanupProviderID.displayName
        let appCount = group.isDefault ? "unassigned apps" : "\(group.appMatchers.count) apps"
        return "\(mode) · \(appCount)"
    }

    private func cleanupGroupNameBinding(_ groupID: String) -> Binding<String> {
        Binding(
            get: { appState.cleanupGroups.first { $0.id == groupID }?.name ?? "" },
            set: { name in
                appState.updateCleanupGroup(id: groupID) { group in
                    group.name = name
                }
            }
        )
    }

    private func cleanupGroupEnabledBinding(_ groupID: String) -> Binding<Bool> {
        Binding(
            get: { appState.cleanupGroups.first { $0.id == groupID }?.isEnabled ?? true },
            set: { isEnabled in
                appState.updateCleanupGroup(id: groupID) { group in
                    group.isEnabled = group.isDefault ? true : isEnabled
                }
            }
        )
    }

    private func cleanupGroupModeBinding(_ groupID: String) -> Binding<TranscriptProcessingMode> {
        Binding(
            get: { appState.cleanupGroups.first { $0.id == groupID }?.processingMode ?? .raw },
            set: { mode in
                appState.updateCleanupGroup(id: groupID) { group in
                    group.processingMode = mode.normalizedActiveMode
                    if group.processingMode.usesCleanupProvider, group.cleanupProviderID == .none {
                        group.cleanupProviderID = .groq
                        group.cleanupModel = appState.defaultCleanupModel(for: .groq)
                    }
                }
            }
        )
    }

    private func cleanupGroupProviderBinding(_ groupID: String) -> Binding<TranscriptCleanupProviderID> {
        Binding(
            get: { appState.cleanupGroups.first { $0.id == groupID }?.cleanupProviderID ?? .groq },
            set: { providerID in
                appState.updateCleanupGroup(id: groupID) { group in
                    group.cleanupProviderID = providerID
                    group.cleanupModel = appState.defaultCleanupModel(for: providerID)
                    group.customCleanupBaseURL = providerID == .customOpenAICompatibleChat
                        ? group.customCleanupBaseURL ?? appState.customTranscriptCleanupBaseURL
                        : nil
                }
            }
        )
    }

    private func cleanupGroupModelBinding(_ groupID: String) -> Binding<String> {
        Binding(
            get: { appState.cleanupGroups.first { $0.id == groupID }?.cleanupModel ?? "" },
            set: { model in
                appState.updateCleanupGroup(id: groupID) { group in
                    group.cleanupModel = model
                }
            }
        )
    }

    private func cleanupGroupBaseURLBinding(_ groupID: String) -> Binding<String> {
        Binding(
            get: { appState.cleanupGroups.first { $0.id == groupID }?.customCleanupBaseURL ?? "" },
            set: { baseURL in
                appState.updateCleanupGroup(id: groupID) { group in
                    group.customCleanupBaseURL = baseURL
                }
            }
        )
    }

    private func cleanupGroupPromptBinding(_ groupID: String) -> Binding<String> {
        Binding(
            get: {
                let group = appState.cleanupGroups.first { $0.id == groupID }
                let trimmedPrompt = group?.customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmedPrompt.isEmpty ? TranscriptProcessingMode.cleanUp.defaultPrompt : trimmedPrompt
            },
            set: { prompt in
                appState.updateCleanupGroup(id: groupID) { group in
                    group.customPrompt = prompt
                }
            }
        )
    }

    private func canMoveSelectedCleanupGroup(delta: Int) -> Bool {
        guard !selectedCleanupGroup.isDefault else { return false }
        let nonDefaultIDs = appState.cleanupGroups
            .filter { !$0.isDefault }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.id)
        guard let index = nonDefaultIDs.firstIndex(of: selectedCleanupGroupID) else { return false }
        return nonDefaultIDs.indices.contains(index + delta)
    }

    private func moveSelectedCleanupGroup(delta: Int) {
        guard !selectedCleanupGroup.isDefault else { return }
        let nonDefaultIDs = appState.cleanupGroups
            .filter { !$0.isDefault }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.id)
        guard let index = nonDefaultIDs.firstIndex(of: selectedCleanupGroupID) else { return }
        appState.moveCleanupGroup(id: selectedCleanupGroupID, toNonDefaultIndex: index + delta)
    }

    private var runningAppCandidates: [CleanupAppCandidate] {
        var candidates: [CleanupAppCandidate] = []
        var seenKeys: Set<String> = []
        for application in NSWorkspace.shared.runningApplications where application.activationPolicy == .regular {
            guard let candidate = CleanupAppCandidate(application: application),
                  seenKeys.insert(candidate.id).inserted else {
                continue
            }
            candidates.append(candidate)
        }
        return candidates.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var recentAppCandidates: [CleanupAppCandidate] {
        var candidates: [CleanupAppCandidate] = []
        var seenKeys: Set<String> = []
        for topApp in usageEventStore.topApps(limit: 24) {
            guard let candidate = CleanupAppCandidate(topApp: topApp),
                  seenKeys.insert(candidate.id).inserted else {
                continue
            }
            candidates.append(candidate)
        }
        return candidates
    }

    private func chooseAppForCleanupGroup(_ groupID: String) {
        let panel = NSOpenPanel()
        panel.title = "Choose app"
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let appURL = panel.url else { return }
        let displayName = appDisplayName(for: appURL)
        let matcher = CleanupAppMatcher(
            displayName: displayName,
            bundleIdentifier: Bundle(url: appURL)?.bundleIdentifier,
            appPath: appURL.path
        )
        appState.addAppMatcher(matcher, toCleanupGroupID: groupID)
    }

    private func appDisplayName(for appURL: URL) -> String {
        let bundle = Bundle(url: appURL)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let fileName = appURL.deletingPathExtension().lastPathComponent
        return [displayName, bundleName, fileName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Selected app"
    }

    private func appMatcherDetail(_ matcher: CleanupAppMatcher) -> String {
        [matcher.bundleIdentifier, matcher.appPath]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func vocabularySettings(isCleanupEnabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Vocabulary")
                    .font(.headline)
                    .accessibilityIdentifier("settings.vocabularySection")
                Text(vocabularyHelpText(isCleanupEnabled: isCleanupEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.vocabularyHelp")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Foil wrote", text: $vocabularyWrittenAs)
                        .accessibilityIdentifier("settings.vocabularyCorrectionWrittenAs")
                    TextField("Use this instead", text: $vocabularyCorrectVersion)
                        .accessibilityIdentifier("settings.vocabularyCorrectionCorrectVersion")
                }

                TextField("Optional note", text: $vocabularyNote)
                    .accessibilityIdentifier("settings.vocabularyCorrectionNote")

                Button {
                    guard appState.addVocabularyCorrection(
                        writtenAs: vocabularyWrittenAs,
                        correctVersion: vocabularyCorrectVersion,
                        note: vocabularyNote
                    ) != nil else {
                        return
                    }
                    vocabularyWrittenAs = ""
                    vocabularyCorrectVersion = ""
                    vocabularyNote = ""
                } label: {
                    Label("Add correction", systemImage: "plus")
                }
                .disabled(vocabularyWrittenAs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vocabularyCorrectVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("settings.addVocabularyCorrectionButton")
            }

            if appState.vocabularyCorrections.isEmpty {
                Text("No corrections yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.vocabularyCorrectionsEmpty")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appState.vocabularyCorrections) { correction in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(correction.writtenAs) -> \(correction.correctVersion)")
                                    .font(.callout)
                                    .lineLimit(2)
                                if let note = correction.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer()

                            Button(role: .destructive) {
                                appState.deleteVocabularyCorrection(id: correction.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete vocabulary correction")
                            .accessibilityIdentifier("settings.deleteVocabularyCorrectionButton")
                        }
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("settings.vocabularyCorrectionRow")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Preferred terms")
                TextEditor(text: $appState.preferredTermsText)
                    .font(.body)
                    .frame(minHeight: 72)
                    .accessibilityIdentifier("settings.preferredTermsEditor")
            }
        }
    }

    private func vocabularyHelpText(isCleanupEnabled: Bool) -> String {
        if isCleanupEnabled {
            return "Corrections teach Cleanup what Foil wrote and what it should use instead. Preferred terms tell Cleanup which names and phrases to preserve."
        }
        return "Vocabulary is saved now and applied when you choose Cleanup profile. Corrections teach Cleanup replacements; preferred terms tell it which names and phrases to preserve."
    }

    private var selectedLocalWhisperSetupModel: LocalWhisperSetupModel {
        LocalWhisperSetupModel.option(id: selectedLocalWhisperSetupModelID)
    }

    private var providerPrivacySummary: String {
        switch appState.selectedTranscriptionProviderPresetID {
        case .groq:
            "Audio is sent to Groq for transcription. Raw transcript is the default; Cleanup profile sends transcript text to the cleanup provider selected below."
        case .openAIWhisper:
            "Audio is sent to OpenAI for Whisper transcription. Raw transcript is the default; Cleanup profile sends transcript text to the cleanup provider selected below."
        case .localWhisperCPP:
            "Audio stays on this Mac when whisper.cpp is running at the local 127.0.0.1 endpoint shown below. Raw transcript is the default; Cleanup profile sends transcript text to the cleanup provider selected below."
        case .customOpenAICompatible:
            "Audio is sent to the OpenAI-compatible endpoint you configure below. Raw transcript is the default; Cleanup profile sends transcript text to the cleanup provider selected below."
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

            localWhisperServerControl

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

    private var localWhisperServerControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    onStartLocalWhisperServer?(selectedLocalWhisperSetupModelID)
                } label: {
                    Label("Start server", systemImage: "play.fill")
                }
                .disabled(appState.localWhisperServerState.isStarting || onStartLocalWhisperServer == nil)
                .accessibilityIdentifier("settings.localWhisperStartServerButton")

                localWhisperServerStatus
            }

            Text("Starts the already-built local whisper-server with the selected downloaded model. Foil will not install, build, clone, or download files automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.localWhisperStartServerHelp")
        }
    }

    @ViewBuilder
    private var localWhisperServerStatus: some View {
        switch appState.localWhisperServerState {
        case .idle:
            Text("Not started from Foil")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.localWhisperServerStatus")
        case .starting(let modelName):
            ProgressView("Starting \(modelName)...")
                .controlSize(.small)
                .accessibilityIdentifier("settings.localWhisperServerStatus")
        case .running(let baseURL):
            Label("Running at \(baseURL)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("settings.localWhisperServerStatus")
        case .alreadyRunning(let baseURL):
            Label("Already reachable at \(baseURL)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("settings.localWhisperServerStatus")
        case .missingBinary(let path):
            Label("Missing whisper-server at \(path)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityIdentifier("settings.localWhisperServerStatus")
        case .missingModel(let path):
            Label("Missing model at \(URL(fileURLWithPath: path).lastPathComponent)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityIdentifier("settings.localWhisperServerStatus")
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityIdentifier("settings.localWhisperServerStatus")
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

    private var providerConnectionTestRow: some View {
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

    private func saveCustomCleanupAPIKey() {
        do {
            try KeychainHelper.saveCleanupApiKey(customCleanupAPIKey, for: .customOpenAICompatibleChat)
            customCleanupAPIKey = ""
        } catch {
            appState.cleanupConnectionTestState = .failed("Could not save cleanup API key: \(error.localizedDescription)")
        }
    }

    private func saveOpenAICleanupAPIKey() {
        do {
            try KeychainHelper.save(apiKey: openAICleanupAPIKey, for: .openAI)
            openAICleanupAPIKey = ""
        } catch {
            appState.cleanupConnectionTestState = .failed("Could not save OpenAI API key: \(error.localizedDescription)")
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
            Section("Usage Metrics") {
                Toggle("Collect usage metrics", isOn: usageMetricsBinding)
                    .accessibilityIdentifier("settings.usageMetricsToggle")
                LabeledContent("Retained usage sessions", value: "\(usageMetricsSummary.totalSessions)")
                    .accessibilityIdentifier("settings.usageMetricsRetainedSessions")
                Text("Usage metrics store local word counts, session counts, and app names for Insights. This control is separate from transcript history retention.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.usageMetricsHelp")
                Button("Delete Usage Metrics", action: deleteUsageMetrics)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.deleteUsageMetricsButton")
                    .disabled(usageMetricsSummary.totalSessions == 0)
            }

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

    private var usageMetricsBinding: Binding<Bool> {
        Binding(
            get: { appState.usageMetricsEnabled },
            set: { enabled in
                appState.usageMetricsEnabled = enabled
                usageEventStore.isEnabled = enabled
                usageMetricsRefreshCounter += 1
            }
        )
    }

    private func deleteUsageMetrics() {
        _ = usageEventStore.deleteAll()
        usageMetricsRefreshCounter += 1
    }

    private var usageMetricsSummary: UsageSummary {
        _ = usageMetricsRefreshCounter
        return usageEventStore.summary()
    }

    private var whatsNewSettings: some View {
        Form {
            Section("Current Version") {
                HStack(alignment: .firstTextBaseline) {
                    Text("Installed")
                    Spacer()
                    Text(AppBrand.succinctVersionDisplay)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("settings.whatsNew.versionText")

                    checkForUpdatesButton(accessibilityIdentifier: "settings.whatsNew.checkForUpdatesButton")
                }
            }

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

    private func checkForUpdatesButton(accessibilityIdentifier: String) -> some View {
        Button("Check for Updates…") {
            sparkleUpdater.checkForUpdates()
        }
        .disabled(!sparkleUpdater.canCheckForUpdates)
        .accessibilityIdentifier(accessibilityIdentifier)
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

            Section("Local Bridge") {
                Toggle(ExperimentalCopy.localBridgeTitle, isOn: $appState.localBridgeEnabled)
                    .accessibilityIdentifier("settings.localBridgeToggle")
                Text(ExperimentalCopy.localBridgeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.localBridgeDescription")

                HStack {
                    Button(ExperimentalCopy.pairIPhoneTitle) {
                        appState.beginLocalBridgePairing()
                    }
                    .disabled(!appState.localBridgeEnabled)
                    .accessibilityIdentifier("settings.localBridgePairIPhoneButton")

                    Button(ExperimentalCopy.approveFixtureIPhoneTitle) {
                        appState.approveFixtureLocalBridgePairing()
                    }
                    .disabled(!appState.localBridgeEnabled || appState.localBridgePairingSession == nil)
                    .accessibilityIdentifier("settings.localBridgeApproveFixtureButton")

                    Button(ExperimentalCopy.revokeIPhoneTitle, role: .destructive) {
                        appState.revokeLocalBridgePairing()
                    }
                    .disabled(!appState.localBridgeEnabled || appState.localBridgeTrustedPeer == nil)
                    .accessibilityIdentifier("settings.localBridgeRevokeButton")

                    Button(ExperimentalCopy.runMockBridgeRequestTitle) {
                        appState.runFixtureLocalBridgeTranscription()
                    }
                    .disabled(!appState.localBridgeEnabled)
                    .accessibilityIdentifier("settings.localBridgeMockRequestButton")
                }

                LabeledContent("State", value: appState.localBridgePairingState.rawValue)
                    .accessibilityIdentifier("settings.localBridgePairingState")
                LabeledContent("Status", value: appState.localBridgeStatusMessage)
                    .accessibilityIdentifier("settings.localBridgeStatus")

                if let session = appState.localBridgePairingSession {
                    LabeledContent("Code", value: session.code)
                        .accessibilityIdentifier("settings.localBridgePairingCode")
                    LabeledContent("Candidate", value: "Fixture iPhone")
                        .accessibilityIdentifier("settings.localBridgePairingCandidate")
                }

                if let payload = appState.localBridgePairingPayloadText {
                    HStack(alignment: .top, spacing: 12) {
                        if let qrCode = Self.qrCodeImage(from: payload) {
                            Image(nsImage: qrCode)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .accessibilityIdentifier("settings.localBridgePairingQRCode")
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pairing payload")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(payload)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityIdentifier("settings.localBridgePairingPayload")
                }

                if let trustedPeer = appState.localBridgeTrustedPeer {
                    LabeledContent("Trusted iPhone", value: trustedPeer.displayName)
                        .accessibilityIdentifier("settings.localBridgeTrustedPeer")
                }

                if let receipt = appState.localBridgeLastReceipt {
                    LabeledContent("Route", value: receipt.routeID.rawValue)
                        .accessibilityIdentifier("settings.localBridgeReceiptRoute")
                    LabeledContent("Audio to cloud", value: receipt.audioReachedCloudProvider ? "yes" : "no")
                        .accessibilityIdentifier("settings.localBridgeReceiptAudioCloud")
                }
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

    private static func qrCodeImage(from payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let representation = NSCIImageRep(ciImage: scaledImage)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
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

private struct CleanupAppCandidate: Identifiable {
    let id: String
    let displayName: String
    let detail: String
    let matcher: CleanupAppMatcher

    init?(application: NSRunningApplication) {
        let displayName = (application.localizedName ?? application.bundleURL?.deletingPathExtension().lastPathComponent ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleIdentifier = application.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let appPath = application.bundleURL?.path.trimmingCharacters(in: .whitespacesAndNewlines)
        let matcher = CleanupAppMatcher(
            displayName: displayName.isEmpty ? bundleIdentifier ?? appPath ?? "Running app" : displayName,
            bundleIdentifier: bundleIdentifier,
            appPath: appPath
        )
        guard let normalizedMatcher = matcher.normalized(),
              let membershipKey = normalizedMatcher.membershipKey else {
            return nil
        }
        self.id = membershipKey
        self.displayName = normalizedMatcher.displayName
        self.detail = [normalizedMatcher.bundleIdentifier, normalizedMatcher.appPath]
            .compactMap { $0 }
            .joined(separator: " · ")
        self.matcher = normalizedMatcher
    }

    init?(topApp: UsageTopApp) {
        let matcher = CleanupAppMatcher(
            displayName: topApp.displayName,
            bundleIdentifier: topApp.bundleIdentifier
        )
        guard let normalizedMatcher = matcher.normalized(),
              let membershipKey = normalizedMatcher.membershipKey else {
            return nil
        }
        self.id = membershipKey
        self.displayName = normalizedMatcher.displayName
        self.detail = normalizedMatcher.bundleIdentifier ?? "Usage metrics"
        self.matcher = normalizedMatcher
    }
}

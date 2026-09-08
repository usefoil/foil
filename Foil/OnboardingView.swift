import AppKit
import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    var onOpenAccessibility: (() -> Void)?
    var onOpenMicrophone: (() -> Void)?
    var onCheckMicrophone: (() -> Void)?
    var onRefreshSetupHealth: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onComplete: () -> Void
    var onDefer: (() -> Void)?
    var onStartLocalServer: ((LocalWhisperSetupModelID) -> Void)?
    var onStartPractice: (() -> Void)?
    var onStopPractice: (() -> Void)?
    var onEndPractice: (() -> Void)?
    var onPracticeStepChanged: ((Bool) -> Void)?
    var onHotkeyChanged: (() -> Void)?

    @State private var currentStep: Int = 0
    @State private var apiKey = ""
    @State private var credentialError: String?
    @State private var isChecking = false
    @State private var connectionChecked = false
    @State private var connectionMessage: String?

    private let steps = ["Transcription", "Configuration", "Insertion access", "Microphone", "First dictation", "Try another app"]

    init(
        appState: AppState,
        onOpenAccessibility: (() -> Void)? = nil,
        onOpenMicrophone: (() -> Void)? = nil,
        onCheckMicrophone: (() -> Void)? = nil,
        onRefreshSetupHealth: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onComplete: @escaping () -> Void,
        initialStep: Int = 0,
        onDefer: (() -> Void)? = nil,
        onStartLocalServer: ((LocalWhisperSetupModelID) -> Void)? = nil,
        onStartPractice: (() -> Void)? = nil,
        onStopPractice: (() -> Void)? = nil,
        onEndPractice: (() -> Void)? = nil,
        onPracticeStepChanged: ((Bool) -> Void)? = nil,
        onHotkeyChanged: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.onOpenAccessibility = onOpenAccessibility
        self.onOpenMicrophone = onOpenMicrophone
        self.onCheckMicrophone = onCheckMicrophone
        self.onRefreshSetupHealth = onRefreshSetupHealth
        self.onOpenSettings = onOpenSettings
        self.onComplete = onComplete
        self.onDefer = onDefer
        self.onStartLocalServer = onStartLocalServer
        self.onStartPractice = onStartPractice
        self.onStopPractice = onStopPractice
        self.onEndPractice = onEndPractice
        self.onPracticeStepChanged = onPracticeStepChanged
        self.onHotkeyChanged = onHotkeyChanged
        _currentStep = State(initialValue: min(max(initialStep, 0), steps.count - 1))
    }

    var body: some View {
        FoilSetupSurface(width: 580, minHeight: 500) {
            VStack(alignment: .leading, spacing: 18) {
                header
                stepIndicator

                ScrollView {
                FoilSetupPanel {
                    Group {
                        switch currentStep {
                        case 0:
                            providerStep
                        case 1:
                            credentialStep
                        case 2:
                            accessibilityStep
                        case 3:
                            microphoneStep
                        case 4:
                            practiceStep
                        case 5:
                            insertionStep
                        default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 208, alignment: .top)
                }

                }
                .frame(minHeight: 270, maxHeight: 400)
                navigationBar
            }
        }
        .accessibilityIdentifier("onboarding.root")
        .onAppear {
            onRefreshSetupHealth?()
            onPracticeStepChanged?(currentStep == 4)
        }
        .onDisappear { onEndPractice?() }
        .onChange(of: currentStep) { _, step in
            appState.onboardingStep = step
            onPracticeStepChanged?(step == 4)
            switch step {
            case 2:
                onRefreshSetupHealth?()
            case 3:
                onRefreshSetupHealth?()
            default:
                break
            }
        }
        .onChange(of: appState.selectedTranscriptionProviderPresetID) { _, _ in
            appState.refreshApiKeyState()
            connectionChecked = false
            connectionMessage = nil
            credentialError = nil
            apiKey = ""
            appState.onboardingTranscript = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .foilOnboardingUITestCommandRelay)) { notification in
            guard let command = OnboardingUITestCommand(notification: notification) else { return }
            handleUITestOnboardingCommand(command)
        }
    }

    // MARK: - Step Views

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(
                title: "Dictate on this Mac",
                description: "Local transcription is recommended: no account or API key. Download and set up a model once, then dictate offline. Cloud providers are available below.",
                systemImage: "waveform.path.ecg"
            )

            Picker("Provider", selection: $appState.selectedTranscriptionProviderPresetID) {
                Text("Groq").tag(TranscriptionProviderPresetID.groq)
                Text("OpenAI Whisper").tag(TranscriptionProviderPresetID.openAIWhisper)
                Text("On this Mac — recommended").tag(TranscriptionProviderPresetID.localWhisperCPP)
                Text("Custom OpenAI-compatible").tag(TranscriptionProviderPresetID.customOpenAICompatible)
            }
            .frame(maxWidth: 300, alignment: .leading)
            .accessibilityIdentifier("onboarding.providerPicker")
            .disabled(isChecking)

            Text(providerPrivacySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.providerPrivacySummary")
        }
    }

    private var credentialStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if appState.selectedTranscriptionProvider.requiresAPIKey {
                stepHeading(title: "Connect \(appState.selectedTranscriptionProvider.displayName)",
                            description: appState.selectedTranscriptionProviderID.credentialInstructions,
                            systemImage: "key.fill")
                if let url = appState.selectedTranscriptionProviderID.apiKeysURL {
                    Link("Create or manage API keys", destination: url)
                        .accessibilityIdentifier("onboarding.providerApiKeysLink")
                }
                if let guide = appState.selectedTranscriptionProviderID.setupGuideURL {
                    Link("Provider setup and billing guidance", destination: guide)
                }
                Text("Your key is saved in macOS Keychain. Audio is sent to this provider when you record; testing the key does not send audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Paste your API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboarding.apiKeyField")
                Button(isChecking ? "Checking…" : "Save & Test") { checkConnection(saveKey: true) }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isChecking)
                    .accessibilityIdentifier("onboarding.saveApiKeyButton")
                if appState.hasApiKey {
                    Button("Test saved key") { checkConnection(saveKey: false) }
                        .disabled(isChecking)
                }
            } else if appState.selectedTranscriptionProviderPresetID == .localWhisperCPP {
                localConfiguration
            } else {
                stepHeading(title: "Connect your server", description: "Configure your OpenAI-compatible endpoint in Transcription settings, then test it here.", systemImage: "network")
                Button("Open Transcription Settings") { onOpenSettings?() }
                    .accessibilityIdentifier("onboarding.openTranscriptionSettingsButton")
                Button("Test connection") { checkConnection(saveKey: false) }
                    .disabled(isChecking)
            }
            if let message = credentialError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(FoilTheme.statusWarning)
            }
            if let message = connectionMessage {
                Label(message, systemImage: connectionChecked ? "checkmark.circle" : "info.circle")
                    .font(.callout)
            }
        }
    }

    private var localConfiguration: some View {
        let model = LocalWhisperSetupModel.option(id: appState.localWhisperSetupModelID)
        let commands = LocalWhisperSetupCommands(model: model)
        return VStack(alignment: .leading, spacing: 12) {
            stepHeading(title: "Set up local transcription", description: "No API key is needed. Foil uses whisper.cpp on this Mac. The one-time installation currently needs Terminal, CMake, and Apple's command-line developer tools.", systemImage: "desktopcomputer")
            Picker("Local model", selection: $appState.localWhisperSetupModelID) {
                ForEach(LocalWhisperSetupModel.all) { option in
                    Text("\(option.displayName) — \(option.languageScope)").tag(option.id)
                }
            }
            Text("\(model.languageScope). \(model.performanceGuidance)")
                .font(.caption)
            Text("Choose an English model only if you dictate in English. Large V3 Turbo and Large V3 support multiple languages.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("whisper.cpp installation guide", destination: URL(string: "https://github.com/ggml-org/whisper.cpp#quick-start")!)
            DisclosureGroup("One-time install commands") {
                setupCommand("1. Install source", commands.cloneCommand)
                setupCommand("2. Build", commands.buildCommand)
                setupCommand("3. Download model", commands.downloadCommand)
            }
            HStack {
                Button("Start local model") { onStartLocalServer?(model.id) }
                    .disabled(appState.localWhisperServerState.isStarting || onStartLocalServer == nil)
                    .accessibilityIdentifier("onboarding.startLocalModel")
                Button("Test connection") { checkConnection(saveKey: false) }
                    .disabled(isChecking)
            }
            switch appState.providerConnectionTestState {
            case .succeeded(let message), .warning(let message), .failed(let message):
                Text(message).font(.caption)
            case .running: ProgressView("Checking server…")
            case .idle: Text("Install the model, start it, then test the connection.").font(.caption)
            }
            Button("Open Transcription Settings") { onOpenSettings?() }
                .accessibilityIdentifier("onboarding.openTranscriptionSettingsButton")
        }
    }

    private func setupCommand(_ title: String, _ command: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout.bold())
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                .accessibilityLabel("Copy \(title)")
            }
            Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
        .padding(.vertical, 5)
    }

    private func checkConnection(saveKey: Bool) {
        let provider = appState.selectedTranscriptionProvider
        let key = saveKey ? apiKey.trimmingCharacters(in: .whitespacesAndNewlines) : appState.selectedProviderApiKey
        isChecking = true
        credentialError = nil
        connectionChecked = false
        Task { @MainActor in
            defer { isChecking = false }
            do {
                let result = try await TranscriptionService().withProvider(provider).validateProviderConfiguration(
                    apiKey: key, requiredModels: [provider.transcriptionModel]
                )
                guard provider == appState.selectedTranscriptionProvider else {
                    credentialError = "The provider changed. Test the current provider to continue."
                    return
                }
                if saveKey { try KeychainHelper.save(apiKey: key ?? "", for: provider.id) }
                appState.refreshApiKeyState()
                connectionChecked = true
                connectionMessage = result == .reachableWithoutModelValidation
                    ? "Server reached. Your first dictation will test the loaded model."
                    : "Connection checked. Next, try your microphone."
                apiKey = ""
            } catch {
                credentialError = "Could not connect. \(error.localizedDescription)"
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(
                title: "Accessibility Permission",
                description: "\(AppBrand.name) needs Accessibility access to paste transcribed text into other apps.",
                systemImage: "hand.point.up.left.fill"
            )

            permissionStatusBadge(state: appState.accessibilityState, readyLabel: "Accessibility enabled")

            Button {
                onOpenAccessibility?()
            } label: {
                Label("Open Privacy & Security Settings", systemImage: "gearshape")
            }
            .font(.caption)
            .accessibilityIdentifier("onboarding.openAccessibilityButton")
        }
    }

    private var microphoneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(
                title: "Microphone Access",
                description: "\(AppBrand.name) needs microphone access to record your voice for transcription.",
                systemImage: "mic.fill"
            )

            permissionStatusBadge(state: appState.microphoneState, readyLabel: "Microphone access granted")

            if appState.microphoneState == .unknown {
                Button {
                    onCheckMicrophone?()
                } label: {
                    Label("Check Microphone Access", systemImage: "checkmark.circle")
                }
                .font(.caption)
                .accessibilityIdentifier("onboarding.checkMicrophoneButton")
            }

            Button {
                onOpenMicrophone?()
            } label: {
                Label("Open Privacy & Security Settings", systemImage: "gearshape")
            }
            .font(.caption)
            .accessibilityIdentifier("onboarding.openMicrophoneButton")
        }
    }

    private var canAdvance: Bool {
        guard !isChecking, appState.status != .recording, appState.status != .transcribing else { return false }
        switch currentStep {
        case 1: return connectionChecked
        case 2: return appState.accessibilityState == .ready
        case 3: return appState.microphoneState == .ready
        case 4: return appState.hasPracticeTranscript
        default: return true
        }
    }

    private var practiceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeading(title: "Try your first dictation", description: "Your practice transcript appears here. It is not pasted into another app or saved in History.", systemImage: "mic")
            Picker("Shortcut", selection: $appState.hotkeyChoice) {
                Text("Right Command").tag(HotkeyMonitor.HotkeyChoice.rightCommand)
                Text("Right Option").tag(HotkeyMonitor.HotkeyChoice.rightOption)
                Text("Globe/Fn").tag(HotkeyMonitor.HotkeyChoice.globeFn)
                if appState.hotkeyChoice == .custom {
                    Text(appState.hotkeyDisplayName).tag(HotkeyMonitor.HotkeyChoice.custom)
                }
            }
            .disabled(appState.status == .recording || appState.status == .transcribing)
            .onChange(of: appState.hotkeyChoice) { _, _ in onHotkeyChanged?() }
            Picker("Recording mode", selection: $appState.recordingMode) {
                Text("Hold to record").tag(HotkeyMonitor.RecordingMode.hold)
                Text("Press to start / stop").tag(HotkeyMonitor.RecordingMode.toggle)
            }
            .disabled(appState.status == .recording || appState.status == .transcribing)
            .onChange(of: appState.recordingMode) { _, _ in onHotkeyChanged?() }
            Text(appState.dictationInstruction).font(.headline)
            Text("Try saying: ‘This is my first dictation with Foil.’")
            Text("Input: \(AudioRecorder.availableInputDevices().first(where: { $0.uid == appState.selectedInputDeviceUID })?.name ?? "System default microphone")")
                .font(.caption)
            if appState.status == .recording {
                LiveAudioLevelBars(levels: appState.audioLevelHistory, phase: .recording, barCount: 14, height: 26, tint: FoilTheme.midTeal)
                Button("Stop and transcribe") { onStopPractice?() }
            } else if appState.status == .transcribing {
                ProgressView("Transcribing your recording…")
                Button("Cancel") { onEndPractice?() }
            } else {
                Button("Record a practice phrase") { onStartPractice?() }
                    .disabled(!appState.isSetupReady || onStartPractice == nil)
                    .accessibilityIdentifier("onboarding.recordPractice")
            }
            if case .error(let message) = appState.status {
                Text(message).foregroundStyle(FoilTheme.statusWarning)
            }
            if let transcript = appState.onboardingTranscript {
                Text(transcript).textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FoilTheme.sidebarBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("onboarding.practiceTranscript")
                Label("Transcription worked", systemImage: "checkmark.circle")
            }
        }
    }

    private var insertionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeading(title: "Try Foil in another app", description: "Open a blank note in Notes or TextEdit and click into it. Use your shortcut to dictate another short phrase. Stay in that app until processing finishes.", systemImage: "text.cursor")
            Text(appState.dictationInstruction).font(.headline)
            Toggle("I saw my words appear in the other app", isOn: $appState.onboardingInsertionConfirmed)
                .accessibilityIdentifier("onboarding.insertionConfirmed")
            Text(appState.onboardingInsertionConfirmed ? "Insertion confirmed by you." : "Insertion has not been confirmed. You can finish now and try it later.")
                .font(.caption)
            Text("If text does not appear, open Foil from the menu bar and choose Copy last result, then paste with Command-V.")
            Text("Foil stays in the menu bar when this window closes. Open Foil → General to choose Launch at Login.")
                .font(.caption)
        }
    }

    // MARK: - Helpers

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            FoilCylinderMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to \(AppBrand.name)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(FoilTheme.deepTeal)
                Text("Let's turn your voice into your first transcript.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var stepIndicator: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(currentStep + 1) of \(steps.count): \(steps[currentStep])")
                .font(.callout.weight(.medium))
            ProgressView(value: Double(currentStep), total: Double(steps.count - 1))
                .accessibilityLabel("Setup progress")
        }
        .accessibilityIdentifier("onboarding.stepIndicator")
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
            if currentStep > 0 {
                Button {
                    withAnimation {
                        currentStep -= 1
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(isChecking || appState.status == .recording || appState.status == .transcribing)
                .accessibilityIdentifier("onboarding.backButton")
            }

            if let onDefer {
                Button("Finish setup later", action: onDefer)
                    .disabled(isChecking || appState.status == .recording || appState.status == .transcribing)
                    .accessibilityIdentifier("onboarding.deferButton")
            }
            Spacer()

            Text("Step \(currentStep + 1) of \(steps.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if currentStep < steps.count - 1 {
                Button {
                    withAnimation {
                        currentStep += 1
                    }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .tint(FoilTheme.deepTeal)
                .disabled(!canAdvance)
                .accessibilityIdentifier("onboarding.nextButton")
            } else {
                Button {
                    onComplete()
                } label: {
                    Label("Get Started", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(FoilTheme.deepTeal)
                .disabled(!appState.areSystemPermissionsReady || !appState.hasPracticeTranscript || appState.status == .recording || appState.status == .transcribing)
                .accessibilityIdentifier("onboarding.getStartedButton")
            }
        }
    }

    private func stepHeading(title: String, description: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(FoilTheme.deepTeal.opacity(0.1))
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(FoilTheme.deepTeal)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FoilTheme.deepTeal)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func handleUITestOnboardingCommand(_ command: OnboardingUITestCommand) {
        switch command.name {
        case "goToMicrophone":
            currentStep = 3
        case "goToAccessibility":
            currentStep = 2
        case "goToCredentials":
            currentStep = 1
        case "goToFinal":
            currentStep = steps.count - 1
        case "goToPractice":
            currentStep = 4
        case "selectLocalProvider":
            appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        case "checkMicrophone":
            onCheckMicrophone?()
        case "grantAccessibility":
            appState.updateAccessibilityState(isTrusted: true)
        case "grantMicrophone":
            appState.updateMicrophoneState(isReady: true)
        case "complete":
            if appState.areSystemPermissionsReady && appState.hasPracticeTranscript { onComplete() }
        case "seedPracticeTranscript":
            guard isUITesting else { return }
            appState.onboardingTranscript = "A fixture transcript for setup testing."
        default:
            break
        }
    }

    private var providerPrivacySummary: String {
        switch appState.selectedTranscriptionProviderPresetID {
        case .groq:
            "Audio is sent to Groq for Whisper transcription. Cleanup can use Groq chat models when enabled."
        case .openAIWhisper:
            "Audio is sent to OpenAI for Whisper transcription. Cleanup stays off unless you choose a separate cleanup endpoint later."
        case .localWhisperCPP:
            "Audio stays on this Mac when your whisper.cpp server is running at 127.0.0.1."
        case .customOpenAICompatible:
            "Audio is sent to the OpenAI-compatible endpoint you configure in Settings."
        }
    }

    @ViewBuilder
    private func permissionStatusBadge(state: AppState.PermissionState, readyLabel: String) -> some View {
        switch state {
        case .ready:
            Label(readyLabel, systemImage: "checkmark.circle.fill")
                .setupStatusBadge(foreground: FoilTheme.statusSuccess, background: FoilTheme.statusSuccess.opacity(0.1))
                .accessibilityLabel("Ready")
        case .needsAction(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
                .setupStatusBadge(foreground: FoilTheme.statusWarning, background: FoilTheme.statusWarning.opacity(0.1))
                .accessibilityLabel("Needs attention: \(message)")
        case .unknown:
            Label("Checking...", systemImage: "circle.dotted")
                .setupStatusBadge(foreground: .secondary, background: Color.secondary.opacity(0.09))
                .accessibilityLabel("Checking status")
        }
    }
}

struct FoilSetupSurface<Content: View>: View {
    var width: CGFloat
    var minHeight: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(24)
            .frame(width: width, alignment: .top)
            .frame(minHeight: minHeight, alignment: .top)
            .background(FoilTheme.windowBackground)
            .environment(\.colorScheme, .light)
    }
}

struct FoilSetupPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(FoilTheme.panelBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(FoilTheme.separator)
            }
    }
}

private extension View {
    func setupStatusBadge(foreground: Color, background: Color) -> some View {
        self
            .font(.caption.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct FoilCylinderMark: View {
    var size: CGFloat = 44

    private let bars: [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: Color)] = [
        (275, 442, 44, 140, Color(red: 0.06, green: 0.25, blue: 0.27)),
        (333, 402, 44, 220, Color(red: 0.06, green: 0.25, blue: 0.27)),
        (391, 352, 44, 320, Color(red: 0.06, green: 0.25, blue: 0.27)),
        (449, 287, 44, 450, Color(red: 0.06, green: 0.25, blue: 0.27)),
        (507, 352, 44, 320, Color(red: 0.06, green: 0.25, blue: 0.27)),
        (565, 242, 44, 540, Color(red: 0.06, green: 0.25, blue: 0.27)),
        (623, 212, 44, 600, Color(red: 0.98, green: 0.72, blue: 0.24)),
        (681, 278, 44, 468, Color(red: 0.06, green: 0.25, blue: 0.27)),
        (739, 346, 44, 332, Color(red: 0.06, green: 0.25, blue: 0.27)),
        (797, 423, 44, 178, Color(red: 0.06, green: 0.25, blue: 0.27)),
        (855, 466, 44, 92, Color(red: 0.06, green: 0.25, blue: 0.27))
    ]

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 1024

            ZStack {
                RoundedRectangle(cornerRadius: 180 * scale, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.37, blue: 0.40))

                Path { path in
                    path.move(to: CGPoint(x: 130 * scale, y: 162 * scale))
                    path.addLine(to: CGPoint(x: 894 * scale, y: 162 * scale))
                    path.addCurve(
                        to: CGPoint(x: 894 * scale, y: 862 * scale),
                        control1: CGPoint(x: 984 * scale, y: 162 * scale),
                        control2: CGPoint(x: 984 * scale, y: 862 * scale)
                    )
                    path.addLine(to: CGPoint(x: 130 * scale, y: 862 * scale))
                    path.closeSubpath()
                }
                .fill(Color.white)

                VStack(spacing: 0) {
                    Color(red: 0.06, green: 0.25, blue: 0.27)
                    Color(red: 0.12, green: 0.37, blue: 0.40)
                }
                .frame(width: 140 * scale, height: 700 * scale)
                .clipShape(Ellipse())
                .position(x: 130 * scale, y: 512 * scale)

                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    Capsule()
                        .fill(bar.color)
                        .frame(width: bar.width * scale, height: bar.height * scale)
                        .position(
                            x: (bar.x + bar.width / 2) * scale,
                            y: (bar.y + bar.height / 2) * scale
                        )
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.16), radius: size * 0.08, y: size * 0.04)
        .accessibilityHidden(true)
    }
}

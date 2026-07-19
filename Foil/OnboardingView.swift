import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    var onOpenAccessibility: (() -> Void)?
    var onOpenMicrophone: (() -> Void)?
    var onCheckMicrophone: (() -> Void)?
    var onRefreshSetupHealth: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onComplete: () -> Void

    @State private var currentStep: Int = 0
    @Environment(\.openWindow) private var openWindow

    private let steps = ["Provider", "Credentials", "Accessibility", "Microphone"]

    init(
        appState: AppState,
        onOpenAccessibility: (() -> Void)? = nil,
        onOpenMicrophone: (() -> Void)? = nil,
        onCheckMicrophone: (() -> Void)? = nil,
        onRefreshSetupHealth: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onComplete: @escaping () -> Void,
        initialStep: Int = 0
    ) {
        self.appState = appState
        self.onOpenAccessibility = onOpenAccessibility
        self.onOpenMicrophone = onOpenMicrophone
        self.onCheckMicrophone = onCheckMicrophone
        self.onRefreshSetupHealth = onRefreshSetupHealth
        self.onOpenSettings = onOpenSettings
        self.onComplete = onComplete
        _currentStep = State(initialValue: min(max(initialStep, 0), steps.count - 1))
    }

    var body: some View {
        FoilSetupSurface(width: 520, minHeight: 430) {
            VStack(alignment: .leading, spacing: 18) {
                header
                stepIndicator

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
                        default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 208, alignment: .top)
                }

                navigationBar
            }
        }
        .accessibilityIdentifier("onboarding.root")
        .onAppear {
            onRefreshSetupHealth?()
        }
        .onChange(of: currentStep) { _, step in
            switch step {
            case 2:
                onRefreshSetupHealth?()
            case 3:
                onRefreshSetupHealth?()
                if !isUITesting {
                    onCheckMicrophone?()
                }
            default:
                break
            }
        }
        .onChange(of: appState.selectedTranscriptionProviderPresetID) { _, _ in
            appState.refreshApiKeyState()
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
                title: "Transcription Provider",
                description: "Choose where \(AppBrand.name) sends audio for transcription. You can change this later in Settings.",
                systemImage: "waveform.path.ecg"
            )

            Picker("Provider", selection: $appState.selectedTranscriptionProviderPresetID) {
                Text("Groq").tag(TranscriptionProviderPresetID.groq)
                Text("OpenAI Whisper").tag(TranscriptionProviderPresetID.openAIWhisper)
                Text("Local whisper.cpp").tag(TranscriptionProviderPresetID.localWhisperCPP)
                Text("Custom OpenAI-compatible").tag(TranscriptionProviderPresetID.customOpenAICompatible)
            }
            .frame(maxWidth: 300, alignment: .leading)
            .accessibilityIdentifier("onboarding.providerPicker")

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
            stepHeading(
                title: credentialTitle,
                description: credentialDescription,
                systemImage: "key.fill"
            )

            permissionStatusBadge(state: appState.apiKeyState, readyLabel: credentialReadyLabel)

            if appState.selectedTranscriptionProvider.requiresAPIKey {
                Button {
                    openWindow(id: "api-key-setup")
                } label: {
                    Label("Add API Key", systemImage: "key")
                }
                .buttonStyle(.borderedProminent)
                .tint(FoilTheme.deepTeal)
                .accessibilityIdentifier("onboarding.addApiKeyButton")

                if let url = appState.selectedTranscriptionProviderID.apiKeysURL,
                   let title = appState.selectedTranscriptionProviderID.apiKeysLinkTitle {
                    Link(title, destination: url)
                        .font(.caption)
                        .accessibilityIdentifier("onboarding.providerApiKeysLink")
                }
            } else {
                Button("Open Transcription Settings") {
                    onOpenSettings?()
                }
                .font(.caption)
                .accessibilityIdentifier("onboarding.openTranscriptionSettingsButton")
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
                Text("Finish setup once, then record from the menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(steps.indices, id: \.self) { index in
                stepPill(title: steps[index], index: index)
            }
        }
        .accessibilityIdentifier("onboarding.stepIndicator")
    }

    private func stepPill(title: String, index: Int) -> some View {
        let isCurrent = index == currentStep
        let isComplete = index < currentStep
        let tint = isCurrent || isComplete ? FoilTheme.deepTeal : Color.secondary

        return HStack(spacing: 6) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "\(index + 1).circle.fill")
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.caption.weight(isCurrent ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? FoilTheme.deepTeal.opacity(0.1) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? FoilTheme.deepTeal.opacity(0.18) : FoilTheme.separator)
        }
        .accessibilityLabel("Step \(index + 1) of \(steps.count): \(title)\(isCurrent ? ", current" : "")")
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
                .accessibilityIdentifier("onboarding.backButton")
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
                .accessibilityIdentifier("onboarding.nextButton")
            } else {
                Button {
                    onComplete()
                } label: {
                    Label("Get Started", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(FoilTheme.deepTeal)
                .disabled(!appState.areSystemPermissionsReady)
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
        case "selectLocalProvider":
            appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        case "checkMicrophone":
            onCheckMicrophone?()
        case "grantAccessibility":
            appState.updateAccessibilityState(isTrusted: true)
        case "grantMicrophone":
            appState.updateMicrophoneState(isReady: true)
        case "complete":
            onComplete()
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

    private var credentialTitle: String {
        appState.selectedTranscriptionProvider.requiresAPIKey
            ? "\(appState.selectedTranscriptionProvider.displayName) API Key"
            : "Credentials Optional"
    }

    private var credentialDescription: String {
        if appState.selectedTranscriptionProvider.requiresAPIKey {
            return "\(AppBrand.name) needs a \(appState.selectedTranscriptionProvider.displayName) API key before it can transcribe with this provider."
        }

        switch appState.selectedTranscriptionProviderPresetID {
        case .localWhisperCPP:
            return "Local whisper.cpp does not need a Groq key. Start the local server, then use Settings to test the connection."
        case .openAIWhisper:
            return "OpenAI Whisper needs an OpenAI API key. Save and test your key, then Foil can send recordings to OpenAI for transcription."
        case .customOpenAICompatible:
            return "Custom OpenAI-compatible servers can run without a key when the server allows it. Configure the endpoint in Settings."
        case .groq:
            return "API key saved."
        }
    }

    private var credentialReadyLabel: String {
        appState.selectedTranscriptionProvider.requiresAPIKey
            ? "API key saved"
            : "No API key required"
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

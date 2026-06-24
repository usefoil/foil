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

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: currentStep)
                        .accessibilityLabel("Step \(index + 1) of \(steps.count)\(index == currentStep ? ", current" : "")")
                }
            }
            .padding(.top, 24)

            Spacer()

            // Step content
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
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .accessibilityIdentifier("onboarding.backButton")
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button("Next") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboarding.nextButton")
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.areSystemPermissionsReady)
                    .accessibilityIdentifier("onboarding.getStartedButton")
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 420, height: 340)
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
        VStack(spacing: 16) {
            FoilCylinderMark(size: 52)

            Text("Transcription Provider")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose where \(AppBrand.name) sends audio for transcription. You can change this later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Picker("Provider", selection: $appState.selectedTranscriptionProviderPresetID) {
                Text("Groq").tag(TranscriptionProviderPresetID.groq)
                Text("OpenAI Whisper").tag(TranscriptionProviderPresetID.openAIWhisper)
                Text("Local whisper.cpp").tag(TranscriptionProviderPresetID.localWhisperCPP)
                Text("Custom OpenAI-compatible").tag(TranscriptionProviderPresetID.customOpenAICompatible)
            }
            .frame(width: 260)
            .accessibilityIdentifier("onboarding.providerPicker")

            Text(providerPrivacySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.providerPrivacySummary")
        }
    }

    private var credentialStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text(credentialTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(credentialDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            permissionStatusBadge(state: appState.apiKeyState, readyLabel: credentialReadyLabel)

            if appState.selectedTranscriptionProvider.requiresAPIKey {
                Button("Add API Key") {
                    openWindow(id: "api-key-setup")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding.addApiKeyButton")

                if let url = apiKeyURL {
                    Link(apiKeyLinkText, destination: url)
                        .font(.caption)
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
        VStack(spacing: 16) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Accessibility Permission")
                .font(.title2)
                .fontWeight(.semibold)

            Text("\(AppBrand.name) needs Accessibility access to paste transcribed text into other apps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            permissionStatusBadge(state: appState.accessibilityState, readyLabel: "Accessibility enabled")

            Button("Open Privacy & Security Settings") {
                onOpenAccessibility?()
            }
            .font(.caption)
            .accessibilityIdentifier("onboarding.openAccessibilityButton")
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Microphone Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("\(AppBrand.name) needs microphone access to record your voice for transcription.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            permissionStatusBadge(state: appState.microphoneState, readyLabel: "Microphone access granted")

            if appState.microphoneState == .unknown {
                Button("Check Microphone Access") {
                    onCheckMicrophone?()
                }
                .font(.caption)
                .accessibilityIdentifier("onboarding.checkMicrophoneButton")
            }

            Button("Open Privacy & Security Settings") {
                onOpenMicrophone?()
            }
            .font(.caption)
            .accessibilityIdentifier("onboarding.openMicrophoneButton")
        }
    }

    // MARK: - Helpers

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
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

    private var apiKeyURL: URL? {
        switch appState.selectedTranscriptionProviderID {
        case .groq:
            URL(string: "https://console.groq.com/keys")
        case .openAI:
            URL(string: "https://platform.openai.com/api-keys")
        case .openAICompatible:
            nil
        }
    }

    private var apiKeyLinkText: String {
        switch appState.selectedTranscriptionProviderID {
        case .groq:
            "Get a free API key at console.groq.com"
        case .openAI:
            "Create an OpenAI API key"
        case .openAICompatible:
            "API key"
        }
    }

    @ViewBuilder
    private func permissionStatusBadge(state: AppState.PermissionState, readyLabel: String) -> some View {
        switch state {
        case .ready:
            Label(readyLabel, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .accessibilityLabel("Ready")
        case .needsAction(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .accessibilityLabel("Needs attention: \(message)")
        case .unknown:
            Label("Checking...", systemImage: "circle.dotted")
                .foregroundStyle(.secondary)
                .font(.caption)
                .accessibilityLabel("Checking status")
        }
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

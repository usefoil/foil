import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    var onOpenAccessibility: (() -> Void)?
    var onOpenMicrophone: (() -> Void)?
    var onCheckMicrophone: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onComplete: () -> Void
    var uiTestCommands: OnboardingUITestCommandBridge?

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
                    .disabled(!appState.isSetupReady)
                    .accessibilityIdentifier("onboarding.getStartedButton")
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 420, height: 340)
        .accessibilityIdentifier("onboarding.root")
        .onChange(of: currentStep) { _, step in
            if step == 3 && !isUITesting {
                onCheckMicrophone?()
            }
        }
        .onChange(of: appState.selectedTranscriptionProviderPresetID) { _, _ in
            appState.refreshApiKeyState()
        }
        .onChange(of: uiTestCommands?.command) { _, command in
            guard let command else { return }
            handleUITestOnboardingCommand(command)
        }
    }

    // MARK: - Step Views

    private var providerStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Transcription Provider")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose where GroqTalk sends audio for transcription. You can change this later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Picker("Provider", selection: $appState.selectedTranscriptionProviderPresetID) {
                Text("Groq").tag(TranscriptionProviderPresetID.groq)
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

                if let url = URL(string: "https://console.groq.com/keys") {
                    Link("Get a free API key at console.groq.com", destination: url)
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

            Text("GroqTalk needs Accessibility access to paste transcribed text into other apps.")
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

            Text("GroqTalk needs microphone access to record your voice for transcription.")
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
        case "goToCredentials":
            currentStep = 1
        case "goToFinal":
            currentStep = steps.count - 1
        case "selectLocalProvider":
            appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        case "checkMicrophone":
            onCheckMicrophone?()
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
            return "GroqTalk needs a \(appState.selectedTranscriptionProvider.displayName) API key before it can transcribe with this provider."
        }

        switch appState.selectedTranscriptionProviderPresetID {
        case .localWhisperCPP:
            return "Local whisper.cpp does not need a Groq key. Start the local server, then use Settings to test the connection."
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

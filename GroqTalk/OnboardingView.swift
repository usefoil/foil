import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    var onOpenApiKey: () -> Void
    var onRunSetupCheck: () -> Void
    var onRequestMicrophoneAccess: () -> Void
    var onOpenAccessibility: () -> Void
    var onOpenMicrophone: () -> Void
    var onComplete: () -> Void

    @State private var currentStep: Int = 0

    private let steps = ["API Key", "Accessibility", "Microphone"]

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
                    apiKeyStep
                case 1:
                    accessibilityStep
                case 2:
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
                    if appState.isSetupReady {
                        Button("Get Started") {
                            onComplete()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("onboarding.getStartedButton")
                    } else {
                        Button(setupCheckButtonTitle) {
                            onRunSetupCheck()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.isSetupCheckRunning)
                        .accessibilityIdentifier("onboarding.checkSetupButton")
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 440, height: 460)
        .accessibilityIdentifier("onboarding.root")
    }

    // MARK: - Step Views

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Groq API Key")
                .font(.title2)
                .fontWeight(.semibold)

            Text("GroqTalk uses the Groq API to transcribe your voice. You'll need a free API key to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            permissionStatusBadge(state: appState.apiKeyState, readyLabel: "API key saved")

            HStack(spacing: 10) {
                Button("Add Key") {
                    onOpenApiKey()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding.addKeyButton")

                if let url = URL(string: "https://console.groq.com/keys") {
                    Link("Get free key", destination: url)
                        .font(.caption)
                        .accessibilityIdentifier("onboarding.getGroqKeyLink")
                }
            }

            setupCheckSummary
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

            HStack(spacing: 10) {
                Button("Open Settings") {
                    onOpenAccessibility()
                }
                .accessibilityIdentifier("onboarding.openAccessibilityButton")

                Button(setupCheckButtonTitle) {
                    onRunSetupCheck()
                }
                .disabled(appState.isSetupCheckRunning)
                .accessibilityIdentifier("onboarding.checkAccessibilityButton")
            }
            .font(.caption)

            setupCheckSummary
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

            HStack(spacing: 10) {
                Button(microphoneActionTitle) {
                    onRequestMicrophoneAccess()
                }
                .disabled(appState.isSetupCheckRunning)
                .accessibilityIdentifier("onboarding.requestMicrophoneButton")

                Button("Open Settings") {
                    onOpenMicrophone()
                }
                .accessibilityIdentifier("onboarding.openMicrophoneButton")
            }
            .font(.caption)

            setupCheckSummary

            Text("When setup is ready, hold your hotkey, speak, then release/stop. GroqTalk transcribes your speech and pastes the text into the active app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.workflowPayoff")
        }
    }

    // MARK: - Helpers

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

    private var setupCheckButtonTitle: String {
        appState.isSetupCheckRunning ? "Checking..." : "Check Setup"
    }

    private var microphoneActionTitle: String {
        switch appState.microphoneState {
        case .ready:
            "Check Microphone"
        case .needsAction:
            "Check Again"
        case .unknown:
            "Request Microphone Access"
        }
    }

    private var setupCheckSummary: some View {
        VStack(spacing: 4) {
            Label(setupCheckTitle, systemImage: setupCheckIcon)
                .foregroundStyle(setupCheckColor)
                .font(.caption)
                .accessibilityIdentifier("onboarding.setupCheckStatus")

            if let detail = setupCheckDetail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.setupCheckDetail")
            }
        }
    }

    private var setupCheckTitle: String {
        switch appState.setupCheckState {
        case .idle:
            appState.isSetupReady ? "Setup ready" : "Check setup when each item is complete"
        case .running:
            "Checking setup..."
        case .passed:
            "Setup ready"
        case .failed(let message):
            "Setup needs attention: \(message)"
        }
    }

    private var setupCheckDetail: String? {
        if appState.isSetupReady {
            return "You can start recording from the menu bar."
        }
        switch appState.setupCheckState {
        case .idle:
            return "Use Check Setup after adding a key and granting permissions."
        case .running:
            return "GroqTalk is checking your key, Accessibility, microphone permission, and audio input."
        case .passed:
            return "All setup checks passed."
        case .failed(let message):
            if message.localizedCaseInsensitiveContains("api key") {
                return "Add or fix your API key, then check setup again."
            }
            if message.localizedCaseInsensitiveContains("accessibility") {
                return "Enable Accessibility in Privacy & Security, then check setup again."
            }
            if message.localizedCaseInsensitiveContains("microphone") {
                return "Allow Microphone access or choose an input device, then check setup again."
            }
            return "Resolve the setup item above, then check setup again."
        }
    }

    private var setupCheckIcon: String {
        switch appState.setupCheckState {
        case .idle:
            appState.isSetupReady ? "checkmark.circle.fill" : "checklist"
        case .running:
            "arrow.triangle.2.circlepath"
        case .passed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var setupCheckColor: Color {
        switch appState.setupCheckState {
        case .passed:
            .green
        case .failed:
            .orange
        case .idle:
            appState.isSetupReady ? .green : .secondary
        case .running:
            .secondary
        }
    }
}

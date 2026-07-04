import SwiftUI

struct ApiKeySetupView: View {
    var provider: TranscriptionProvider = .groq
    var onSaved: (() -> Void)?
    var validateApiKey: (String) async throws -> Void = { key in
        try await TranscriptionService().validateApiKey(apiKey: key)
    }

    @State private var apiKey = ""
    @State private var errorMessage: String?
    @State private var saved = false
    @State private var isValidating = false
    @State private var canSaveWithoutValidation = false
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        FoilSetupSurface(width: 430, minHeight: 330) {
            VStack(alignment: .leading, spacing: 18) {
                header

                FoilSetupPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(provider.requiresAPIKey ? "Enter your \(provider.displayName) API key to enable speech-to-text." : "\(provider.displayName) can run without a real API key when your server allows it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        SecureField(apiKeyPlaceholder, text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("\(provider.displayName) API Key")
                            .accessibilityIdentifier("apiKeySetup.apiKeyField")

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Error: \(errorMessage)")
                                .accessibilityIdentifier("apiKeySetup.errorMessage")
                        }

                        if saved {
                            Label("API key saved", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(FoilTheme.midTeal)
                                .accessibilityLabel("API key is valid")
                                .accessibilityIdentifier("apiKeySetup.validIndicator")
                        }

                        if isValidating {
                            ProgressView("Checking key...")
                                .controlSize(.small)
                                .font(.caption)
                                .accessibilityLabel("Validating API key")
                                .accessibilityIdentifier("apiKeySetup.progress")
                        }
                    }
                }

                HStack(spacing: 10) {
                    if let apiKeyURL {
                        Link("Get API Key", destination: apiKeyURL)
                            .font(.caption)
                            .accessibilityIdentifier("apiKeySetup.getKeyLink")
                    }

                    Spacer()

                    if canSaveWithoutValidation {
                        Button("Save Anyway") {
                            saveKeyWithoutValidation()
                        }
                        .accessibilityIdentifier("apiKeySetup.saveAnywayButton")
                    }

                    Button {
                        saveKey()
                    } label: {
                        Label(isValidating ? "Checking..." : "Save & Test", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FoilTheme.deepTeal)
                    .disabled(apiKey.isEmpty || isValidating)
                    .accessibilityIdentifier("apiKeySetup.saveTestButton")
                }
            }
        }
        .accessibilityIdentifier("apiKeySetup.root")
        .onAppear {
            guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
            if let existing = KeychainHelper.readApiKey(for: provider.id) {
                apiKey = existing
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            FoilCylinderMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(AppBrand.name) Setup")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(FoilTheme.deepTeal)
                Text("\(provider.displayName) credentials")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func saveKey() {
        isValidating = true
        errorMessage = nil
        canSaveWithoutValidation = false
        let key = apiKey
        Task {
            do {
                try await validateApiKey(key)
                try KeychainHelper.save(apiKey: key, for: provider.id)
                await MainActor.run {
                    finishSaved()
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    saved = false
                    errorMessage = validationMessage(from: error)
                    canSaveWithoutValidation = allowsSaveAnyway(for: error)
                }
            }
        }
    }

    private func saveKeyWithoutValidation() {
        do {
            try KeychainHelper.save(apiKey: apiKey, for: provider.id)
            finishSaved()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func finishSaved() {
        isValidating = false
        canSaveWithoutValidation = false
        onSaved?()
        saved = true
        errorMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismissWindow(id: "api-key-setup")
        }
    }

    private func allowsSaveAnyway(for error: Error) -> Bool {
        error is URLError
    }

    private func validationMessage(from error: Error) -> String {
        switch error {
        case TranscriptionService.TranscriptionError.invalidApiKey:
            "Invalid \(provider.displayName) API key."
        case TranscriptionService.TranscriptionError.rateLimited:
            "\(provider.displayName) rate limit reached. Try again shortly."
        case TranscriptionService.TranscriptionError.quotaExceeded:
            "\(provider.displayName) quota exceeded. Check your account limits."
        case TranscriptionService.TranscriptionError.serverError:
            "\(provider.displayName) is temporarily unavailable. Try again later."
        case let urlError as URLError where urlError.code == .notConnectedToInternet:
            "Could not reach \(provider.displayName). Check your connection, or save anyway and test later."
        case let urlError as URLError where urlError.code == .timedOut:
            "\(provider.displayName) validation timed out. You can save anyway and test later."
        default:
            "Could not validate key: \(error.localizedDescription)"
        }
    }

    private var apiKeyPlaceholder: String {
        switch provider.id {
        case .groq:
            "gsk_..."
        case .openAI:
            "sk-..."
        case .openAICompatible:
            "API key"
        }
    }

    private var apiKeyURL: URL? {
        switch provider.id {
        case .groq:
            URL(string: "https://console.groq.com/keys")
        case .openAI:
            URL(string: "https://platform.openai.com/api-keys")
        case .openAICompatible:
            nil
        }
    }
}

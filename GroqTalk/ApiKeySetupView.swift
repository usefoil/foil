import SwiftUI

struct ApiKeySetupView: View {
    @State private var apiKey = ""
    @State private var errorMessage: String?
    @State private var saved = false
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)

            Text("GroqTalk Setup")
                .font(.headline)

            Text("Enter your Groq API key to enable speech-to-text.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("gsk_...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if saved {
                Label("API key saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            HStack {
                Link("Get API Key", destination: URL(string: "https://console.groq.com/keys")!)
                    .font(.caption)

                Spacer()

                Button("Save") {
                    saveKey()
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            if let existing = KeychainHelper.readApiKey() {
                apiKey = existing
            }
        }
    }

    private func saveKey() {
        do {
            try KeychainHelper.save(apiKey: apiKey)
            saved = true
            errorMessage = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                dismissWindow(id: "api-key-setup")
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}

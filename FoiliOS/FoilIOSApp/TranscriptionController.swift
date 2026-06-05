import Foundation

@MainActor
final class TranscriptionController: ObservableObject {
    @Published private(set) var status = "Transcription idle"
    @Published private(set) var recoveryMessage: String?

    private let bridge = FoilKeyboardBridge()
    private let client = FoilTranscriptionClient()
    private let credentialStore = FoilCredentialStore.shared

    var hasConfiguredAPIKey: Bool {
        apiKey != nil
    }

    var credentialSummary: String {
        hasConfiguredAPIKey ? "Groq key configured" : "Groq key needed"
    }

    func saveGroqAPIKey(_ value: String) throws {
        try credentialStore.saveGroqAPIKey(value)
        objectWillChange.send()
    }

    func clearGroqAPIKey() throws {
        try credentialStore.clearGroqAPIKey()
        objectWillChange.send()
    }

    func transcribeLatestRecording(_ recordingURL: URL?) async {
        guard let recordingURL else {
            status = TranscriptionError.missingRecording.localizedDescription
            recoveryMessage = "Record first, then tap Transcribe."
            return
        }
        guard let apiKey else {
            status = TranscriptionError.missingAPIKey.localizedDescription
            recoveryMessage = "Save a Groq key, then tap Transcribe again."
            bridge.fail(message: "Groq key needed. Open Foil app to recover.")
            return
        }

        status = "Transcribing"
        recoveryMessage = nil
        bridge.save(
            FoilKeyboardSnapshot(
                phase: .processing,
                transcript: nil,
                message: "Transcribing with Groq. Return when the transcript is ready.",
                updatedAt: Date()
            )
        )

        do {
            let transcript = try await client.transcribe(audioFileURL: recordingURL, apiKey: apiKey)
            guard FoilTranscriptQuality.isAcceptable(transcript) else {
                status = "No speech detected"
                recoveryMessage = "Record again, or reset shared state to return the keyboard to ready."
                bridge.fail(message: "No speech detected. Record again in Foil.")
                return
            }
            let finalTranscript = transcript
            status = "Transcription complete"
            recoveryMessage = nil
            bridge.complete(transcript: finalTranscript, message: "Groq transcript ready. Switch back and tap Insert latest.")
        } catch {
            status = error.localizedDescription
            recoveryMessage = "Check the key or network, then tap Transcribe again."
            bridge.fail(message: "Transcription failed. Open Foil app to retry.")
        }
    }

    private var apiKey: String? {
        if let environmentKey = nonEmpty(ProcessInfo.processInfo.environment["FOIL_IOS_GROQ_API_KEY"]) {
            return environmentKey
        }
        if let environmentKey = nonEmpty(ProcessInfo.processInfo.environment["GROQ_API_KEY"]) {
            return environmentKey
        }
        if let storedKey = credentialStore.loadGroqAPIKey() {
            return storedKey
        }

        #if DEBUG
        return nonEmpty(UserDefaults.standard.string(forKey: "FOIL_IOS_GROQ_API_KEY"))
            ?? nonEmpty(UserDefaults.standard.string(forKey: "GROQ_API_KEY"))
        #else
        return nil
        #endif
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

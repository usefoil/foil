import Foundation

@MainActor
final class TranscriptionController: ObservableObject {
    @Published private(set) var status = "Transcription idle"

    private let bridge = FoilKeyboardBridge()
    private let client = FoilTranscriptionClient()

    func transcribeLatestRecording(_ recordingURL: URL?) async {
        guard let recordingURL else {
            status = TranscriptionError.missingRecording.localizedDescription
            return
        }
        guard let apiKey else {
            status = TranscriptionError.missingAPIKey.localizedDescription
            return
        }

        status = "Transcribing"
        bridge.save(
            FoilKeyboardSnapshot(
                phase: .processing,
                transcript: nil,
                message: "Transcribing with Groq",
                updatedAt: Date()
            )
        )

        do {
            let transcript = try await client.transcribe(audioFileURL: recordingURL, apiKey: apiKey)
            let finalTranscript = transcript.isEmpty ? "(empty transcript)" : transcript
            status = "Transcription complete"
            bridge.complete(transcript: finalTranscript, message: "Groq transcript ready")
        } catch {
            status = error.localizedDescription
            bridge.save(
                FoilKeyboardSnapshot(
                    phase: .idle,
                    transcript: nil,
                    message: "Transcription failed",
                    updatedAt: Date()
                )
            )
        }
    }

    private var apiKey: String? {
        if let environmentKey = nonEmpty(ProcessInfo.processInfo.environment["FOIL_IOS_GROQ_API_KEY"]) {
            return environmentKey
        }
        if let environmentKey = nonEmpty(ProcessInfo.processInfo.environment["GROQ_API_KEY"]) {
            return environmentKey
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

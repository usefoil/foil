import CoreAudio
import Foundation

/// AudioRecording stub that returns a pre-generated audio file instead of recording from the mic.
/// Used by the opt-in E2E transcription smoke path.
final class E2EAudioStub: AudioRecording {
    var levelUpdateHandler: ((Float) -> Void)?

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func startRecording(deviceID: AudioDeviceID?) throws {
        // No-op: no microphone needed
    }

    func stopRecordingAsync(format: AudioFormat) async throws -> URL? {
        return fileURL
    }

    func cancelRecording() {
        // No-op
    }
}

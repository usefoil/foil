import CoreAudio
import Foundation

#if DEBUG
/// AudioRecording stub that returns a pre-generated audio file instead of recording from the mic.
/// Used by UITestingController for E2E transcription tests.
final class E2EAudioStub: AudioRecording {
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
#endif

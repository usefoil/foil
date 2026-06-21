import AVFoundation
import CoreAudio

/// Minimal protocol for the audio recording operations used by RecordingController.
/// Concrete types: AudioRecorder (production), MockAudioRecorder (tests).
protocol AudioRecording: AnyObject {
    var levelUpdateHandler: ((Float) -> Void)? { get set }

    func startRecording(deviceID: AudioDeviceID?) throws
    func stopRecordingAsync(format: AudioFormat) async throws -> URL?
    func cancelRecording()
}

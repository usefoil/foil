import AVFoundation
import Foundation

@MainActor
final class AudioCaptureController: NSObject, ObservableObject {
    @Published private(set) var status = "Recorder idle"
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var recoveryMessage: String?

    private let bridge = FoilKeyboardBridge()
    private var recorder: AVAudioRecorder?

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    func startRecording() async {
        guard !isRecording else { return }

        guard await requestRecordPermission() else {
            status = "Microphone permission denied"
            recoveryMessage = "Enable Microphone access in Settings, then return to Foil."
            bridge.fail(message: "Microphone blocked. Open Foil app to recover.")
            return
        }

        do {
            recoveryMessage = nil
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)

            let url = try makeRecordingURL()
            let recorder = try AVAudioRecorder(url: url, settings: recordingSettings)
            recorder.prepareToRecord()
            guard recorder.record() else {
                throw AudioCaptureError.recordingDidNotStart
            }
            self.recorder = recorder
            lastRecordingURL = url
            status = "Recording"
            bridge.markListening()
        } catch {
            recorder = nil
            lastRecordingURL = nil
            status = "Recording failed: \(error.localizedDescription)"
            recoveryMessage = "Try recording again, or reset shared state if the keyboard looks stuck."
            bridge.fail(message: "Recording failed. Open Foil app to retry.")
        }
    }

    func stopRecording() {
        guard let recorder else { return }
        recorder.stop()
        self.recorder = nil
        status = "Recording saved"
        recoveryMessage = nil
        bridge.save(
            FoilKeyboardSnapshot(
                phase: .processing,
                transcript: nil,
                message: "Recording saved. Tap Transcribe in Foil.",
                updatedAt: Date()
            )
        )
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func requestRecordPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }

    private func makeRecordingURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let filename = "foil-ios-\(formatter.string(from: Date())).m4a"
            .replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent(filename)
    }
}

private enum AudioCaptureError: LocalizedError {
    case recordingDidNotStart

    var errorDescription: String? {
        switch self {
        case .recordingDidNotStart:
            return "Recorder did not start"
        }
    }
}

import AVFAudio
import Foundation

final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var buffers: [AVAudioPCMBuffer] = []
    private let bufferQueue = DispatchQueue(label: "com.neonwatty.groqtalk.audiobuffers")

    func startRecording() throws {
        cancelRecording()

        let engine = AVAudioEngine()
        audioEngine = engine
        bufferQueue.sync { buffers = [] }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.bufferQueue.sync { self?.buffers.append(buffer) }
        }

        try engine.start()
    }

    func stopRecording() -> URL? {
        guard let engine = audioEngine else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil

        let captured = bufferQueue.sync { () -> [AVAudioPCMBuffer] in
            let b = buffers; buffers = []; return b
        }

        guard !captured.isEmpty, let format = captured.first?.format else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("groqtalk-\(UUID().uuidString).wav")

        do {
            let file = try AVAudioFile(forWriting: tempURL, settings: format.settings)
            for buffer in captured {
                try file.write(from: buffer)
            }
            return tempURL
        } catch {
            print("AudioRecorder: failed to write WAV — \(error)")
            return nil
        }
    }

    func cancelRecording() {
        guard let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        bufferQueue.sync { buffers = [] }
    }
}

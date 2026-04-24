import AVFAudio
import Foundation

final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var buffers: [AVAudioPCMBuffer] = []
    private let bufferQueue = DispatchQueue(label: "com.neonwatty.groqtalk.audiobuffers")

    private static let targetSampleRate: Double = 16000
    private static let targetChannels: AVAudioChannelCount = 1

    private static var pcmFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        )!
    }

    func startRecording() throws {
        cancelRecording()

        let engine = AVAudioEngine()
        audioEngine = engine
        bufferQueue.sync { buffers = [] }

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: hwFormat, to: Self.pcmFormat) else {
            throw RecordingError.formatConversionFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = Self.targetSampleRate / hwFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard outputFrameCount > 0,
                  let converted = AVAudioPCMBuffer(
                      pcmFormat: Self.pcmFormat, frameCapacity: outputFrameCount
                  ) else { return }

            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if error == nil && converted.frameLength > 0 {
                self.bufferQueue.sync { self.buffers.append(converted) }
            }
        }

        try engine.start()
    }

    func stopRecording(format: String = "wav") -> URL? {
        guard let engine = audioEngine else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil

        let captured = bufferQueue.sync { () -> [AVAudioPCMBuffer] in
            let b = buffers; buffers = []; return b
        }

        guard !captured.isEmpty else { return nil }

        switch format {
        case "m4a":  return writeM4A(buffers: captured)
        case "flac": return writeFLAC(buffers: captured)
        default:     return writeWAV(buffers: captured)
        }
    }

    func cancelRecording() {
        guard let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        bufferQueue.sync { buffers = [] }
    }

    // MARK: - WAV output

    func writeWAV(buffers: [AVAudioPCMBuffer]) -> URL? {
        let url = tempURL(extension: "wav")
        // Write as 16-bit PCM WAV for smallest lossless size
        let int16Format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: true
        )!
        do {
            let file = try AVAudioFile(forWriting: url, settings: int16Format.settings)
            for buffer in buffers {
                try file.write(from: buffer)
            }
            return url
        } catch {
            print("AudioRecorder: failed to write WAV — \(error)")
            return nil
        }
    }

    // MARK: - M4A/AAC output

    func writeM4A(buffers: [AVAudioPCMBuffer]) -> URL? {
        let url = tempURL(extension: "m4a")
        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.targetSampleRate,
            AVNumberOfChannelsKey: Self.targetChannels,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: aacSettings)
            for buffer in buffers {
                try file.write(from: buffer)
            }
            return url
        } catch {
            print("AudioRecorder: failed to write M4A — \(error)")
            return nil
        }
    }

    // MARK: - FLAC output

    func writeFLAC(buffers: [AVAudioPCMBuffer]) -> URL? {
        let url = tempURL(extension: "flac")
        let flacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: Self.targetSampleRate,
            AVNumberOfChannelsKey: Self.targetChannels,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: flacSettings)
            for buffer in buffers {
                try file.write(from: buffer)
            }
            return url
        } catch {
            print("AudioRecorder: failed to write FLAC — \(error)")
            return nil
        }
    }

    private func tempURL(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("groqtalk-\(UUID().uuidString).\(ext)")
    }

    enum RecordingError: Error {
        case formatConversionFailed
    }
}

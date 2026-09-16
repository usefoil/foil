import AVFAudio
import Foundation

enum ManagedLocalAudioConverter {
    /// The temporary upload is owned by this scope, including thrown and cancelled uploads.
    static func withWAV<T>(source: URL, operation: (URL) async throws -> T) async throws -> T {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-managed-audio-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: destination) }
        try Task.checkCancellation()
        try convert(source: source, destination: destination)
        try Task.checkCancellation()
        return try await operation(destination)
    }

    private static func convert(source: URL, destination: URL) throws {
        do {
            let input = try AVAudioFile(forReading: source)
            guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                    channels: 1, interleaved: true),
                  let converter = AVAudioConverter(from: input.processingFormat, to: outputFormat),
                  let inputBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 4096),
                  let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096) else {
                throw ManagedLocalError.transport
            }
            let output = try AVAudioFile(forWriting: destination, settings: outputFormat.settings,
                commonFormat: .pcmFormatInt16, interleaved: true)
            var inputFailure: Error?
            while true {
                try Task.checkCancellation()
                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { count, state in
                    if input.framePosition >= input.length { state.pointee = .endOfStream; return nil }
                    do {
                        try input.read(into: inputBuffer, frameCount: min(count, inputBuffer.frameCapacity))
                        state.pointee = .haveData
                        return inputBuffer
                    } catch {
                        inputFailure = error; state.pointee = .endOfStream; return nil
                    }
                }
                guard inputFailure == nil, conversionError == nil, status != .error else {
                    throw ManagedLocalError.transport
                }
                if outputBuffer.frameLength > 0 { try output.write(from: outputBuffer) }
                if status == .endOfStream { break }
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw ManagedLocalError.transport }
    }
}

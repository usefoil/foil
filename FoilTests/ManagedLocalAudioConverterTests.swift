import AVFAudio
import XCTest
@testable import Foil

final class ManagedLocalAudioConverterTests: XCTestCase {
    func testStereoAACConvertsToMono16KPCMAndRemovesTemporaryFile() async throws {
        let source = try makeSource()
        defer { try? FileManager.default.removeItem(at: source) }
        var temporary: URL?
        try await ManagedLocalAudioConverter.withWAV(source: source) { url in
            temporary = url
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
            XCTAssertEqual(file.fileFormat.channelCount, 1)
            XCTAssertEqual(file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int, 16)
            XCTAssertGreaterThan(file.length, 7_000)
            XCTAssertLessThan(file.length, 10_000)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(temporary).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testTemporaryAudioIsRemovedWhenUploadThrowsOrCancels() async throws {
        let source = try makeSource()
        defer { try? FileManager.default.removeItem(at: source) }
        for failure: Error in [ManagedLocalError.transport, CancellationError()] {
            var temporary: URL?
            do {
                try await ManagedLocalAudioConverter.withWAV(source: source) { url in
                    temporary = url
                    throw failure
                }
                XCTFail("Expected upload failure")
            } catch {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(temporary).path))
        }
    }

    private func makeSource() throws -> URL {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24_000)!
        buffer.frameLength = 24_000
        for channel in 0..<2 {
            for frame in 0..<24_000 { buffer.floatChannelData![channel][frame] = sin(Float(frame) * 0.1) * 0.4 }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2])
        try file.write(from: buffer)
        return url
    }
}

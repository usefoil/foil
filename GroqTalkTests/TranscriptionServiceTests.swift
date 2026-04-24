import XCTest
@testable import GroqTalk

final class TranscriptionServiceTests: XCTestCase {
    func testMultipartBodyContainsAllFields() throws {
        let service = TranscriptionService()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let boundary = "test-boundary-123"
        let body = try service.buildMultipartBody(
            audioFileURL: tempURL,
            model: "whisper-large-v3-turbo",
            format: "wav",
            boundary: boundary
        )
        let bodyString = String(data: body, encoding: .utf8)!

        XCTAssertTrue(bodyString.contains("--test-boundary-123\r\n"))
        XCTAssertTrue(bodyString.contains("name=\"model\"\r\n\r\nwhisper-large-v3-turbo"))
        XCTAssertTrue(bodyString.contains("name=\"response_format\"\r\n\r\ntext"))
        XCTAssertTrue(bodyString.contains("name=\"file\"; filename=\"audio.wav\""))
        XCTAssertTrue(bodyString.contains("Content-Type: audio/wav"))
        XCTAssertTrue(bodyString.contains("--test-boundary-123--"))
    }

    func testMultipartBodyM4AFormat() throws {
        let service = TranscriptionService()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio.m4a")
        try Data([0x00, 0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let body = try service.buildMultipartBody(
            audioFileURL: tempURL,
            model: "whisper-large-v3",
            format: "m4a",
            boundary: "b"
        )
        let bodyString = String(data: body, encoding: .utf8)!

        XCTAssertTrue(bodyString.contains("filename=\"audio.m4a\""))
        XCTAssertTrue(bodyString.contains("Content-Type: audio/mp4"))
    }

    func testMultipartBodyMP3Format() throws {
        let service = TranscriptionService()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio.mp3")
        try Data([0xFF, 0xFB]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let body = try service.buildMultipartBody(
            audioFileURL: tempURL,
            model: "whisper-large-v3",
            format: "mp3",
            boundary: "b"
        )
        // Use latin1 (lossless for arbitrary bytes) since body contains binary audio data
        let bodyString = String(data: body, encoding: .isoLatin1)!

        XCTAssertTrue(bodyString.contains("filename=\"audio.mp3\""))
        XCTAssertTrue(bodyString.contains("Content-Type: audio/mpeg"))
    }

    func testMultipartBodyIncludesAudioData() throws {
        let service = TranscriptionService()

        let audioBytes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05]
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio2.wav")
        try Data(audioBytes).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let body = try service.buildMultipartBody(
            audioFileURL: tempURL,
            model: "whisper-large-v3",
            format: "wav",
            boundary: "b"
        )

        let audioData = Data(audioBytes)
        XCTAssertNotNil(body.range(of: audioData))
    }
}

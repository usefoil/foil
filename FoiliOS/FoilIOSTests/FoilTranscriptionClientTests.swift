import Foundation
import XCTest
@testable import FoilIOS

final class FoilTranscriptionClientTests: XCTestCase {
    func testTranscribeUploadsMultipartAudioToGroqAndTrimsResponse() async throws {
        let audioURL = try writeTemporaryAudioFile(bytes: Data([0x66, 0x6f, 0x69, 0x6c]))
        var capturedRequest: URLRequest?
        var capturedBody: Data?
        let transport = StubUploadTransport { request, body in
            capturedRequest = request
            capturedBody = body
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"text":"  hello foil  \n"}"#.utf8), response)
        }
        let client = FoilTranscriptionClient(
            transport: transport,
            boundaryProvider: { "TestBoundary" }
        )

        let transcript = try await client.transcribe(audioFileURL: audioURL, apiKey: "test-groq-key")

        XCTAssertEqual(transcript, "hello foil")
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-groq-key")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=TestBoundary"
        )
        let body = String(decoding: try XCTUnwrap(capturedBody), as: UTF8.self)
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"model\""), body)
        XCTAssertTrue(body.contains("whisper-large-v3-turbo"), body)
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\""), body)
        XCTAssertTrue(body.contains("Content-Type: audio/mp4"), body)
        XCTAssertTrue(body.contains("foil"), body)
        XCTAssertTrue(body.hasSuffix("--TestBoundary--\r\n"), body)
    }

    func testTranscribeThrowsHTTPStatusWithoutLeakingResponseBody() async throws {
        let audioURL = try writeTemporaryAudioFile(bytes: Data("voice".utf8))
        let transport = StubUploadTransport { request, _ in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"error":"bad provider-body-sentinel"}"#.utf8), response)
        }
        let client = FoilTranscriptionClient(
            transport: transport,
            boundaryProvider: { "TestBoundary" }
        )

        do {
            _ = try await client.transcribe(audioFileURL: audioURL, apiKey: "test-groq-key")
            XCTFail("Expected HTTP status failure")
        } catch {
            XCTAssertEqual(error as? TranscriptionError, .httpStatus(401))
            XCTAssertFalse(error.localizedDescription.contains("provider-body-sentinel"))
        }
    }

    private func writeTemporaryAudioFile(bytes: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilTranscriptionClientTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sample.m4a")
        try bytes.write(to: url)
        return url
    }
}

private struct StubUploadTransport: FoilTranscriptionUploading {
    var handler: (URLRequest, Data) async throws -> (Data, URLResponse)

    func upload(for request: URLRequest, from body: Data) async throws -> (Data, URLResponse) {
        try await handler(request, body)
    }
}

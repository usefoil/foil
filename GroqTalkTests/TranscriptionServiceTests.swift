import XCTest
@testable import GroqTalk

final class TranscriptionServiceTests: XCTestCase {
    private final class StubTransport: TranscriptionTransport {
        var requests: [URLRequest] = []
        let handler: (URLRequest) async throws -> (Data, URLResponse)

        init(handler: @escaping (URLRequest) async throws -> (Data, URLResponse)) {
            self.handler = handler
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            return try await handler(request)
        }
    }

    private static func makeAudioFile(name: String = UUID().uuidString, bytes: [UInt8] = [0x52, 0x49, 0x46, 0x46]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension("wav")
        try Data(bytes).write(to: url)
        return url
    }

    private static func httpResponse(statusCode: Int, url: URL = URL(string: "https://api.groq.com")!) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

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
            format: .wav,
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
            format: .m4a,
            boundary: "b"
        )
        let bodyString = String(data: body, encoding: .utf8)!

        XCTAssertTrue(bodyString.contains("filename=\"audio.m4a\""))
        XCTAssertTrue(bodyString.contains("Content-Type: audio/mp4"))
    }

    func testMultipartBodyFLACFormat() throws {
        let service = TranscriptionService()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio.flac")
        try Data([0x66, 0x4C, 0x61, 0x43]).write(to: tempURL) // "fLaC" magic
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let body = try service.buildMultipartBody(
            audioFileURL: tempURL,
            model: "whisper-large-v3",
            format: .flac,
            boundary: "b"
        )
        let bodyString = String(data: body, encoding: .utf8)!

        XCTAssertTrue(bodyString.contains("filename=\"audio.flac\""))
        XCTAssertTrue(bodyString.contains("Content-Type: audio/flac"))
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
            format: .wav,
            boundary: "b"
        )

        let audioData = Data(audioBytes)
        XCTAssertNotNil(body.range(of: audioData))
    }

    // MARK: - Format consistency

    func testAllThreeFormatsProduceDistinctContentTypes() throws {
        let service = TranscriptionService()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-ct.bin")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var contentTypes: Set<String> = []

        for format in AudioFormat.allCases {
            let body = try service.buildMultipartBody(
                audioFileURL: tempURL, model: "m", format: format, boundary: "b"
            )
            let bodyString = String(data: body, encoding: .isoLatin1)!
            if let range = bodyString.range(of: "Content-Type: audio/") {
                let start = range.lowerBound
                let lineEnd = bodyString[start...].firstIndex(of: "\r") ?? bodyString.endIndex
                contentTypes.insert(String(bodyString[start..<lineEnd]))
            }
        }

        XCTAssertEqual(contentTypes.count, 3, "Each format should produce a distinct Content-Type")
    }

    func testMultipartBodyIncludesResponseFormatText() throws {
        let service = TranscriptionService()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-rf.wav")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let body = try service.buildMultipartBody(
            audioFileURL: tempURL, model: "whisper-large-v3", format: .wav, boundary: "b"
        )
        let bodyString = String(data: body, encoding: .utf8)!
        XCTAssertTrue(bodyString.contains("name=\"response_format\"\r\n\r\ntext"),
                       "Multipart body must request text response format")
    }

    func testMultipartBodyBoundaryTermination() throws {
        let service = TranscriptionService()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-term.wav")
        try Data([0x00]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let body = try service.buildMultipartBody(
            audioFileURL: tempURL, model: "m", format: .wav, boundary: "BOUNDARY"
        )
        let bodyString = String(data: body, encoding: .utf8)!
        XCTAssertTrue(bodyString.hasSuffix("--BOUNDARY--\r\n"),
                       "Multipart body must end with closing boundary")
    }

    func testTranscriptProcessingBodyUsesGroqChatShape() throws {
        let service = TranscriptionService()

        let data = try service.buildTranscriptProcessingBody(
            transcript: "um this is teh thing",
            mode: .cleanUp,
            model: "llama-3.3-70b-versatile"
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let messages = json?["messages"] as? [[String: String]]

        XCTAssertEqual(json?["model"] as? String, "llama-3.3-70b-versatile")
        XCTAssertEqual(json?["temperature"] as? Double, 0.2)
        XCTAssertEqual(json?["max_completion_tokens"] as? Int, 1024)
        XCTAssertEqual(messages?.first?["role"], "system")
        XCTAssertTrue(messages?.first?["content"]?.contains("Clean up the transcript lightly") == true)
        XCTAssertEqual(messages?.last?["role"], "user")
        XCTAssertEqual(messages?.last?["content"], "um this is teh thing")
    }

    // MARK: - Deterministic transport/status mapping

    func testTranscribeReturnsTrimmedTextForHTTP200() async throws {
        let transport = StubTransport { request in
            (
                Data("  hello world\n".utf8),
                Self.httpResponse(statusCode: 200, url: request.url!)
            )
        }
        let service = TranscriptionService(transport: transport)
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let text = try await service.transcribe(
            audioFileURL: tempURL,
            apiKey: "test-key",
            model: "whisper-large-v3",
            format: .wav
        )

        XCTAssertEqual(text, "hello world")
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testTranscribeMapsHTTP401ToInvalidApiKey() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data("unauthorized".utf8), Self.httpResponse(statusCode: 401, url: request.url!))
        })
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "bad", model: "m")
            XCTFail("Expected invalid API key error")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .invalidApiKey)
        }
    }

    func testTranscribeMapsHTTP413ToFileTooLarge() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data("too large".utf8), Self.httpResponse(statusCode: 413, url: request.url!))
        })
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "m")
            XCTFail("Expected file too large error")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .fileTooLarge)
        }
    }

    func testTranscribeMapsHTTP429ToApiErrorWithBody() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data("rate limited".utf8), Self.httpResponse(statusCode: 429, url: request.url!))
        })
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "m")
            XCTFail("Expected API error")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .apiError(429, "rate limited"))
        }
    }

    func testTranscribeMapsHTTP500ToApiErrorWithBody() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data("server exploded".utf8), Self.httpResponse(statusCode: 500, url: request.url!))
        })
        let tempURL = try Self.makeAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "m")
            XCTFail("Expected API error")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .apiError(500, "server exploded"))
        }
    }

    func testProcessTranscriptMapsMalformedChatResponseToInvalidResponse() async throws {
        let service = TranscriptionService(transport: StubTransport { request in
            (Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8), Self.httpResponse(statusCode: 200, url: request.url!))
        })

        do {
            _ = try await service.processTranscript(
                "raw transcript",
                apiKey: "key",
                mode: .cleanUp,
                model: "llama-3.3-70b-versatile"
            )
            XCTFail("Expected invalid response")
        } catch let error as TranscriptionService.TranscriptionError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testTranscribePropagatesTimeoutAndOfflineErrors() async throws {
        for code in [URLError.timedOut, .notConnectedToInternet] {
            let service = TranscriptionService(transport: StubTransport { _ in
                throw URLError(code)
            })
            let tempURL = try Self.makeAudioFile()
            defer { try? FileManager.default.removeItem(at: tempURL) }

            do {
                _ = try await service.transcribe(audioFileURL: tempURL, apiKey: "key", model: "m")
                XCTFail("Expected URL error \(code)")
            } catch let error as URLError {
                XCTAssertEqual(error.code, code)
            }
        }
    }
}

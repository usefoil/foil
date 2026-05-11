import Foundation

protocol TranscriptionTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: TranscriptionTransport {}

struct TranscriptionService {
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private let chatEndpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let transport: TranscriptionTransport

    init(transport: TranscriptionTransport = URLSession.shared) {
        self.transport = transport
    }

    func transcribe(audioFileURL: URL, apiKey: String, model: String, format: AudioFormat = .wav, language: Language = .auto) async throws -> String {
        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try buildMultipartBody(
            audioFileURL: audioFileURL, model: model, format: format, language: language, boundary: boundary
        )
        let audioSize = fileSize(at: audioFileURL)
        let bodySize = request.httpBody?.count ?? 0
        DiagnosticLog.write(
            "transcribe: sending format=\(format.rawValue) audioBytes=\(audioSize) bodyBytes=\(bodySize) model=\(model) language=\(language.rawValue)"
        )

        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            DiagnosticLog.write("transcribe: invalid response type")
            throw TranscriptionError.invalidResponse
        }
        DiagnosticLog.write("transcribe: response status=\(http.statusCode) responseBytes=\(data.count)")

        switch http.statusCode {
        case 200:
            guard let text = String(data: data, encoding: .utf8) else {
                DiagnosticLog.write("transcribe: failed to decode response as UTF-8")
                throw TranscriptionError.invalidResponse
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            DiagnosticLog.write("transcribe: success textLength=\(trimmed.count)")
            return trimmed
        case 401:
            DiagnosticLog.write("transcribe: invalid API key")
            throw TranscriptionError.invalidApiKey
        case 413:
            DiagnosticLog.write("transcribe: file too large")
            throw TranscriptionError.fileTooLarge
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            DiagnosticLog.write("transcribe: API error status=\(http.statusCode) bodyLength=\(body.count)")
            throw TranscriptionError.apiError(http.statusCode, body)
        }
    }

    func processTranscript(
        _ transcript: String,
        apiKey: String,
        mode: TranscriptProcessingMode,
        model: String
    ) async throws -> String {
        guard mode != .raw else { return transcript }
        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try buildTranscriptProcessingBody(transcript: transcript, mode: mode, model: model)

        DiagnosticLog.write("processTranscript: sending mode=\(mode.rawValue) model=\(model) inputLength=\(transcript.count)")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            DiagnosticLog.write("processTranscript: invalid response type")
            throw TranscriptionError.invalidResponse
        }
        DiagnosticLog.write("processTranscript: response status=\(http.statusCode) responseBytes=\(data.count)")

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                throw TranscriptionError.invalidResponse
            }
            DiagnosticLog.write("processTranscript: success outputLength=\(content.count)")
            return content
        case 401:
            throw TranscriptionError.invalidApiKey
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.apiError(http.statusCode, body)
        }
    }

    func buildTranscriptProcessingBody(
        transcript: String,
        mode: TranscriptProcessingMode,
        model: String
    ) throws -> Data {
        let request = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: mode.promptInstruction),
                .init(role: "user", content: transcript)
            ],
            temperature: 0.2,
            maxCompletionTokens: 1024
        )
        return try JSONEncoder().encode(request)
    }

    func buildMultipartBody(audioFileURL: URL, model: String, format: AudioFormat, language: Language = .auto, boundary: String) throws -> Data {
        let audioData = try Data(contentsOf: audioFileURL)
        var body = Data()

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendString("\(model)\r\n")

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.appendString("text\r\n")

        if language != .auto {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            body.appendString("\(language.rawValue)\r\n")
        }

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(format.filename)\"\r\n")
        body.appendString("Content-Type: \(format.contentType)\r\n\r\n")
        body.append(audioData)
        body.appendString("\r\n")

        body.appendString("--\(boundary)--\r\n")
        return body
    }

    enum TranscriptionError: Error, Equatable {
        case invalidResponse
        case invalidApiKey
        case fileTooLarge
        case apiError(Int, String)
    }

    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? -1)
    }

    private struct ChatCompletionRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let maxCompletionTokens: Int

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxCompletionTokens = "max_completion_tokens"
        }

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct ChatCompletionResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String
        }
    }
}

extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}

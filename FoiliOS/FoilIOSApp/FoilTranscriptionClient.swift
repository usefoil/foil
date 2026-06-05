import Foundation

protocol FoilTranscriptionUploading {
    func upload(for request: URLRequest, from body: Data) async throws -> (Data, URLResponse)
}

extension URLSession: FoilTranscriptionUploading {}

struct FoilTranscriptionClient {
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private let model = "whisper-large-v3-turbo"
    private let transport: FoilTranscriptionUploading
    private let boundaryProvider: () -> String

    init(
        transport: FoilTranscriptionUploading = URLSession.shared,
        boundaryProvider: @escaping () -> String = { "Boundary-\(UUID().uuidString)" }
    ) {
        self.transport = transport
        self.boundaryProvider = boundaryProvider
    }

    func transcribe(audioFileURL: URL, apiKey: String) async throws -> String {
        let boundary = boundaryProvider()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try buildMultipartBody(audioFileURL: audioFileURL, boundary: boundary)
        let (data, response) = try await transport.upload(for: request, from: body)

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw TranscriptionError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildMultipartBody(audioFileURL: URL, boundary: String) throws -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("\(model)\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: audio/mp4\r\n\r\n")
        body.append(try Data(contentsOf: audioFileURL))
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

enum TranscriptionError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case missingAPIKey
    case missingRecording

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid transcription response"
        case .httpStatus(let status):
            "Transcription failed with HTTP \(status)"
        case .missingAPIKey:
            "Groq key needed"
        case .missingRecording:
            "No recording available"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

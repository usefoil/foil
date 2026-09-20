import Foundation

private struct AdapterRequest: Decodable {
    let schemaVersion: Int
    let operation: String
    let id: String
    let input: String
    let activeGroup: String?
    let enabled: Bool
    let rules: [LocalCorrectionRule]

    enum CodingKeys: String, CodingKey {
        case operation, id, input, enabled, rules
        case schemaVersion = "schema_version"
        case activeGroup = "active_group"
    }
}

private struct AdapterReply: Encodable {
    let schemaVersion: Int
    let id: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case id, text
        case schemaVersion = "schema_version"
    }
}

private let decoder = JSONDecoder()
private let encoder = JSONEncoder()
private var hadFailure = false

while let line = readLine() {
    do {
        let request = try decoder.decode(AdapterRequest.self, from: Data(line.utf8))
        guard request.schemaVersion == 1, request.operation == "correct" else {
            throw AdapterError.unsupportedRequest
        }
        let compiled = try LocalCorrectionEngine.compile(request.rules)
        let result = LocalCorrectionEngine.correct(
            request.input,
            activeGroup: request.activeGroup,
            enabled: request.enabled,
            compiled: compiled
        )
        let reply = AdapterReply(schemaVersion: 1, id: request.id, text: result.text)
        FileHandle.standardOutput.write(try encoder.encode(reply))
        FileHandle.standardOutput.write(Data([0x0A]))
    } catch {
        hadFailure = true
        FileHandle.standardError.write(Data("local-corrections-adapter: request failed\n".utf8))
        break
    }
}

if hadFailure {
    exit(1)
}

private enum AdapterError: Error {
    case unsupportedRequest
}

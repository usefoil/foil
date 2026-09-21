import Foundation

enum AgentAccessContract {
    static let schemaVersion = 1
    static let apiVersion = "v1"
    static let serviceName = "Foil Agent Access"
}

enum AgentAccessProposalState: String, Codable, CaseIterable, Equatable {
    case pending
    case applied
    case rejected
    case discarded
}

struct AgentAccessLimits: Codable, Equatable {
    static let standard = AgentAccessLimits(
        maximumHeaderBytes: 16 * 1024,
        maximumBodyBytes: 64 * 1024,
        maximumCorrectionPairs: 50,
        maximumSpokenFormsPerPair: 10,
        maximumPhraseScalars: 256,
        requestDeadlineSeconds: 5
    )

    let maximumHeaderBytes: Int
    let maximumBodyBytes: Int
    let maximumCorrectionPairs: Int
    let maximumSpokenFormsPerPair: Int
    let maximumPhraseScalars: Int
    let requestDeadlineSeconds: Int

    enum CodingKeys: String, CodingKey {
        case maximumHeaderBytes = "maximum_header_bytes"
        case maximumBodyBytes = "maximum_body_bytes"
        case maximumCorrectionPairs = "maximum_correction_pairs"
        case maximumSpokenFormsPerPair = "maximum_spoken_forms_per_pair"
        case maximumPhraseScalars = "maximum_phrase_scalars"
        case requestDeadlineSeconds = "request_deadline_seconds"
    }
}

struct AgentAccessInstructionsResponse: Codable, Equatable {
    let schemaVersion: Int
    let requestID: String
    let service: String
    let apiVersion: String
    let availableOperations: [String]
    let bootstrapCommand: String
    let privacy: [String]
    let limits: AgentAccessLimits

    init(requestID: String, socketPath: String, limits: AgentAccessLimits = .standard) {
        schemaVersion = AgentAccessContract.schemaVersion
        self.requestID = requestID
        service = AgentAccessContract.serviceName
        apiVersion = AgentAccessContract.apiVersion
        availableOperations = ["get_instructions", "get_openapi"]
        bootstrapCommand = AgentAccessInstructionsResponse.bootstrapCommand(socketPath: socketPath)
        privacy = [
            "This contract host exposes instructions and its OpenAPI document only.",
            "It does not expose History, audio, credentials, provider configuration, project files, clipboard contents, or the active application.",
            "It accepts no Vocabulary mutations in this tranche."
        ]
        self.limits = limits
    }

    static func bootstrapCommand(socketPath: String) -> String {
        let escapedPath = socketPath.replacingOccurrences(of: "'", with: "'\\''")
        return "/usr/bin/curl --silent --show-error --retry 10 --retry-all-errors --retry-delay 1 --unix-socket '\(escapedPath)' http://foil/v1/instructions"
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case service
        case apiVersion = "api_version"
        case availableOperations = "available_operations"
        case bootstrapCommand = "bootstrap_command"
        case privacy
        case limits
    }
}

struct AgentAccessErrorBody: Codable, Equatable {
    let schemaVersion: Int
    let requestID: String
    let error: AgentAccessErrorDetail

    init(requestID: String, code: String, message: String) {
        schemaVersion = AgentAccessContract.schemaVersion
        self.requestID = requestID
        error = AgentAccessErrorDetail(code: code, message: message)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case error
    }
}

struct AgentAccessErrorDetail: Codable, Equatable {
    let code: String
    let message: String
}

import Foundation

enum AgentAccessContract {
    static let schemaVersion = 1
    static let apiVersion = "v1"
    static let serviceName = "Foil Agent Access"
}

enum AgentAccessPresentationState: String, Equatable {
    case off
    case starting
    case running
    case error

    var label: String {
        switch self {
        case .off: "Off"
        case .starting: "Starting…"
        case .running: "Running"
        case .error: "Could not start"
        }
    }
}

enum AgentAccessProposalState: String, Codable, CaseIterable, Equatable, Sendable {
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
    let openAPIPath: String
    let openAPICommand: String
    let unavailableBehavior: String
    let privacy: [String]
    let limits: AgentAccessLimits

    init(requestID: String, socketPath: String, limits: AgentAccessLimits = .standard) {
        schemaVersion = AgentAccessContract.schemaVersion
        self.requestID = requestID
        service = AgentAccessContract.serviceName
        apiVersion = AgentAccessContract.apiVersion
        availableOperations = [
            "get_instructions",
            "get_openapi",
            "list_vocabulary_scopes",
            "list_vocabulary",
            "preview_vocabulary_corrections",
            "verify_vocabulary_targets",
            "preview_effective_vocabulary",
            "propose_vocabulary_corrections",
            "get_vocabulary_proposal_status",
            "request_vocabulary_action",
            "get_vocabulary_action_status"
        ]
        bootstrapCommand = AgentAccessInstructionsResponse.bootstrapCommand(socketPath: socketPath)
        openAPIPath = "/v1/openapi.json"
        openAPICommand = AgentAccessInstructionsResponse.openAPICommand(socketPath: socketPath)
        unavailableBehavior = "If Foil is closed or Agent Access is off, the command exits nonzero within 12 seconds and no JSON response is available."
        privacy = [
            "Local processes running as the same macOS user can read the allowed Vocabulary fields while Agent Access is enabled.",
            "It does not expose History, audio, credentials, provider configuration, project files, clipboard contents, or the active application.",
            "Vocabulary endpoints expose names, terms, corrections, and executable-rule settings without source records, source apps, or timestamps.",
            "Preview validates hypothetical corrections in memory and never saves them.",
            "Proposals and action requests remain inert until the user approves each change inside Foil. Agent claims of approval are never accepted."
        ]
        self.limits = limits
    }

    static func bootstrapCommand(socketPath: String) -> String {
        let escapedPath = socketPath.replacingOccurrences(of: "'", with: "'\\''")
        return "/usr/bin/curl --silent --show-error --connect-timeout 1 --max-time 12 --retry 10 --retry-all-errors --retry-delay 1 --unix-socket '\(escapedPath)' http://foil/v1/instructions"
    }

    static func openAPICommand(socketPath: String) -> String {
        let escapedPath = socketPath.replacingOccurrences(of: "'", with: "'\\''")
        return "/usr/bin/curl --silent --show-error --max-time 12 --unix-socket '\(escapedPath)' http://foil/v1/openapi.json"
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case service
        case apiVersion = "api_version"
        case availableOperations = "available_operations"
        case bootstrapCommand = "bootstrap_command"
        case openAPIPath = "openapi_path"
        case openAPICommand = "openapi_command"
        case unavailableBehavior = "unavailable_behavior"
        case privacy
        case limits
    }
}

struct AgentAccessVocabularyReadModel: Encodable, Equatable, Sendable {
    let scopes: [AgentAccessVocabularyScope]
    let terms: [AgentAccessVocabularyTerm]
    let corrections: [AgentAccessVocabularyCorrection]
    let localCorrectionsEnabled: Bool
    let suppressionRules: [LocalCorrectionRule]
    let catalogRules: [LocalCorrectionRule]

    init(
        scopes: [AgentAccessVocabularyScope],
        terms: [AgentAccessVocabularyTerm],
        corrections: [AgentAccessVocabularyCorrection],
        localCorrectionsEnabled: Bool,
        suppressionRules: [LocalCorrectionRule] = [],
        catalogRules: [LocalCorrectionRule] = []
    ) {
        self.scopes = scopes
        self.terms = terms
        self.corrections = corrections
        self.localCorrectionsEnabled = localCorrectionsEnabled
        self.suppressionRules = suppressionRules
        self.catalogRules = catalogRules
    }
}

struct AgentAccessVocabularyScope: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let isDefault: Bool
    let isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case isDefault = "is_default"
        case isEnabled = "is_enabled"
    }
}

struct AgentAccessVocabularyTerm: Codable, Equatable, Sendable {
    let id: String
    let term: String
    let note: String?
}

struct AgentAccessVocabularyCorrection: Codable, Equatable, Sendable {
    let id: String
    let writtenAs: String
    let correctVersion: String
    let note: String?
    let localRule: AgentAccessLocalRule?

    enum CodingKeys: String, CodingKey {
        case id, note
        case writtenAs = "written_as"
        case correctVersion = "correct_version"
        case localRule = "local_rule"
    }
}

struct AgentAccessLocalRule: Codable, Equatable, Sendable {
    let enabled: Bool
    let caseSensitive: Bool
    let scopeID: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case caseSensitive = "case_sensitive"
        case scopeID = "scope_id"
    }
}

struct AgentAccessScopesResponse: Codable, Equatable {
    let schemaVersion = AgentAccessContract.schemaVersion
    let requestID: String
    let scopes: [AgentAccessVocabularyScope]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case scopes
    }
}

struct AgentAccessVocabularyResponse: Codable, Equatable {
    let schemaVersion = AgentAccessContract.schemaVersion
    let requestID: String
    let localCorrectionsEnabled: Bool
    let terms: [AgentAccessVocabularyTerm]
    let corrections: [AgentAccessVocabularyCorrection]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case localCorrectionsEnabled = "local_corrections_enabled"
        case terms, corrections
    }
}

struct AgentAccessPreviewRequest: Codable, Equatable {
    let corrections: [AgentAccessPreviewCorrection]
}

struct AgentAccessPreviewCorrection: Codable, Equatable {
    let spokenForms: [String]
    let replacement: String
    let scopeID: String?
    let caseSensitive: Bool

    enum CodingKeys: String, CodingKey {
        case spokenForms = "spoken_forms"
        case replacement
        case scopeID = "scope_id"
        case caseSensitive = "case_sensitive"
    }

    init(spokenForms: [String], replacement: String, scopeID: String?, caseSensitive: Bool) {
        self.spokenForms = spokenForms
        self.replacement = replacement
        self.scopeID = scopeID
        self.caseSensitive = caseSensitive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spokenForms = try container.decode([String].self, forKey: .spokenForms)
        replacement = try container.decode(String.self, forKey: .replacement)
        scopeID = try container.decodeIfPresent(String.self, forKey: .scopeID)
        caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
    }
}

struct AgentAccessPreviewResponse: Codable, Equatable {
    let schemaVersion = AgentAccessContract.schemaVersion
    let requestID: String
    let valid: Bool
    let issues: [AgentAccessPreviewIssue]
    let normalizedCorrections: [AgentAccessPreviewCorrection]
    let examples: [AgentAccessPreviewExample]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case valid, issues, examples
        case normalizedCorrections = "normalized_corrections"
    }
}

struct AgentAccessPreviewIssue: Codable, Equatable {
    let code: String
    let message: String
    let correctionIndex: Int?

    enum CodingKeys: String, CodingKey {
        case code, message
        case correctionIndex = "correction_index"
    }
}

struct AgentAccessPreviewExample: Codable, Equatable {
    let input: String
    let output: String
    let replacementCount: Int

    enum CodingKeys: String, CodingKey {
        case input, output
        case replacementCount = "replacement_count"
    }
}

struct AgentAccessTargetVerificationRequest: Decodable {
    let appPaths: [String]
    let expectedGroupID: String?

    enum CodingKeys: String, CodingKey {
        case appPaths = "app_paths"
        case expectedGroupID = "expected_group_id"
    }
}

struct AgentAccessVerifiedTarget: Encodable {
    let appPath: String
    let bundleID: String
    let displayName: String
    let resolvedGroupID: String
    let resolvedGroupName: String
    let exactPathMatch: Bool
    let matchesExpectedGroup: Bool?

    enum CodingKeys: String, CodingKey {
        case appPath = "app_path"
        case bundleID = "bundle_id"
        case displayName = "display_name"
        case resolvedGroupID = "resolved_group_id"
        case resolvedGroupName = "resolved_group_name"
        case exactPathMatch = "exact_path_match"
        case matchesExpectedGroup = "matches_expected_group"
    }
}

struct AgentAccessTargetVerificationResponse: Encodable {
    let schemaVersion = AgentAccessContract.schemaVersion
    let requestID: String
    let targets: [AgentAccessVerifiedTarget]
    let allMatchExpectedGroup: Bool?
    let groupExclusiveToRequestedPaths: Bool?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case targets
        case allMatchExpectedGroup = "all_match_expected_group"
        case groupExclusiveToRequestedPaths = "group_exclusive_to_requested_paths"
    }
}

struct AgentAccessEffectivePreviewRequest: Decodable {
    let appPath: String
    let sampleText: String

    enum CodingKeys: String, CodingKey {
        case appPath = "app_path"
        case sampleText = "sample_text"
    }
}

struct AgentAccessEffectiveRule: Encodable {
    let ruleID: String
    let correctionID: String?
    let source: String
    let replacement: String?
    let scopeID: String?
    let caseSensitive: Bool
    let suppressesGlobal: Bool

    enum CodingKeys: String, CodingKey {
        case ruleID = "rule_id"
        case correctionID = "correction_id"
        case source, replacement
        case scopeID = "scope_id"
        case caseSensitive = "case_sensitive"
        case suppressesGlobal = "suppresses_global"
    }
}

struct AgentAccessEffectivePreviewResponse: Encodable {
    let schemaVersion = AgentAccessContract.schemaVersion
    let requestID: String
    let target: AgentAccessVerifiedTarget
    let localCorrectionsEnabled: Bool
    let outputText: String
    let replacementCount: Int
    let rules: [AgentAccessEffectiveRule]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case target
        case localCorrectionsEnabled = "local_corrections_enabled"
        case outputText = "output_text"
        case replacementCount = "replacement_count"
        case rules
    }
}

struct AgentAccessProposalResponse: Codable, Equatable {
    let schemaVersion = AgentAccessContract.schemaVersion
    let requestID: String
    let clientRequestID: String
    let proposalID: String
    let state: AgentAccessProposalState
    let replayed: Bool
    let createdAt: Date
    let updatedAt: Date

    init(requestID: String, receipt: VocabularyProposalReceipt, replayed: Bool) {
        self.requestID = requestID
        clientRequestID = receipt.requestID
        proposalID = receipt.proposalID
        state = receipt.state
        self.replayed = replayed
        createdAt = receipt.createdAt
        updatedAt = receipt.updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case clientRequestID = "client_request_id"
        case proposalID = "proposal_id"
        case state, replayed
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct AgentAccessActionResponse: Codable, Equatable {
    let schemaVersion = AgentAccessContract.schemaVersion
    let requestID: String
    let clientRequestID: String
    let actionID: String
    let groupID: String?
    let state: AgentAccessActionState
    let replayed: Bool
    let createdAt: Date
    let updatedAt: Date
    let approvedAt: Date?

    init(requestID: String, record: AgentAccessActionRecord, replayed: Bool) {
        self.requestID = requestID
        clientRequestID = record.request.requestID
        actionID = record.id
        groupID = record.request.action == .createCleanupGroup ? record.id : record.request.groupID
        state = record.state
        self.replayed = replayed
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        approvedAt = record.approvedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case clientRequestID = "client_request_id"
        case actionID = "action_id"
        case groupID = "group_id"
        case state, replayed
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case approvedAt = "approved_at"
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

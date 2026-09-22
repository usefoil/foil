import CryptoKit
import Foundation

enum VocabularyProposalContract {
    static let schemaVersion = 1
}

struct VocabularyProposalScope: Codable, Equatable, Sendable {
    let kind: String
    let id: String
}

struct VocabularyProposalCorrection: Codable, Equatable, Sendable {
    let spokenForms: [String]
    let replacement: String
    let note: String?
    let caseSensitive: Bool

    init(
        spokenForms: [String],
        replacement: String,
        note: String? = nil,
        caseSensitive: Bool = false
    ) {
        self.spokenForms = spokenForms
        self.replacement = replacement
        self.note = note
        self.caseSensitive = caseSensitive
    }

    enum CodingKeys: String, CodingKey {
        case spokenForms = "spoken_forms"
        case replacement, note
        case caseSensitive = "case_sensitive"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spokenForms = try container.decode([String].self, forKey: .spokenForms)
        replacement = try container.decode(String.self, forKey: .replacement)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
    }
}

struct VocabularyProposalRequest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let requestID: String
    let scope: VocabularyProposalScope
    let corrections: [VocabularyProposalCorrection]

    init(
        schemaVersion: Int = VocabularyProposalContract.schemaVersion,
        requestID: String,
        scope: VocabularyProposalScope,
        corrections: [VocabularyProposalCorrection]
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.scope = scope
        self.corrections = corrections
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case scope, corrections
    }

    func canonicalized() -> VocabularyProposalRequest {
        VocabularyProposalRequest(
            schemaVersion: schemaVersion,
            requestID: Self.normalize(requestID),
            scope: .init(kind: Self.normalize(scope.kind), id: Self.normalize(scope.id)),
            corrections: corrections.map { correction in
                VocabularyProposalCorrection(
                    spokenForms: correction.spokenForms.map(Self.normalize),
                    replacement: Self.normalize(correction.replacement),
                    note: Self.normalizeOptional(correction.note),
                    caseSensitive: correction.caseSensitive
                )
            }
        )
    }

    func canonicalPayloadDigest() throws -> String {
        struct CanonicalPayload: Encodable {
            let schemaVersion: Int
            let scope: VocabularyProposalScope
            let corrections: [VocabularyProposalCorrection]

            enum CodingKeys: String, CodingKey {
                case schemaVersion = "schema_version"
                case scope, corrections
            }
        }

        let request = canonicalized()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(CanonicalPayload(
            schemaVersion: request.schemaVersion,
            scope: request.scope,
            corrections: request.corrections
        ))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    private static func normalizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalize(value)
        return normalized.isEmpty ? nil : normalized
    }
}

struct VocabularyProposal: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let requestID: String
    let requestHash: String
    let reviewHash: String?
    let state: AgentAccessProposalState
    let scope: VocabularyProposalScope
    let corrections: [VocabularyProposalCorrection]
    let snapshotToken: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case requestID = "request_id"
        case requestHash = "request_hash"
        case reviewHash = "review_hash"
        case state, scope, corrections
        case snapshotToken = "snapshot_token"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        requestID: String,
        requestHash: String,
        reviewHash: String? = nil,
        state: AgentAccessProposalState,
        scope: VocabularyProposalScope,
        corrections: [VocabularyProposalCorrection],
        snapshotToken: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.requestID = requestID
        self.requestHash = requestHash
        self.reviewHash = reviewHash
        self.state = state
        self.scope = scope
        self.corrections = corrections
        self.snapshotToken = snapshotToken
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func receipt() -> VocabularyProposalReceipt {
        VocabularyProposalReceipt(
            requestID: requestID,
            proposalID: id,
            state: state,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct VocabularyProposalReceipt: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let requestID: String
    let proposalID: String
    let state: AgentAccessProposalState
    let createdAt: Date
    let updatedAt: Date

    init(
        schemaVersion: Int = VocabularyProposalContract.schemaVersion,
        requestID: String,
        proposalID: String,
        state: AgentAccessProposalState,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.proposalID = proposalID
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case proposalID = "proposal_id"
        case state
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct VocabularyProposalSubmission: Equatable, Sendable {
    let receipt: VocabularyProposalReceipt
    let wasReplay: Bool
}

struct VocabularyProposalSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = VocabularyProposalContract.schemaVersion

    let schemaVersion: Int
    let revision: Int
    let proposals: [VocabularyProposal]

    init(revision: Int = 0, proposals: [VocabularyProposal] = []) {
        schemaVersion = Self.currentSchemaVersion
        self.revision = revision
        self.proposals = proposals
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case revision, proposals
    }
}

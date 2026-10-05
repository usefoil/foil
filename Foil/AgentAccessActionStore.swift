import CryptoKit
import Foundation

enum AgentAccessActionKind: String, Codable, Sendable {
    case applyProposal = "apply_proposal"
    case setLocalCorrectionsEnabled = "set_local_corrections_enabled"
    case setCorrectionScope = "set_correction_scope"
    case assignAppToGroup = "assign_app_to_group"
}

enum AgentAccessActionState: String, Codable, Sendable {
    case pending
    case approvedPendingApply = "approved_pending_apply"
    case approved
    case rejected
    case cancelledAfterApproval = "cancelled_after_approval"
}

struct AgentAccessActionRequest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let requestID: String
    let action: AgentAccessActionKind
    let proposalID: String?
    let enabled: Bool?
    let correctionID: String?
    let scopeID: String?
    let appBundleID: String?
    let groupID: String?

    init(
        schemaVersion: Int = 1,
        requestID: String,
        action: AgentAccessActionKind,
        proposalID: String? = nil,
        enabled: Bool? = nil,
        correctionID: String? = nil,
        scopeID: String? = nil,
        appBundleID: String? = nil,
        groupID: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.action = action
        self.proposalID = proposalID
        self.enabled = enabled
        self.correctionID = correctionID
        self.scopeID = scopeID
        self.appBundleID = appBundleID
        self.groupID = groupID
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case action
        case proposalID = "proposal_id"
        case enabled
        case correctionID = "correction_id"
        case scopeID = "scope_id"
        case appBundleID = "app_bundle_id"
        case groupID = "group_id"
    }

    func validated() throws -> AgentAccessActionRequest {
        guard schemaVersion == 1,
              !requestID.isEmpty, requestID.utf8.count <= 128,
              requestID.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7e }) else {
            throw AgentAccessActionError.invalidRequest
        }
        let fields: [String?] = [proposalID, correctionID, scopeID, appBundleID, groupID]
        guard fields.compactMap({ $0 }).allSatisfy({
            !$0.isEmpty && $0.count <= 256 && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }) else { throw AgentAccessActionError.invalidRequest }
        switch action {
        case .applyProposal:
            guard let proposalID, UUID(uuidString: proposalID) != nil,
                  enabled == nil, correctionID == nil, scopeID == nil,
                  appBundleID == nil, groupID == nil else { throw AgentAccessActionError.invalidRequest }
        case .setLocalCorrectionsEnabled:
            guard enabled != nil, proposalID == nil, correctionID == nil,
                  scopeID == nil, appBundleID == nil, groupID == nil else {
                throw AgentAccessActionError.invalidRequest
            }
        case .setCorrectionScope:
            guard let correctionID, UUID(uuidString: correctionID) != nil,
                  scopeID != nil, proposalID == nil, enabled == nil,
                  appBundleID == nil, groupID == nil else { throw AgentAccessActionError.invalidRequest }
        case .assignAppToGroup:
            guard let appBundleID, appBundleID.contains("."), !appBundleID.contains("/"),
                  groupID != nil, proposalID == nil, enabled == nil,
                  correctionID == nil, scopeID == nil else { throw AgentAccessActionError.invalidRequest }
        }
        return self
    }

    func digest() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(self)).map { String(format: "%02x", $0) }.joined()
    }
}

struct AgentAccessActionRecord: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let request: AgentAccessActionRequest
    let digest: String
    let targetDigest: String?
    let state: AgentAccessActionState
    let createdAt: Date
    let updatedAt: Date
    let approvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, request, digest, state
        case targetDigest = "target_digest"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case approvedAt = "approved_at"
    }
}

struct AgentAccessActionSnapshot: Codable {
    let schemaVersion: Int
    let revision: Int
    let records: [AgentAccessActionRecord]

    init(revision: Int = 0, records: [AgentAccessActionRecord] = []) {
        schemaVersion = 1
        self.revision = revision
        self.records = records
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case revision, records
    }
}

enum AgentAccessActionError: Error, Equatable, LocalizedError {
    case invalidRequest
    case requestConflict
    case queueFull
    case notFound
    case invalidState
    case targetChanged
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The requested target or scope is no longer available. Review the current Vocabulary and ask for a new request."
        case .requestConflict: "This request ID was already used for a different change."
        case .queueFull: "Review pending agent actions before submitting another."
        case .notFound: "The action request was not found."
        case .invalidState: "The proposal or action is no longer pending, or its validation failed. Review it before trying again."
        case .targetChanged: "This proposal changed after the action request. Apply it in proposal review or ask the agent for a new request."
        case .unavailable: "Foil could not save the action decision. Try again."
        }
    }
}

final class AgentAccessActionStore: @unchecked Sendable {
    let fileURL: URL
    private let lock = NSLock()
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
        self.makeID = makeID
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func load() throws -> AgentAccessActionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return try read()
    }

    func submit(
        _ raw: AgentAccessActionRequest,
        targetDigest: String? = nil,
        targetAvailable: Bool = true
    ) throws -> (AgentAccessActionRecord, Bool) {
        let request = try raw.validated()
        let digest = try request.digest()
        lock.lock()
        defer { lock.unlock() }
        let current = try read()
        if let existing = current.records.first(where: { $0.request.requestID == request.requestID }) {
            guard existing.digest == digest else { throw AgentAccessActionError.requestConflict }
            return (existing, true)
        }
        guard targetAvailable else { throw AgentAccessActionError.invalidRequest }
        if request.action == .applyProposal {
            guard let targetDigest, Self.isDigest(targetDigest) else {
                throw AgentAccessActionError.invalidRequest
            }
        } else if targetDigest != nil {
            throw AgentAccessActionError.invalidRequest
        }
        guard current.records.filter({ $0.state == .pending || $0.state == .approvedPendingApply }).count < 100 else {
            throw AgentAccessActionError.queueFull
        }
        let timestamp = normalizedTimestamp()
        let record = AgentAccessActionRecord(
            id: makeID().uuidString.lowercased(), request: request, digest: digest,
            targetDigest: targetDigest,
            state: .pending, createdAt: timestamp, updatedAt: timestamp,
            approvedAt: nil
        )
        try write(AgentAccessActionSnapshot(revision: current.revision + 1, records: current.records + [record]))
        return (record, false)
    }

    func transition(id: String, to state: AgentAccessActionState) throws -> AgentAccessActionRecord {
        lock.lock()
        defer { lock.unlock() }
        let current = try read()
        guard let index = current.records.firstIndex(where: { $0.id == id }) else {
            throw AgentAccessActionError.notFound
        }
        let existing = current.records[index]
        if existing.state == state { return existing }
        let allowed = (existing.state == .pending && (state == .approvedPendingApply || state == .rejected))
            || (existing.state == .approvedPendingApply && (state == .approved || state == .cancelledAfterApproval))
        guard allowed else { throw AgentAccessActionError.invalidState }
        let timestamp = normalizedTimestamp()
        let updated = AgentAccessActionRecord(
            id: existing.id, request: existing.request, digest: existing.digest,
            targetDigest: existing.targetDigest,
            state: state, createdAt: existing.createdAt, updatedAt: timestamp,
            approvedAt: existing.approvedAt ?? (state == .approvedPendingApply ? timestamp : nil)
        )
        var records = current.records
        records[index] = updated
        try write(AgentAccessActionSnapshot(revision: current.revision + 1, records: records))
        return updated
    }

    private func read() throws -> AgentAccessActionSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else { return AgentAccessActionSnapshot() }
        do {
            let value = try decoder.decode(AgentAccessActionSnapshot.self, from: Data(contentsOf: fileURL))
            guard value.schemaVersion == 1, value.revision >= 0,
                  Set(value.records.map(\.id)).count == value.records.count,
                  Set(value.records.map(\.request.requestID)).count == value.records.count else {
                throw AgentAccessActionError.unavailable
            }
            for record in value.records {
                guard UUID(uuidString: record.id) != nil,
                      try record.request.validated() == record.request,
                      try record.request.digest() == record.digest,
                      (record.request.action == .applyProposal) == (record.targetDigest.map(Self.isDigest) == true),
                      record.createdAt <= record.updatedAt,
                      record.approvedAt.map({ record.createdAt <= $0 && $0 <= record.updatedAt }) ?? true,
                      (record.state == .pending || record.state == .rejected) == (record.approvedAt == nil) else {
                    throw AgentAccessActionError.unavailable
                }
            }
            return value
        } catch { throw AgentAccessActionError.unavailable }
    }

    private func write(_ value: AgentAccessActionSnapshot) throws {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try encoder.encode(value).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { throw AgentAccessActionError.unavailable }
    }

    private func normalizedTimestamp() -> Date {
        Date(timeIntervalSince1970: (now().timeIntervalSince1970 * 1_000).rounded(.down) / 1_000)
    }

    private static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }
}

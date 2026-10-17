import CryptoKit
import Foundation

enum AgentAccessActionKind: String, Codable, Sendable {
    case applyProposal = "apply_proposal"
    case createCleanupGroup = "create_cleanup_group"
    case rescopeProposal = "rescope_proposal"
    case setLocalCorrectionsEnabled = "set_local_corrections_enabled"
    case setCorrectionScope = "set_correction_scope"
    case setCorrectionPolicies = "set_correction_policies"
    case assignAppToGroup = "assign_app_to_group"
}

struct AgentAccessCorrectionPolicy: Codable, Equatable, Sendable {
    let correctionID: String
    let scopeID: String
    let enabled: Bool
    let caseSensitive: Bool
    let suppressedGroupIDs: [String]
    let matchPunctuationVariants: Bool?

    init(
        correctionID: String,
        scopeID: String,
        enabled: Bool,
        caseSensitive: Bool,
        suppressedGroupIDs: [String],
        matchPunctuationVariants: Bool? = nil
    ) {
        self.correctionID = correctionID
        self.scopeID = scopeID
        self.enabled = enabled
        self.caseSensitive = caseSensitive
        self.suppressedGroupIDs = suppressedGroupIDs
        self.matchPunctuationVariants = matchPunctuationVariants
    }

    enum CodingKeys: String, CodingKey {
        case correctionID = "correction_id"
        case scopeID = "scope_id"
        case enabled
        case caseSensitive = "case_sensitive"
        case suppressedGroupIDs = "suppressed_group_ids"
        case matchPunctuationVariants = "match_punctuation_variants"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        correctionID = try container.decode(String.self, forKey: .correctionID)
        scopeID = try container.decode(String.self, forKey: .scopeID)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        caseSensitive = try container.decode(Bool.self, forKey: .caseSensitive)
        suppressedGroupIDs = try container.decode([String].self, forKey: .suppressedGroupIDs)
        matchPunctuationVariants = try container.decodeIfPresent(Bool.self, forKey: .matchPunctuationVariants)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(correctionID, forKey: .correctionID)
        try container.encode(scopeID, forKey: .scopeID)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(caseSensitive, forKey: .caseSensitive)
        try container.encode(suppressedGroupIDs, forKey: .suppressedGroupIDs)
        try container.encodeIfPresent(matchPunctuationVariants, forKey: .matchPunctuationVariants)
    }

    func validated() throws -> AgentAccessCorrectionPolicy {
        guard let id = UUID(uuidString: correctionID),
              !scopeID.isEmpty, scopeID.count <= 256,
              scopeID == scopeID.trimmingCharacters(in: .whitespacesAndNewlines),
              suppressedGroupIDs.count <= 20,
              suppressedGroupIDs.allSatisfy({ !$0.isEmpty && $0.count <= 256 &&
                  $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              Set(suppressedGroupIDs).count == suppressedGroupIDs.count,
              (scopeID == "global" && enabled) || suppressedGroupIDs.isEmpty else {
            throw AgentAccessActionError.invalidRequest
        }
        return AgentAccessCorrectionPolicy(
            correctionID: id.uuidString.lowercased(), scopeID: scopeID,
            enabled: enabled, caseSensitive: caseSensitive,
            suppressedGroupIDs: suppressedGroupIDs.sorted(),
            matchPunctuationVariants: matchPunctuationVariants
        )
    }
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
    let groupName: String?
    let appPaths: [String]?
    let correctionPolicies: [AgentAccessCorrectionPolicy]?

    init(
        schemaVersion: Int = 1,
        requestID: String,
        action: AgentAccessActionKind,
        proposalID: String? = nil,
        enabled: Bool? = nil,
        correctionID: String? = nil,
        scopeID: String? = nil,
        appBundleID: String? = nil,
        groupID: String? = nil,
        groupName: String? = nil,
        appPaths: [String]? = nil,
        correctionPolicies: [AgentAccessCorrectionPolicy]? = nil
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
        self.groupName = groupName
        self.appPaths = appPaths
        self.correctionPolicies = correctionPolicies
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
        case groupName = "group_name"
        case appPaths = "app_paths"
        case correctionPolicies = "correction_policies"
    }

    func validated() throws -> AgentAccessActionRequest {
        guard schemaVersion == 1,
              !requestID.isEmpty, requestID.utf8.count <= 128,
              requestID.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7e }) else {
            throw AgentAccessActionError.invalidRequest
        }
        let fields: [String?] = [proposalID, correctionID, scopeID, appBundleID, groupID, groupName]
        guard fields.compactMap({ $0 }).allSatisfy({
            !$0.isEmpty && $0.count <= 256 && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }) else { throw AgentAccessActionError.invalidRequest }
        var canonicalProposalID = proposalID
        var canonicalCorrectionID = correctionID
        let canonicalPolicies: [AgentAccessCorrectionPolicy]?
        if let correctionPolicies {
            guard (1...50).contains(correctionPolicies.count) else { throw AgentAccessActionError.invalidRequest }
            let normalized = try correctionPolicies.map { try $0.validated() }
            guard Set(normalized.map(\.correctionID)).count == normalized.count else {
                throw AgentAccessActionError.invalidRequest
            }
            canonicalPolicies = normalized.sorted { $0.correctionID < $1.correctionID }
        } else {
            canonicalPolicies = nil
        }
        let canonicalAppPaths: [String]?
        if let appPaths {
            guard (1...8).contains(appPaths.count),
                  appPaths.allSatisfy({ path in
                      path.hasPrefix("/") && path.hasSuffix(".app") &&
                      path.utf8.count <= 1024 &&
                      path == URL(fileURLWithPath: path).standardizedFileURL.path &&
                      !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                  }),
                  Set(appPaths.map { $0.lowercased() }).count == appPaths.count else {
                throw AgentAccessActionError.invalidRequest
            }
            canonicalAppPaths = appPaths.sorted()
        } else {
            canonicalAppPaths = nil
        }
        switch action {
        case .applyProposal:
            guard let proposalID, let parsedID = UUID(uuidString: proposalID),
                  enabled == nil, correctionID == nil, scopeID == nil,
                  appBundleID == nil, groupID == nil, groupName == nil,
                  appPaths == nil, correctionPolicies == nil else { throw AgentAccessActionError.invalidRequest }
            canonicalProposalID = parsedID.uuidString.lowercased()
        case .createCleanupGroup:
            guard let groupName, !groupName.isEmpty, groupName.unicodeScalars.count <= 80,
                  !groupName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  canonicalAppPaths != nil, proposalID == nil, enabled == nil,
                  correctionID == nil, scopeID == nil, appBundleID == nil,
                  groupID == nil, correctionPolicies == nil else { throw AgentAccessActionError.invalidRequest }
        case .rescopeProposal:
            guard let proposalID, let parsedID = UUID(uuidString: proposalID),
                  let groupID, UUID(uuidString: groupID) != nil,
                  canonicalAppPaths != nil, enabled == nil, correctionID == nil,
                  scopeID == nil, appBundleID == nil, groupName == nil,
                  correctionPolicies == nil else {
                throw AgentAccessActionError.invalidRequest
            }
            canonicalProposalID = parsedID.uuidString.lowercased()
        case .setLocalCorrectionsEnabled:
            guard enabled != nil, proposalID == nil, correctionID == nil,
                  scopeID == nil, appBundleID == nil, groupID == nil,
                  groupName == nil, appPaths == nil, correctionPolicies == nil else {
                throw AgentAccessActionError.invalidRequest
            }
        case .setCorrectionScope:
            guard let correctionID, let parsedID = UUID(uuidString: correctionID),
                  scopeID != nil, proposalID == nil, enabled == nil,
                  appBundleID == nil, groupID == nil, groupName == nil,
                  appPaths == nil, correctionPolicies == nil else { throw AgentAccessActionError.invalidRequest }
            canonicalCorrectionID = parsedID.uuidString.lowercased()
        case .setCorrectionPolicies:
            guard canonicalPolicies != nil, proposalID == nil, correctionID == nil,
                  scopeID == nil, appBundleID == nil, groupID == nil,
                  groupName == nil, appPaths == nil else {
                throw AgentAccessActionError.invalidRequest
            }
        case .assignAppToGroup:
            guard let appBundleID, appBundleID.contains("."), !appBundleID.contains("/"),
                  groupID != nil, proposalID == nil, enabled == nil,
                  correctionID == nil, scopeID == nil, groupName == nil,
                  appPaths == nil, correctionPolicies == nil else { throw AgentAccessActionError.invalidRequest }
        }
        return AgentAccessActionRequest(
            schemaVersion: schemaVersion, requestID: requestID, action: action,
            proposalID: canonicalProposalID, enabled: enabled,
            correctionID: canonicalCorrectionID, scopeID: scopeID,
            appBundleID: appBundleID, groupID: groupID,
            groupName: groupName, appPaths: canonicalAppPaths,
            correctionPolicies: canonicalPolicies
        )
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
    let resultDigest: String?
    let state: AgentAccessActionState
    let createdAt: Date
    let updatedAt: Date
    let approvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, request, digest, state
        case targetDigest = "target_digest"
        case resultDigest = "result_digest"
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
    case validation(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The requested target or scope is no longer available. Review the current Vocabulary and ask for a new request."
        case .requestConflict: "This request ID was already used for a different change."
        case .queueFull: "Review pending agent actions before submitting another."
        case .notFound: "The action request was not found."
        case .invalidState: "The proposal or action is no longer pending, or its validation failed. Review it before trying again."
        case .targetChanged: "The target changed after this action request. Review the current state and ask the agent for a new request."
        case let .validation(message): message
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
        resultDigest: String? = nil,
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
        if request.action == .applyProposal || request.action == .rescopeProposal ||
            request.action == .setCorrectionPolicies {
            guard let targetDigest, Self.isDigest(targetDigest) else {
                throw AgentAccessActionError.invalidRequest
            }
        } else if targetDigest != nil {
            throw AgentAccessActionError.invalidRequest
        }
        if request.action == .rescopeProposal || request.action == .setCorrectionPolicies {
            guard let resultDigest, Self.isDigest(resultDigest) else {
                throw AgentAccessActionError.invalidRequest
            }
        } else if resultDigest != nil {
            throw AgentAccessActionError.invalidRequest
        }
        guard current.records.filter({ $0.state == .pending || $0.state == .approvedPendingApply }).count < 100 else {
            throw AgentAccessActionError.queueFull
        }
        let timestamp = normalizedTimestamp()
        let record = AgentAccessActionRecord(
            id: makeID().uuidString.lowercased(), request: request, digest: digest,
            targetDigest: targetDigest, resultDigest: resultDigest,
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
        let timestamp = max(normalizedTimestamp(), existing.updatedAt)
        let updated = AgentAccessActionRecord(
            id: existing.id, request: existing.request, digest: existing.digest,
            targetDigest: existing.targetDigest, resultDigest: existing.resultDigest,
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
                      (record.request.action == .applyProposal || record.request.action == .rescopeProposal ||
                          record.request.action == .setCorrectionPolicies)
                          == (record.targetDigest.map(Self.isDigest) == true),
                      (record.request.action == .rescopeProposal || record.request.action == .setCorrectionPolicies)
                          == (record.resultDigest.map(Self.isDigest) == true),
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

enum AgentAccessPolicyBatchPlanner {
    struct Plan {
        let rules: [LocalCorrectionRule]
        let localCorrectionsEnabled: Bool
        let targetDigest: String
        let resultDigest: String
    }

    private struct DigestInput: Encodable {
        let model: AgentAccessVocabularyReadModel
        let routingGroups: [CleanupGroup]
    }

    static func digest(model: AgentAccessVocabularyReadModel, groups: [CleanupGroup]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(DigestInput(model: model, routingGroups: groups))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func plan(
        _ rawRequest: AgentAccessActionRequest,
        model: AgentAccessVocabularyReadModel,
        groups: [CleanupGroup]
    ) throws -> Plan {
        let request = try rawRequest.validated()
        guard request.action == .setCorrectionPolicies,
              let policies = request.correctionPolicies else {
            throw AgentAccessActionError.invalidRequest
        }
        let projectedRules = model.corrections.compactMap { correction -> LocalCorrectionRule? in
            guard let local = correction.localRule else { return nil }
            return LocalCorrectionRule(
                id: "vocabulary:\(correction.id)", source: correction.writtenAs,
                replacement: correction.correctVersion, group: local.scopeID,
                enabled: local.enabled, caseSensitive: local.caseSensitive,
                matchPunctuationVariants: local.matchPunctuationVariants
            )
        } + model.suppressionRules
        var rules = model.catalogRules.isEmpty ? projectedRules : model.catalogRules
        let correctionsByID = Dictionary(uniqueKeysWithValues: model.corrections.map { ($0.id, $0) })
        let enabledGroupIDs = Set(model.scopes.filter(\.isEnabled).map(\.id))
        for policy in policies {
            guard let correction = correctionsByID[policy.correctionID],
                  policy.scopeID == "global" || enabledGroupIDs.contains(policy.scopeID),
                  policy.suppressedGroupIDs.allSatisfy(enabledGroupIDs.contains) else {
                throw AgentAccessActionError.invalidRequest
            }
            let ruleID = "vocabulary:\(policy.correctionID)"
            let suppressionPrefix = "suppression:\(policy.correctionID):"
            let punctuationVariants = policy.matchPunctuationVariants ??
                correction.localRule?.matchPunctuationVariants ?? false
            rules.removeAll { $0.id == ruleID || $0.id.hasPrefix(suppressionPrefix) }
            rules.append(LocalCorrectionRule(
                id: ruleID, source: correction.writtenAs, replacement: correction.correctVersion,
                group: policy.scopeID == "global" ? nil : policy.scopeID,
                enabled: policy.enabled, caseSensitive: policy.caseSensitive,
                matchPunctuationVariants: punctuationVariants
            ))
            for groupID in policy.suppressedGroupIDs {
                rules.append(LocalCorrectionRule(
                    id: suppressionPrefix + groupID,
                    source: correction.writtenAs, replacement: correction.writtenAs,
                    group: groupID, enabled: true,
                    caseSensitive: policy.caseSensitive,
                    matchPunctuationVariants: punctuationVariants,
                    suppressesGlobal: true
                ))
            }
        }
        do {
            _ = try LocalCorrectionEngine.compile(rules)
        } catch let error as LocalCorrectionValidationError {
            throw AgentAccessActionError.validation(error.description)
        }
        let policyByID = Dictionary(uniqueKeysWithValues: policies.map { ($0.correctionID, $0) })
        let updatedCorrections = model.corrections.map { correction in
            guard let policy = policyByID[correction.id] else { return correction }
            let punctuationVariants = policy.matchPunctuationVariants ??
                correction.localRule?.matchPunctuationVariants ?? false
            return AgentAccessVocabularyCorrection(
                id: correction.id, writtenAs: correction.writtenAs,
                correctVersion: correction.correctVersion, note: correction.note,
                localRule: AgentAccessLocalRule(
                    enabled: policy.enabled, caseSensitive: policy.caseSensitive,
                    scopeID: policy.scopeID == "global" ? nil : policy.scopeID,
                    matchPunctuationVariants: punctuationVariants
                )
            )
        }
        let after = AgentAccessVocabularyReadModel(
            scopes: model.scopes, terms: model.terms,
            corrections: updatedCorrections,
            localCorrectionsEnabled: request.enabled ?? model.localCorrectionsEnabled,
            suppressionRules: rules.filter(\.suppressesGlobal),
            catalogRules: rules,
            scopedTerms: model.scopedTerms
        )
        return Plan(
            rules: rules,
            localCorrectionsEnabled: after.localCorrectionsEnabled,
            targetDigest: try digest(model: model, groups: groups),
            resultDigest: try digest(model: after, groups: groups)
        )
    }
}

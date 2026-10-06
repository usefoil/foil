import CryptoKit
import Darwin
import Foundation
import Security

struct AgentAccessGrantSummary: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let groupID: String
    let appPaths: [String]
    let createdAt: Date
    let expiresAt: Date
    let revokedAt: Date?

    var isRevoked: Bool { revokedAt != nil }
}

struct AgentAccessGrantUse: Codable, Equatable, Identifiable, Sendable {
    let grantID: String
    let objectKind: String
    let objectID: String
    let requestDigest: String
    let createdAt: Date

    var id: String { "\(objectKind):\(objectID)" }
}

struct AgentAccessGrantSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let grants: [StoredAgentAccessGrant]
    let uses: [AgentAccessGrantUse]

    init(grants: [StoredAgentAccessGrant] = [], uses: [AgentAccessGrantUse] = []) {
        schemaVersion = 1
        self.grants = grants
        self.uses = uses
    }
}

struct StoredAgentAccessGrant: Codable, Equatable, Sendable {
    let summary: AgentAccessGrantSummary
    let tokenDigest: String

    enum CodingKeys: String, CodingKey {
        case summary
        case tokenDigest = "token_digest"
    }
}

enum AgentAccessGrantError: Error, Equatable, LocalizedError {
    case invalidName
    case invalidScope
    case unauthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a short name for this agent."
        case .invalidScope: "Choose an enabled Cleanup Group containing only the selected exact app paths."
        case .unauthorized: "This agent's Vocabulary edit access is missing, expired, or revoked."
        case .unavailable: "Foil could not read or save agent permissions. No edit access was granted."
        }
    }
}

final class AgentAccessGrantStore: @unchecked Sendable {
    private let fileURL: URL
    private let now: @Sendable () -> Date
    private let makeToken: @Sendable () throws -> String
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL,
        now: @escaping @Sendable () -> Date = { Date() },
        makeToken: @escaping @Sendable () throws -> String = { try AgentAccessGrantStore.randomToken() }
    ) {
        self.fileURL = fileURL
        self.now = now
        self.makeToken = makeToken
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> AgentAccessGrantSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return try read()
    }

    func create(name rawName: String, groupID: String, appPaths: [String]) throws -> (AgentAccessGrantSummary, String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AgentAccessGrantError.invalidName
        }
        guard groupID != "global", groupID != "default-unassigned-apps",
              (1...8).contains(appPaths.count),
              Set(appPaths.map { $0.lowercased() }).count == appPaths.count,
              appPaths.allSatisfy({ $0.hasPrefix("/") && $0 == URL(fileURLWithPath: $0).standardizedFileURL.path }) else {
            throw AgentAccessGrantError.invalidScope
        }
        let token = try makeToken()
        guard token.hasPrefix("foil_"), token.count >= 45 else { throw AgentAccessGrantError.unavailable }
        let timestamp = now()
        let summary = AgentAccessGrantSummary(
            id: UUID().uuidString.lowercased(), name: name, groupID: groupID,
            appPaths: appPaths.sorted(), createdAt: timestamp,
            expiresAt: timestamp.addingTimeInterval(60 * 60), revokedAt: nil
        )
        let stored = StoredAgentAccessGrant(summary: summary, tokenDigest: Self.digest(token))
        lock.lock()
        defer { lock.unlock() }
        let current = try read()
        guard !current.grants.contains(where: { $0.tokenDigest == stored.tokenDigest }) else {
            throw AgentAccessGrantError.unavailable
        }
        try write(AgentAccessGrantSnapshot(grants: current.grants + [stored], uses: current.uses))
        return (summary, token)
    }

    func authorize(_ token: String) throws -> AgentAccessGrantSummary {
        guard token.hasPrefix("foil_"), token.count >= 45 else { throw AgentAccessGrantError.unauthorized }
        let digest = Self.digest(token)
        lock.lock()
        defer { lock.unlock() }
        let current = try read()
        guard let grant = current.grants.first(where: { Self.constantTimeEqual($0.tokenDigest, digest) }),
              grant.summary.revokedAt == nil,
              grant.summary.expiresAt > now() else { throw AgentAccessGrantError.unauthorized }
        return grant.summary
    }

    func revoke(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let current = try read()
        guard let index = current.grants.firstIndex(where: { $0.summary.id == id }) else {
            throw AgentAccessGrantError.unauthorized
        }
        if current.grants[index].summary.revokedAt != nil { return }
        var grants = current.grants
        let old = grants[index]
        grants[index] = StoredAgentAccessGrant(
            summary: AgentAccessGrantSummary(
                id: old.summary.id, name: old.summary.name, groupID: old.summary.groupID,
                appPaths: old.summary.appPaths, createdAt: old.summary.createdAt,
                expiresAt: old.summary.expiresAt, revokedAt: now()
            ),
            tokenDigest: old.tokenDigest
        )
        try write(AgentAccessGrantSnapshot(grants: grants, uses: current.uses))
    }

    func recordUse(grantID: String, kind: String, objectID: String, requestDigest: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let current = try read()
        guard current.grants.contains(where: { $0.summary.id == grantID }),
              Self.isDigest(requestDigest),
              kind == "proposal" || kind == "action" else { throw AgentAccessGrantError.unavailable }
        if let existing = current.uses.first(where: { $0.objectKind == kind && $0.objectID == objectID }) {
            guard existing.grantID == grantID, existing.requestDigest == requestDigest else {
                throw AgentAccessGrantError.unavailable
            }
            return
        }
        let use = AgentAccessGrantUse(
            grantID: grantID, objectKind: kind, objectID: objectID,
            requestDigest: requestDigest, createdAt: now()
        )
        try write(AgentAccessGrantSnapshot(grants: current.grants, uses: current.uses + [use]))
    }

    private func read() throws -> AgentAccessGrantSnapshot {
        var info = stat()
        if lstat(fileURL.path, &info) != 0 {
            guard errno == ENOENT else { throw AgentAccessGrantError.unavailable }
            return AgentAccessGrantSnapshot()
        }
        guard info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            throw AgentAccessGrantError.unavailable
        }
        do {
            let value = try decoder.decode(AgentAccessGrantSnapshot.self, from: Data(contentsOf: fileURL))
            guard value.schemaVersion == 1,
                  Set(value.grants.map(\.summary.id)).count == value.grants.count,
                  Set(value.grants.map(\.tokenDigest)).count == value.grants.count,
                  Set(value.uses.map { "\($0.objectKind):\($0.objectID)" }).count == value.uses.count,
                  value.grants.allSatisfy({ grant in
                      UUID(uuidString: grant.summary.id) != nil && Self.isDigest(grant.tokenDigest) &&
                          grant.summary.createdAt < grant.summary.expiresAt &&
                          grant.summary.revokedAt.map { $0 >= grant.summary.createdAt } != false
                  }),
                  value.uses.allSatisfy({ use in
                      value.grants.contains(where: { $0.summary.id == use.grantID }) &&
                          Self.isDigest(use.requestDigest)
                  }) else { throw AgentAccessGrantError.unavailable }
            return value
        } catch { throw AgentAccessGrantError.unavailable }
    }

    private func write(_ snapshot: AgentAccessGrantSnapshot) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: fileURL.path)
        } catch { throw AgentAccessGrantError.unavailable }
    }

    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AgentAccessGrantError.unavailable
        }
        return "foil_" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8), right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}

enum AgentAccessGrantScope {
    static func validate(_ grant: AgentAccessGrantSummary, groups: [CleanupGroup]) throws {
        guard let group = groups.first(where: { $0.id == grant.groupID && $0.isEnabled && !$0.isDefault }),
              AgentAccessAppTargeting.hasExactlyThesePaths(group, paths: grant.appPaths) else {
            throw AgentAccessGrantError.invalidScope
        }
        let verified: AgentAccessTargetVerificationResponse
        do {
            verified = try AgentAccessTargetInspection.verify(
                .init(appPaths: grant.appPaths, expectedGroupID: grant.groupID),
                requestID: "grant-scope", groups: groups
            )
        } catch {
            throw AgentAccessGrantError.invalidScope
        }
        guard verified.groupExclusiveToRequestedPaths == true else {
            throw AgentAccessGrantError.invalidScope
        }
    }

    static func validateProposal(
        _ request: VocabularyProposalRequest,
        grant: AgentAccessGrantSummary,
        groups: [CleanupGroup]
    ) throws {
        try validate(grant, groups: groups)
        guard request.scope.kind == "cleanup_group", request.scope.id == grant.groupID else {
            throw AgentAccessGrantError.invalidScope
        }
    }

    static func validatePolicyAction(
        _ request: AgentAccessActionRequest,
        grant: AgentAccessGrantSummary,
        model: AgentAccessVocabularyReadModel,
        groups: [CleanupGroup]
    ) throws {
        try validate(grant, groups: groups)
        guard request.action == .setCorrectionPolicies, request.enabled == nil,
              let policies = request.correctionPolicies, !policies.isEmpty else {
            throw AgentAccessGrantError.invalidScope
        }
        let corrections = Dictionary(uniqueKeysWithValues: model.corrections.map { ($0.id, $0) })
        guard policies.allSatisfy({ policy in
            policy.scopeID == grant.groupID && policy.suppressedGroupIDs.isEmpty &&
                corrections[policy.correctionID]?.localRule?.scopeID == grant.groupID
        }) else { throw AgentAccessGrantError.invalidScope }
    }
}

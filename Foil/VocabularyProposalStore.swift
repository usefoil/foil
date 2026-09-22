import Foundation

enum VocabularyProposalStoreError: Error, Equatable {
    case unreadable
    case unsupportedSchema(Int)
    case unsupportedRequestSchema(Int)
    case invalidRequestID
    case correctionsRequired
    case invalidReview
    case invalidSnapshotToken
    case queueFull(maximum: Int)
    case requestIDConflict(String)
    case proposalNotFound(String)
    case invalidStateTransition(from: AgentAccessProposalState, to: AgentAccessProposalState)
    case writeFailed
}

final class VocabularyProposalStore: @unchecked Sendable {
    static let maximumPendingProposals = 100

    let fileURL: URL
    private let maximumPending: Int
    private let fileManager: FileManager
    private let atomicWriter: @Sendable (Data, URL) throws -> Void
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    init(
        fileURL: URL,
        maximumPending: Int = VocabularyProposalStore.maximumPendingProposals,
        fileManager: FileManager = .default,
        atomicWriter: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        },
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.fileURL = fileURL
        self.maximumPending = maximumPending
        self.fileManager = fileManager
        self.atomicWriter = atomicWriter
        self.now = now
        self.makeID = makeID
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    convenience init(fileManager: FileManager = .default) {
        let paths = AgentAccessPaths.current(fileManager: fileManager)
        self.init(fileURL: paths.proposalStoreURL, fileManager: fileManager)
    }

    func load() throws -> VocabularyProposalSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return try decodeSnapshot()
    }

    func proposal(id: String) throws -> VocabularyProposal? {
        lock.lock()
        defer { lock.unlock() }
        return try decodeSnapshot().proposals.first { $0.id == id }
    }

    @discardableResult
    func submit(
        _ request: VocabularyProposalRequest,
        snapshotToken: String
    ) throws -> VocabularyProposalSubmission {
        lock.lock()
        defer { lock.unlock() }

        let request = request.canonicalized()
        guard request.schemaVersion == VocabularyProposalContract.schemaVersion else {
            throw VocabularyProposalStoreError.unsupportedRequestSchema(request.schemaVersion)
        }
        guard !request.requestID.isEmpty else {
            throw VocabularyProposalStoreError.invalidRequestID
        }
        guard !request.corrections.isEmpty else {
            throw VocabularyProposalStoreError.correctionsRequired
        }
        let normalizedSnapshotToken = snapshotToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSHA256Digest(normalizedSnapshotToken) else {
            throw VocabularyProposalStoreError.invalidSnapshotToken
        }

        let requestHash: String
        do {
            requestHash = try request.canonicalPayloadDigest()
        } catch {
            throw VocabularyProposalStoreError.unreadable
        }

        let current = try decodeSnapshot()
        if let existing = current.proposals.first(where: { $0.requestID == request.requestID }) {
            guard existing.requestHash == requestHash else {
                throw VocabularyProposalStoreError.requestIDConflict(request.requestID)
            }
            return VocabularyProposalSubmission(receipt: existing.receipt(), wasReplay: true)
        }

        let pendingCount = current.proposals.lazy.filter { $0.state == .pending }.count
        guard pendingCount < maximumPending else {
            throw VocabularyProposalStoreError.queueFull(maximum: maximumPending)
        }

        let timestamp = normalizedTimestamp()
        let proposal = VocabularyProposal(
            id: makeID().uuidString.lowercased(),
            requestID: request.requestID,
            requestHash: requestHash,
            reviewHash: nil,
            state: .pending,
            scope: request.scope,
            corrections: request.corrections,
            snapshotToken: normalizedSnapshotToken,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try persist(VocabularyProposalSnapshot(
            revision: current.revision + 1,
            proposals: current.proposals + [proposal]
        ))
        return VocabularyProposalSubmission(receipt: proposal.receipt(), wasReplay: false)
    }

    @discardableResult
    func revise(
        id: String,
        scope: VocabularyProposalScope,
        corrections: [VocabularyProposalCorrection]
    ) throws -> VocabularyProposal {
        lock.lock()
        defer { lock.unlock() }

        let current = try decodeSnapshot()
        guard let index = current.proposals.firstIndex(where: { $0.id == id }) else {
            throw VocabularyProposalStoreError.proposalNotFound(id)
        }
        let existing = current.proposals[index]
        guard existing.state == .pending else {
            throw VocabularyProposalStoreError.invalidStateTransition(from: existing.state, to: .pending)
        }
        let reviewedRequest = VocabularyProposalRequest(
            requestID: existing.requestID,
            scope: scope,
            corrections: corrections
        ).canonicalized()
        guard !reviewedRequest.corrections.isEmpty,
              reviewedRequest.corrections.allSatisfy({ !$0.spokenForms.isEmpty }) else {
            throw VocabularyProposalStoreError.invalidReview
        }
        let reviewHash: String
        do {
            reviewHash = try reviewedRequest.canonicalPayloadDigest()
        } catch {
            throw VocabularyProposalStoreError.invalidReview
        }
        if existing.scope == reviewedRequest.scope,
           existing.corrections == reviewedRequest.corrections {
            return existing
        }

        let updated = VocabularyProposal(
            id: existing.id,
            requestID: existing.requestID,
            requestHash: existing.requestHash,
            reviewHash: reviewHash,
            state: existing.state,
            scope: reviewedRequest.scope,
            corrections: reviewedRequest.corrections,
            snapshotToken: existing.snapshotToken,
            createdAt: existing.createdAt,
            updatedAt: normalizedTimestamp()
        )
        var proposals = current.proposals
        proposals[index] = updated
        try persist(VocabularyProposalSnapshot(revision: current.revision + 1, proposals: proposals))
        return updated
    }

    @discardableResult
    func transition(id: String, to state: AgentAccessProposalState) throws -> VocabularyProposalReceipt {
        lock.lock()
        defer { lock.unlock() }

        let current = try decodeSnapshot()
        guard let index = current.proposals.firstIndex(where: { $0.id == id }) else {
            throw VocabularyProposalStoreError.proposalNotFound(id)
        }
        let existing = current.proposals[index]
        if existing.state == state {
            return existing.receipt()
        }
        guard existing.state == .pending,
              state == .rejected || state == .discarded else {
            throw VocabularyProposalStoreError.invalidStateTransition(from: existing.state, to: state)
        }

        let updated = VocabularyProposal(
            id: existing.id,
            requestID: existing.requestID,
            requestHash: existing.requestHash,
            reviewHash: existing.reviewHash,
            state: state,
            scope: existing.scope,
            corrections: existing.corrections,
            snapshotToken: existing.snapshotToken,
            createdAt: existing.createdAt,
            updatedAt: normalizedTimestamp()
        )
        var proposals = current.proposals
        proposals[index] = updated
        try persist(VocabularyProposalSnapshot(revision: current.revision + 1, proposals: proposals))
        return updated.receipt()
    }

    private func decodeSnapshot() throws -> VocabularyProposalSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return VocabularyProposalSnapshot()
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw VocabularyProposalStoreError.unreadable
        }

        let schemaVersion: Int
        do {
            schemaVersion = try decoder.decode(SchemaHeader.self, from: data).schemaVersion
        } catch {
            throw VocabularyProposalStoreError.unreadable
        }
        guard schemaVersion == VocabularyProposalSnapshot.currentSchemaVersion else {
            throw VocabularyProposalStoreError.unsupportedSchema(schemaVersion)
        }

        do {
            let snapshot = try decoder.decode(VocabularyProposalSnapshot.self, from: data)
            guard snapshot.revision >= 0,
                  Set(snapshot.proposals.map(\.id)).count == snapshot.proposals.count,
                  Set(snapshot.proposals.map(\.requestID)).count == snapshot.proposals.count else {
                throw VocabularyProposalStoreError.unreadable
            }
            for proposal in snapshot.proposals {
                guard try isValid(proposal) else {
                    throw VocabularyProposalStoreError.unreadable
                }
            }
            return snapshot
        } catch let error as VocabularyProposalStoreError {
            throw error
        } catch {
            throw VocabularyProposalStoreError.unreadable
        }
    }

    private func persist(_ snapshot: VocabularyProposalSnapshot) throws {
        let data: Data
        do {
            data = try encoder.encode(snapshot)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try atomicWriter(data, fileURL)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            throw VocabularyProposalStoreError.writeFailed
        }
    }

    private func normalizedTimestamp() -> Date {
        let milliseconds = (now().timeIntervalSince1970 * 1_000).rounded(.down)
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private func isSHA256Digest(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }

    private func isValid(_ proposal: VocabularyProposal) throws -> Bool {
        guard UUID(uuidString: proposal.id) != nil,
              !proposal.requestID.isEmpty,
              isSHA256Digest(proposal.snapshotToken),
              proposal.createdAt <= proposal.updatedAt,
              isSHA256Digest(proposal.requestHash) else {
            return false
        }
        let request = VocabularyProposalRequest(
            requestID: proposal.requestID,
            scope: proposal.scope,
            corrections: proposal.corrections
        )
        guard request == request.canonicalized() else { return false }
        let currentDigest = try request.canonicalPayloadDigest()
        if let reviewHash = proposal.reviewHash {
            guard isSHA256Digest(reviewHash) else { return false }
            return currentDigest == reviewHash
        }
        return currentDigest == proposal.requestHash
    }

    private struct SchemaHeader: Decodable {
        let schemaVersion: Int

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
        }
    }
}

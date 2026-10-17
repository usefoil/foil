import Darwin
import Foundation

/// Separate storage prevents an older correction-only client from decoding and partially applying a mixed batch.
final class VocabularyBatchStore: @unchecked Sendable {
    struct Snapshot: Codable {
        let schemaVersion: Int
        var records: [VocabularyBatchRecord]
        enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", records }
    }
    private let fileURL: URL
    private let lock = NSRecursiveLock()
    private let write: @Sendable (Data, URL) throws -> Void
    private let now: @Sendable () -> Date

    init(fileURL: URL, now: @escaping @Sendable () -> Date = { Date() },
         write: @escaping @Sendable (Data, URL) throws -> Void = { try VocabularyBatchStore.writeOwnerOnlyAtomically($0, to: $1) }) {
        self.fileURL = fileURL
        self.now = now
        self.write = write
    }

    func records() throws -> [VocabularyBatchRecord] { try lock.withLock { try load().records } }

    func record(id: String) throws -> VocabularyBatchRecord {
        guard let record = try records().first(where: { $0.id == id }) else { throw VocabularyBatchError.notFound }
        return record
    }

    func submit(_ request: VocabularyBatchRequest, grantID: String? = nil,
                validate: () throws -> Void) throws -> (record: VocabularyBatchRecord, replay: Bool) {
        try lock.withLock {
            let request = request.normalized()
            let digest = try request.digest()
            var snapshot = try load()
            if let existing = snapshot.records.first(where: { $0.originalRequest.requestID == request.requestID }) {
                guard existing.requestDigest == digest else { throw VocabularyBatchError.conflict("This request_id was already used for different content.") }
                return (existing, true)
            }
            try validate()
            guard snapshot.records.filter({ $0.state == .pending }).count < 100 else { throw VocabularyBatchError.queueFull }
            let timestamp = now()
            let record = VocabularyBatchRecord(id: UUID().uuidString.lowercased(), originalRequest: request, reviewedRequest: request, requestDigest: digest, state: .pending, createdAt: timestamp, updatedAt: timestamp, grantID: grantID)
            snapshot.records.append(record)
            try persist(snapshot)
            return (record, false)
        }
    }

    func revise(id: String, request: VocabularyBatchRequest, validate: () throws -> Void) throws {
        try lock.withLock {
            var snapshot = try load()
            guard let index = snapshot.records.firstIndex(where: { $0.id == id }) else { throw VocabularyBatchError.notFound }
            guard snapshot.records[index].state == .pending,
                  request.requestID == snapshot.records[index].originalRequest.requestID else {
                throw VocabularyBatchError.conflict("Only a pending batch can be edited, with its original request_id.")
            }
            try validate()
            snapshot.records[index].reviewedRequest = request.normalized()
            snapshot.records[index].updatedAt = now()
            // A Foil edit cannot inherit a delegated approval for different content.
            snapshot.records[index].grantID = nil
            try persist(snapshot)
        }
    }

    func transition(id: String, to state: AgentAccessProposalState) throws {
        try lock.withLock {
            var snapshot = try load()
            guard let index = snapshot.records.firstIndex(where: { $0.id == id }) else { throw VocabularyBatchError.notFound }
            let old = snapshot.records[index].state
            if old == state { return }
            guard old == .pending, state == .rejected || state == .discarded else {
                throw VocabularyBatchError.conflict("This batch is no longer pending.")
            }
            snapshot.records[index].state = state
            snapshot.records[index].updatedAt = now()
            try persist(snapshot)
        }
    }

    /// Hold the record stable across validation and the catalog commit; HTTP submissions cannot race review edits.
    func apply(id: String, commit: (VocabularyBatchRecord) throws -> VocabularyAppliedProposalReceipt) throws {
        try lock.withLock {
            let record = try record(id: id)
            guard record.state == .pending || record.state == .applied else { throw VocabularyBatchError.conflict("This batch is no longer pending.") }
            let receipt = try commit(record)
            try reconcile([receipt])
        }
    }

    func reconcile(_ receipts: [VocabularyAppliedProposalReceipt]) throws {
        try lock.withLock {
            var snapshot = try load()
            var changed = false
            for receipt in receipts where receipt.batchItems != nil {
                guard let index = snapshot.records.firstIndex(where: { $0.id == receipt.proposalID }) else { continue }
                let record = snapshot.records[index]
                guard record.originalRequest.requestID == receipt.requestID,
                      record.requestDigest == receipt.requestDigest,
                      try record.reviewedRequest.digest() == receipt.reviewedDigest else {
                    throw VocabularyBatchError.conflict("The saved catalog receipt does not match this batch.")
                }
                if record.state == .applied { continue }
                guard record.state == .pending else { throw VocabularyBatchError.conflict("A terminal batch conflicts with a saved receipt.") }
                snapshot.records[index].state = .applied
                snapshot.records[index].appliedItems = receipt.batchItems
                snapshot.records[index].catalogRevision = receipt.catalogRevision
                snapshot.records[index].updatedAt = receipt.appliedAt
                changed = true
            }
            if changed { try persist(snapshot) }
        }
    }

    private func load() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .init(schemaVersion: 1, records: []) }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let snapshot = try decoder.decode(Snapshot.self, from: Data(contentsOf: fileURL))
            guard snapshot.schemaVersion == 1,
                  Set(snapshot.records.map(\.id)).count == snapshot.records.count,
                  Set(snapshot.records.map { $0.originalRequest.requestID }).count == snapshot.records.count else { throw VocabularyBatchError.unavailable }
            for record in snapshot.records {
                guard UUID(uuidString: record.id) != nil,
                      record.originalRequest.schemaVersion == 2, record.reviewedRequest.schemaVersion == 2,
                      record.originalRequest.requestID == record.reviewedRequest.requestID,
                      record.originalRequest == record.originalRequest.normalized(),
                      record.reviewedRequest == record.reviewedRequest.normalized(),
                      try record.originalRequest.digest() == record.requestDigest,
                      record.createdAt <= record.updatedAt,
                      record.state != .applied || (record.appliedItems != nil && record.catalogRevision != nil) else {
                    throw VocabularyBatchError.unavailable
                }
            }
            return snapshot
        } catch { throw VocabularyBatchError.unavailable }
    }

    private static func writeOwnerOnlyAtomically(_ data: Data, to url: URL) throws {
        let staging = url.deletingLastPathComponent().appendingPathComponent(".batch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try VocabularyCatalogStore.writeOwnerOnly(data, to: staging)
        guard rename(staging.path, url.path) == 0 else { throw VocabularyBatchError.unavailable }
    }

    private func persist(_ snapshot: Snapshot) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fileURL.deletingLastPathComponent().path)
            try write(encoder.encode(snapshot), fileURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { throw VocabularyBatchError.unavailable }
    }
}

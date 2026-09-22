import Foundation
import XCTest
@testable import Foil

final class VocabularyProposalStoreTests: XCTestCase {
    func testMissingStoreLoadsVersionedEmptySnapshot() throws {
        let fixture = try makeFixture()

        XCTAssertEqual(try fixture.store.load(), VocabularyProposalSnapshot())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    func testSubmissionPersistsOnceAndSurvivesRelaunch() throws {
        let fixture = try makeFixture()
        let request = proposalRequest(id: "request-1")

        let submitted = try fixture.store.submit(request, snapshotToken: proposalSnapshotToken)
        let reloaded = try VocabularyProposalStore(fileURL: fixture.fileURL).load()

        XCTAssertFalse(submitted.wasReplay)
        XCTAssertEqual(reloaded.revision, 1)
        XCTAssertEqual(reloaded.proposals.count, 1)
        XCTAssertEqual(reloaded.proposals[0].requestID, "request-1")
        XCTAssertEqual(reloaded.proposals[0].state, .pending)
        XCTAssertEqual(reloaded.proposals[0].snapshotToken, proposalSnapshotToken)
        XCTAssertEqual(reloaded.proposals[0].receipt(), submitted.receipt)
    }

    func testSemanticReplayReturnsOriginalReceiptWithoutWriting() throws {
        let fixture = try makeFixture()
        let first = proposalRequest(id: "request-1", aliases: ["super base", "Café"])
        let replay = VocabularyProposalRequest(
            requestID: " request-1 ",
            scope: .init(kind: " cleanup_group ", id: " agents "),
            corrections: [.init(
                spokenForms: [" super base ", "Cafe\u{301}"],
                replacement: " Supabase ",
                note: " database "
            )]
        )
        let original = try fixture.store.submit(first, snapshotToken: proposalSnapshotToken)
        let bytes = try Data(contentsOf: fixture.fileURL)

        let repeated = try fixture.store.submit(replay, snapshotToken: alternateProposalSnapshotToken)

        XCTAssertTrue(repeated.wasReplay)
        XCTAssertEqual(repeated.receipt, original.receipt)
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
        XCTAssertEqual(try fixture.store.load().revision, 1)
    }

    func testReusedRequestIDWithDifferentContentConflictsWithoutMutation() throws {
        let fixture = try makeFixture()
        _ = try fixture.store.submit(proposalRequest(id: "request-1"), snapshotToken: proposalSnapshotToken)
        let before = try Data(contentsOf: fixture.fileURL)
        let different = proposalRequest(id: "request-1", replacement: "Postgres")

        XCTAssertThrowsError(try fixture.store.submit(different, snapshotToken: proposalSnapshotToken)) { error in
            XCTAssertEqual(error as? VocabularyProposalStoreError, .requestIDConflict("request-1"))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), before)
        XCTAssertEqual(try fixture.store.load().proposals.count, 1)
    }

    func testSimultaneousReplayRacePersistsExactlyOneProposal() throws {
        let fixture = try makeFixture()
        let request = proposalRequest(id: "racing-request")
        let results = LockedResults<Result<VocabularyProposalSubmission, Error>>()
        let queue = DispatchQueue(label: "proposal-race", attributes: .concurrent)
        let group = DispatchGroup()

        for _ in 0..<40 {
            group.enter()
            queue.async {
                results.append(Result { try fixture.store.submit(request, snapshotToken: proposalSnapshotToken) })
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)

        let submissions = try results.values.map { try $0.get() }
        XCTAssertEqual(submissions.filter { !$0.wasReplay }.count, 1)
        XCTAssertEqual(Set(submissions.map(\.receipt.proposalID)).count, 1)
        XCTAssertEqual(try fixture.store.load().proposals.count, 1)
        XCTAssertEqual(try fixture.store.load().revision, 1)
    }

    func testConcurrentDistinctRequestsDoNotOverwriteEachOther() throws {
        let fixture = try makeFixture(maximumPending: 50)
        let results = LockedResults<Result<VocabularyProposalSubmission, Error>>()
        let queue = DispatchQueue(label: "proposal-distinct-race", attributes: .concurrent)
        let group = DispatchGroup()

        for index in 0..<30 {
            group.enter()
            queue.async {
                results.append(Result {
                    try fixture.store.submit(
                        self.proposalRequest(id: "request-\(index)", replacement: "Value \(index)"),
                        snapshotToken: proposalSnapshotToken
                    )
                })
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        _ = try results.values.map { try $0.get() }

        let snapshot = try fixture.store.load()
        XCTAssertEqual(snapshot.revision, 30)
        XCTAssertEqual(snapshot.proposals.count, 30)
        XCTAssertEqual(Set(snapshot.proposals.map(\.requestID)).count, 30)
    }

    func testMultipleProposalsSurviveRelaunchInOrder() throws {
        let fixture = try makeFixture()
        for index in 1...3 {
            _ = try fixture.store.submit(
                proposalRequest(id: "request-\(index)", replacement: "Value \(index)"),
                snapshotToken: proposalSnapshotToken
            )
        }

        let reloaded = try VocabularyProposalStore(fileURL: fixture.fileURL).load()

        XCTAssertEqual(reloaded.revision, 3)
        XCTAssertEqual(reloaded.proposals.map(\.requestID), ["request-1", "request-2", "request-3"])
    }

    func testQueueLimitRejectsWithoutMutationAndTerminalProposalReleasesCapacity() throws {
        let fixture = try makeFixture(maximumPending: 1)
        let first = try fixture.store.submit(proposalRequest(id: "request-1"), snapshotToken: proposalSnapshotToken)
        let fullBytes = try Data(contentsOf: fixture.fileURL)

        XCTAssertThrowsError(
            try fixture.store.submit(proposalRequest(id: "request-2"), snapshotToken: proposalSnapshotToken)
        ) { error in
            XCTAssertEqual(error as? VocabularyProposalStoreError, .queueFull(maximum: 1))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), fullBytes)

        _ = try fixture.store.transition(id: first.receipt.proposalID, to: .rejected)
        XCTAssertNoThrow(try fixture.store.submit(proposalRequest(id: "request-2"), snapshotToken: proposalSnapshotToken))
        XCTAssertEqual(try fixture.store.load().proposals.count, 2)
    }

    func testTerminalTransitionIsIdempotentAndCannotChangeDisposition() throws {
        let fixture = try makeFixture()
        let submission = try fixture.store.submit(proposalRequest(id: "request-1"), snapshotToken: proposalSnapshotToken)

        let rejected = try fixture.store.transition(id: submission.receipt.proposalID, to: .rejected)
        let revisionAfterReject = try fixture.store.load().revision
        let repeated = try fixture.store.transition(id: submission.receipt.proposalID, to: .rejected)

        XCTAssertEqual(repeated, rejected)
        XCTAssertEqual(try fixture.store.load().revision, revisionAfterReject)
        XCTAssertThrowsError(
            try fixture.store.transition(id: submission.receipt.proposalID, to: .discarded)
        ) { error in
            XCTAssertEqual(
                error as? VocabularyProposalStoreError,
                .invalidStateTransition(from: .rejected, to: .discarded)
            )
        }
    }

    func testPendingProposalCannotBeMarkedAppliedWithoutTheFutureCoordinator() throws {
        let fixture = try makeFixture()
        let submission = try fixture.store.submit(proposalRequest(id: "request-1"), snapshotToken: proposalSnapshotToken)
        let before = try Data(contentsOf: fixture.fileURL)

        XCTAssertThrowsError(
            try fixture.store.transition(id: submission.receipt.proposalID, to: .applied)
        ) { error in
            XCTAssertEqual(
                error as? VocabularyProposalStoreError,
                .invalidStateTransition(from: .pending, to: .applied)
            )
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), before)
    }

    func testInvalidEnvelopeDoesNotCreateStore() throws {
        let fixture = try makeFixture()
        let emptyID = proposalRequest(id: "   ")
        let noCorrections = VocabularyProposalRequest(
            requestID: "request-1",
            scope: .init(kind: "cleanup_group", id: "agents"),
            corrections: []
        )
        let future = VocabularyProposalRequest(
            schemaVersion: 999,
            requestID: "request-1",
            scope: .init(kind: "cleanup_group", id: "agents"),
            corrections: proposalRequest(id: "unused").corrections
        )

        XCTAssertThrowsError(try fixture.store.submit(emptyID, snapshotToken: proposalSnapshotToken))
        XCTAssertThrowsError(try fixture.store.submit(noCorrections, snapshotToken: proposalSnapshotToken))
        XCTAssertThrowsError(try fixture.store.submit(future, snapshotToken: proposalSnapshotToken))
        for invalidToken in ["  ", "existing vocabulary text", String(repeating: "A", count: 64)] {
            XCTAssertThrowsError(
                try fixture.store.submit(proposalRequest(id: "request"), snapshotToken: invalidToken)
            ) { error in
                XCTAssertEqual(error as? VocabularyProposalStoreError, .invalidSnapshotToken)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    func testCorruptAndFutureStoresCannotBeSilentlyOverwritten() throws {
        for data in [
            Data("{ definitely-not-json".utf8),
            Data(#"{"schema_version":999,"revision":4,"proposals":[]}"#.utf8)
        ] {
            let fixture = try makeFixture()
            try data.write(to: fixture.fileURL)

            XCTAssertThrowsError(
                try fixture.store.submit(proposalRequest(id: "request"), snapshotToken: proposalSnapshotToken)
            )
            XCTAssertEqual(try Data(contentsOf: fixture.fileURL), data)
        }
    }

    func testStructurallyValidStoreWithInvalidDigestFailsClosed() throws {
        let fixture = try makeFixture()
        _ = try fixture.store.submit(proposalRequest(id: "request-1"), snapshotToken: proposalSnapshotToken)
        let original = try String(contentsOf: fixture.fileURL, encoding: .utf8)
        let invalid = try XCTUnwrap(
            original.replacingOccurrences(
                of: #""request_hash" : "[0-9a-f]{64}""#,
                with: #""request_hash" : "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz""#,
                options: .regularExpression
            ).data(using: .utf8)
        )
        try invalid.write(to: fixture.fileURL)

        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? VocabularyProposalStoreError, .unreadable)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), invalid)
    }

    func testStructurallyValidStoreWithTamperedPayloadFailsClosed() throws {
        let fixture = try makeFixture()
        _ = try fixture.store.submit(proposalRequest(id: "request-1"), snapshotToken: proposalSnapshotToken)
        let original = try String(contentsOf: fixture.fileURL, encoding: .utf8)
        let tampered = try XCTUnwrap(
            original.replacingOccurrences(of: "Supabase", with: "Postgres").data(using: .utf8)
        )
        try tampered.write(to: fixture.fileURL)

        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? VocabularyProposalStoreError, .unreadable)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), tampered)
    }

    func testAtomicWriteFailureLeavesPriorSnapshotByteIdentical() throws {
        let fixture = try makeFixture()
        _ = try fixture.store.submit(proposalRequest(id: "request-1"), snapshotToken: proposalSnapshotToken)
        let before = try Data(contentsOf: fixture.fileURL)
        let failing = VocabularyProposalStore(
            fileURL: fixture.fileURL,
            atomicWriter: { _, _ in throw SimulatedProposalWriteFailure() }
        )

        XCTAssertThrowsError(
            try failing.submit(proposalRequest(id: "request-2"), snapshotToken: proposalSnapshotToken)
        ) { error in
            XCTAssertEqual(error as? VocabularyProposalStoreError, .writeFailed)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), before)
        XCTAssertEqual(try fixture.store.load().proposals.map(\.requestID), ["request-1"])
    }

    func testPersistedFileIsOwnerOnly() throws {
        let fixture = try makeFixture()
        _ = try fixture.store.submit(proposalRequest(id: "request-1"), snapshotToken: proposalSnapshotToken)

        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.fileURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(permissions & 0o777, 0o600)
    }

    private func makeFixture(
        maximumPending: Int = VocabularyProposalStore.maximumPendingProposals
    ) throws -> (store: VocabularyProposalStore, fileURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilVocabularyProposalStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(AgentAccessPaths.proposalStoreFileName)
        let date = Date(timeIntervalSince1970: 1_700_000_000.123456)
        return (
            VocabularyProposalStore(
                fileURL: fileURL,
                maximumPending: maximumPending,
                now: { date }
            ),
            fileURL
        )
    }

    private func proposalRequest(
        id: String,
        aliases: [String] = ["super base", "Café"],
        replacement: String = "Supabase"
    ) -> VocabularyProposalRequest {
        VocabularyProposalRequest(
            requestID: id,
            scope: .init(kind: "cleanup_group", id: "agents"),
            corrections: [.init(
                spokenForms: aliases,
                replacement: replacement,
                note: "database"
            )]
        )
    }
}

private final class LockedResults<Value>: @unchecked Sendable {
    private var storage: [Value] = []
    private let lock = NSLock()

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private struct SimulatedProposalWriteFailure: Error {}

private let proposalSnapshotToken = String(repeating: "a", count: 64)
private let alternateProposalSnapshotToken = String(repeating: "b", count: 64)

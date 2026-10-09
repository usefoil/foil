import Foundation
import XCTest
@testable import Foil

@MainActor
final class VocabularyBatchTests: XCTestCase {
    private let scopes: [AgentAccessVocabularyScope] = [.init(id: "agents", name: "ChatGPT + Codex", isDefault: false, isEnabled: true)]

    func testScopedReadTermsPreserveLegacyPolicyReceiptDigest() throws {
        let model = AgentAccessVocabularyReadModel(scopes: [], terms: [], corrections: [], localCorrectionsEnabled: false,
            scopedTerms: [.init(id: UUID().uuidString, term: "Supabase", note: nil, scopeID: "agents")])
        // Frozen pre-v2 digest: existing pending v1 actions must survive the upgrade.
        XCTAssertEqual(try AgentAccessPolicyBatchPlanner.digest(model: model, groups: []), "a4e9f16773dfc2f9563e0b7684a3cd21264aff0c8580d666abbd47dc8336ebbb")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(model)) as? [String: Any])
        XCTAssertNil(object["scopedTerms"])
        XCTAssertEqual(model.scopedTerms.count, 1, "The v2 projection still retains scoped terms")
    }

    func testMixedBatchCommitsTermsCorrectionsAndTypedReceiptTogether() throws {
        let fixture = try fixture()
        let request = batch("mixed", items: [term(), correction()])
        let record = try submit(request, fixture)
        let initial = try XCTUnwrap(fixture.coordinator.loadedCatalog)
        let result = try fixture.coordinator.applyBatch(record, scopes: scopes)
        XCTAssertEqual(result.loaded.snapshot.revision, initial.snapshot.revision + 1)
        XCTAssertEqual(result.loaded.snapshot.vocabularyTerms.map(\.term), ["Supabase"])
        XCTAssertEqual(result.loaded.snapshot.vocabularyTerms.map(\.scopeID), ["agents"])
        XCTAssertEqual(result.loaded.snapshot.rules.map(\.group), ["agents"])
        XCTAssertEqual(result.receipt.batchItems?.map(\.kind), [.preferredTerm, .correction])
        XCTAssertFalse(result.loaded.snapshot.localCorrectionsEnabled)
        XCTAssertEqual(try fixture.store.load(legacyVocabularyData: nil, legacyLocalCorrectionsData: nil).snapshot, result.loaded.snapshot)
    }

    func testRepeatWithFreshRequestIDHasStableEntryIDsAndRevision() throws {
        let fixture = try fixture()
        let first = try fixture.coordinator.applyBatch(submit(batch("first", items: [term(), correction()]), fixture), scopes: scopes)
        let secondRequest = batch("second", items: [term(), correction()])
        let preview = VocabularyBatchEvaluator.preview(secondRequest, model: model(fixture))
        XCTAssertEqual(preview.items.map(\.disposition), [.alreadyPresent, .alreadyPresent])
        let second = try fixture.coordinator.applyBatch(submit(secondRequest, fixture), scopes: scopes)
        XCTAssertEqual(first.loaded.snapshot.revision, second.loaded.snapshot.revision)
        XCTAssertEqual(first.loaded.snapshot.vocabularyTerms, second.loaded.snapshot.vocabularyTerms)
        XCTAssertEqual(first.loaded.snapshot.vocabularyCorrections, second.loaded.snapshot.vocabularyCorrections)
        XCTAssertEqual(second.receipt.batchItems?.map(\.disposition), ["already_present", "already_present"])
        XCTAssertEqual(second.loaded.snapshot.appliedProposalReceipts.count, 2, "An audit receipt is durable even when Vocabulary is unchanged")
    }

    func testGlobalTermCoversGroupUnlessIndependentScopeExplicitlyRequested() throws {
        let fixture = try fixture()
        var global = batch("global", items: [term()])
        global.scope = .init(kind: "global", id: "global")
        _ = try fixture.coordinator.applyBatch(submit(global, fixture), scopes: scopes)
        let group = batch("group", items: [term()])
        XCTAssertEqual(VocabularyBatchEvaluator.preview(group, model: model(fixture)).items.first?.disposition, .alreadyPresent)
        var independent = group
        independent.items[0].independentScope = true
        XCTAssertEqual(VocabularyBatchEvaluator.preview(independent, model: model(fixture)).items.first?.disposition, .add)
        let result = try fixture.coordinator.applyBatch(submit(independent, fixture), scopes: scopes)
        XCTAssertEqual(result.loaded.snapshot.vocabularyTerms.count, 2)
        XCTAssertEqual(PreferredTermPolicy.effective(result.loaded.snapshot.vocabularyTerms, groupID: "agents"), ["Supabase"])
    }

    func testSpellingAndNoteDifferencesAreConflictsWithoutOverwrite() throws {
        let fixture = try fixture()
        _ = try fixture.coordinator.applyBatch(submit(batch("initial", items: [term()]), fixture), scopes: scopes)
        for item in [VocabularyBatchItem(id: "case", kind: .preferredTerm, term: "supabase"), .init(id: "note", kind: .preferredTerm, term: "Supabase", note: "changed")] {
            let preview = VocabularyBatchEvaluator.preview(batch(UUID().uuidString, items: [item]), model: model(fixture))
            XCTAssertFalse(preview.valid)
            XCTAssertEqual(preview.items.first?.disposition, .conflict)
        }
    }

    func testUnrelatedCatalogChangeDoesNotStrandPendingBatch() throws {
        let fixture = try fixture()
        let pending = try submit(batch("pending", items: [term()]), fixture)
        _ = try fixture.coordinator.applyBatch(submit(batch("other", items: [.init(id: "vercel", kind: .preferredTerm, term: "Vercel")]), fixture), scopes: scopes)
        let applied = try fixture.coordinator.applyBatch(pending, scopes: scopes)
        XCTAssertEqual(applied.loaded.snapshot.vocabularyTerms.map(\.term), ["Vercel", "Supabase"])
    }

    func testGenuineConflictBlocksWholeBatchThenOmissionAppliesInPlace() throws {
        let fixture = try fixture()
        let pending = try submit(batch("pending", items: [term(), correction()]), fixture)
        let conflict = VocabularyBatchItem(id: "conflict", kind: .correction, correction: .init(spokenForms: ["super base"], replacement: "OtherService"))
        _ = try fixture.coordinator.applyBatch(submit(batch("other", items: [conflict]), fixture), scopes: scopes)
        let before = try Data(contentsOf: fixture.store.fileURL)
        XCTAssertThrowsError(try fixture.coordinator.applyBatch(pending, scopes: scopes))
        XCTAssertEqual(try Data(contentsOf: fixture.store.fileURL), before)
        XCTAssertTrue(try XCTUnwrap(fixture.coordinator.loadedCatalog).snapshot.vocabularyTerms.isEmpty)
        var edited = pending.reviewedRequest
        edited.items.removeLast()
        try fixture.inbox.revise(id: pending.id, request: edited) { try VocabularyBatchHTTP.validate(edited, model: model(fixture)) }
        let result = try fixture.coordinator.applyBatch(fixture.inbox.record(id: pending.id), scopes: scopes)
        XCTAssertEqual(result.receipt.proposalID, pending.id)
        XCTAssertEqual(result.loaded.snapshot.vocabularyTerms.map(\.term), ["Supabase"])
    }

    func testFailureCannotPartiallySaveMixedBatchOrReceipt() throws {
        let fault = Fault()
        let fixture = try fixture(fault: fault)
        let pending = try submit(batch("fail", items: [term(), correction()]), fixture)
        let before = try Data(contentsOf: fixture.store.fileURL)
        fault.enabled = true
        XCTAssertThrowsError(try fixture.coordinator.applyBatch(pending, scopes: scopes))
        XCTAssertEqual(try Data(contentsOf: fixture.store.fileURL), before)
        XCTAssertTrue(try XCTUnwrap(fixture.coordinator.loadedCatalog).snapshot.vocabularyTerms.isEmpty)
        XCTAssertEqual(try fixture.inbox.record(id: pending.id).state, .pending)
    }

    func testAuthorizationRecheckedImmediatelyBeforeCommit() throws {
        let fixture = try fixture()
        let pending = try submit(batch("revoked", items: [term(), correction()]), fixture)
        let before = try Data(contentsOf: fixture.store.fileURL)
        var checked = false
        XCTAssertThrowsError(try fixture.coordinator.applyBatch(pending, scopes: scopes) {
            checked = true
            throw VocabularyBatchError.conflict("Grant revoked")
        })
        XCTAssertTrue(checked)
        XCTAssertEqual(try Data(contentsOf: fixture.store.fileURL), before)
    }

    func testDurableCatalogReceiptRecoversFailedInboxUpdateAndReplay() throws {
        let inboxFault = Fault()
        let fixture = try fixture(inboxFault: inboxFault)
        let request = batch("recover", items: [term(), correction()])
        let pending = try submit(request, fixture)
        inboxFault.enabled = true
        XCTAssertThrowsError(try fixture.inbox.apply(id: pending.id) { try fixture.coordinator.applyBatch($0, scopes: scopes).receipt })
        let saved = try XCTUnwrap(fixture.coordinator.loadedCatalog)
        XCTAssertEqual(saved.snapshot.vocabularyTerms.count, 1)
        XCTAssertEqual(try fixture.inbox.record(id: pending.id).state, .pending)
        inboxFault.enabled = false
        try fixture.inbox.reconcile(saved.snapshot.appliedProposalReceipts)
        XCTAssertEqual(try fixture.inbox.record(id: pending.id).state, .applied)
        let replay = try fixture.inbox.submit(request) { XCTFail("A durable replay must precede validation against its own saved entries") }
        XCTAssertTrue(replay.replay)
        XCTAssertEqual(replay.record.appliedItems?.count, 2)
        let reapplied = try fixture.coordinator.applyBatch(replay.record, scopes: scopes)
        XCTAssertEqual(reapplied.loaded.snapshot, saved.snapshot)
        var changed = request
        changed.items[0].term = "Different"
        XCTAssertThrowsError(try fixture.inbox.submit(changed) {})
    }

    func testDisabledAndMissingScopesCannotWidenTermsToGlobal() throws {
        let fixture = try fixture()
        let pending = try submit(batch("disabled", items: [term()]), fixture)
        XCTAssertThrowsError(try fixture.coordinator.applyBatch(pending, scopes: []))
        XCTAssertThrowsError(try fixture.coordinator.applyBatch(pending, scopes: [.init(id: "agents", name: "Agents", isDefault: false, isEnabled: false)]))
        XCTAssertTrue(try XCTUnwrap(fixture.coordinator.loadedCatalog).snapshot.vocabularyTerms.isEmpty)
    }

    func testBatchBoundsUnicodePunctuationAndUnsupportedPayloads() throws {
        let fixture = try fixture()
        let valid = batch("symbols", items: [.init(id: "cpp", kind: .preferredTerm, term: "C++"), .init(id: "cs", kind: .preferredTerm, term: "C#"), .init(id: "accent", kind: .preferredTerm, term: " Cafe\u{301} ")])
        XCTAssertTrue(VocabularyBatchEvaluator.preview(valid, model: model(fixture)).valid)
        XCTAssertEqual(valid.normalized().items.last?.term, "Café")
        var duplicate = valid
        duplicate.items.append(.init(id: "other", kind: .preferredTerm, term: "CAFÉ"))
        XCTAssertFalse(VocabularyBatchEvaluator.preview(duplicate, model: model(fixture)).valid)
        for bad in ["", "word\tword", String(repeating: "x", count: 257)] {
            XCTAssertFalse(VocabularyBatchEvaluator.preview(batch("bad", items: [.init(id: "bad", kind: .preferredTerm, term: bad)]), model: model(fixture)).valid)
        }
        var oversized = valid
        oversized.items = (0..<51).map { .init(id: "id\($0)", kind: .preferredTerm, term: "Term\($0)") }
        XCTAssertFalse(VocabularyBatchEvaluator.preview(oversized, model: model(fixture)).valid)
        XCTAssertThrowsError(try JSONDecoder().decode(VocabularyBatchRequest.self, from: Data(#"{"schema_version":2,"request_id":"x","scope":{"kind":"global","id":"global"},"items":[{"id":"x","kind":"execute"}]}"#.utf8)))
    }

    func testV2RoutesPreviewSubmitReplayAndStatusWithoutGrant() throws {
        let fixture = try fixture()
        let router = VocabularyBatchHTTP(store: fixture.inbox, model: { self.model(fixture) }, didChange: {})
        func call(_ method: AgentAccessHTTPMethod, _ path: String, _ body: Data = Data()) -> AgentAccessHTTPResponse {
            router.response(to: .init(method: method, path: path, headers: [:], body: body), requestID: "transport")
        }
        let body = try JSONEncoder().encode(batch("http", items: [term(), correction()]))
        XCTAssertEqual(call(.post, "/v2/vocabulary/preview", body).status, 200)
        XCTAssertTrue(try fixture.inbox.records().isEmpty)
        let submitted = call(.post, "/v2/vocabulary/proposals", body)
        XCTAssertEqual(submitted.status, 202)
        XCTAssertEqual(call(.post, "/v2/vocabulary/proposals", body).status, 200)
        let pending = try XCTUnwrap(fixture.inbox.records().first)
        XCTAssertEqual(pending.state, .pending, "Ordinary agent submissions require Foil review")
        XCTAssertEqual(call(.get, "/v2/vocabulary/proposals/\(pending.id)").status, 200)
        XCTAssertEqual(call(.get, "/v2/vocabulary/proposals/not-a-uuid").status, 404)
        XCTAssertEqual(call(.post, "/v2/vocabulary").status, 405)
        XCTAssertEqual(call(.post, "/v2/vocabulary/proposals", Data(repeating: 65, count: 65_537)).status, 413)
        XCTAssertTrue(try XCTUnwrap(fixture.coordinator.loadedCatalog).snapshot.vocabularyTerms.isEmpty)
    }

    func testCorruptInboxFailsClosed() throws {
        let fixture = try fixture()
        try Data("broken".utf8).write(to: fixture.directory.appendingPathComponent("batches.json"))
        XCTAssertThrowsError(try fixture.inbox.records())
        XCTAssertThrowsError(try submit(batch("corrupt", items: [term()]), fixture))
    }

    private struct Fixture {
        let directory: URL
        let store: VocabularyCatalogStore
        let coordinator: VocabularyCorrectionCoordinator
        let inbox: VocabularyBatchStore
    }
    private final class Fault: @unchecked Sendable { var enabled = false }
    private func fixture(fault: Fault = Fault(), inboxFault: Fault = Fault()) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("foil-batch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = VocabularyCatalogStore(fileURL: directory.appendingPathComponent("catalog.json"), stagedWriter: { data, url in
            if fault.enabled { throw VocabularyBatchError.unavailable }
            try data.write(to: url)
        })
        let coordinator = VocabularyCorrectionCoordinator(store: store, legacyVocabularyData: nil, legacyLocalCorrectionsData: nil)
        try coordinator.activate()
        let inbox = VocabularyBatchStore(fileURL: directory.appendingPathComponent("batches.json"), write: { data, url in
            if inboxFault.enabled { throw VocabularyBatchError.unavailable }
            try data.write(to: url, options: .atomic)
        })
        return .init(directory: directory, store: store, coordinator: coordinator, inbox: inbox)
    }
    private func model(_ fixture: Fixture) -> AgentAccessVocabularyReadModel {
        VocabularyBatchEvaluator.model(snapshot: fixture.coordinator.loadedCatalog!.snapshot, scopes: scopes)
    }
    private func submit(_ request: VocabularyBatchRequest, _ fixture: Fixture) throws -> VocabularyBatchRecord {
        try fixture.inbox.submit(request) { try VocabularyBatchHTTP.validate(request, model: model(fixture)) }.record
    }
    private func batch(_ id: String, items: [VocabularyBatchItem]) -> VocabularyBatchRequest {
        .init(requestID: id, scope: .init(kind: "cleanup_group", id: "agents"), items: items)
    }
    private func term() -> VocabularyBatchItem { .init(id: "term", kind: .preferredTerm, term: "Supabase") }
    private func correction() -> VocabularyBatchItem { .init(id: "correction", kind: .correction, correction: .init(spokenForms: ["super base"], replacement: "Supabase")) }
}

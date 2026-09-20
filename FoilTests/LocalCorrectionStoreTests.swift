import XCTest
@testable import Foil

final class LocalCorrectionStoreTests: XCTestCase {
    func testMissingStoreLoadsEmptyRevisionZero() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(try fixture.store.load(), LocalCorrectionSnapshot())
    }

    func testSaveIsVersionedAndReloadsExactRules() throws {
        let fixture = try makeFixture()
        let rules = [rule(id: "supabase", source: "super base", replacement: "Supabase")]

        let saved = try fixture.store.save(rules: rules, isEnabled: true, expectedRevision: 0)

        XCTAssertEqual(saved.revision, 1)
        XCTAssertTrue(saved.isEnabled)
        XCTAssertEqual(saved.rules, rules)
        XCTAssertEqual(try fixture.store.load(), saved)
    }

    func testRevisionConflictLeavesExistingBytesUntouched() throws {
        let fixture = try makeFixture()
        _ = try fixture.store.save(
            rules: [rule(id: "one", source: "one", replacement: "One")],
            expectedRevision: 0
        )
        let before = try Data(contentsOf: fixture.fileURL)

        XCTAssertThrowsError(
            try fixture.store.save(
                rules: [rule(id: "two", source: "two", replacement: "Two")],
                expectedRevision: 0
            )
        ) { error in
            XCTAssertEqual(
                error as? LocalCorrectionStoreError,
                .revisionConflict(expected: 0, actual: 1)
            )
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), before)
    }

    func testCorruptStoreCannotBeSilentlyOverwritten() throws {
        let fixture = try makeFixture()
        let corrupt = Data("{ definitely-not-json".utf8)
        try corrupt.write(to: fixture.fileURL)

        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? LocalCorrectionStoreError, .unreadable)
        }
        XCTAssertThrowsError(
            try fixture.store.save(
                rules: [rule(id: "one", source: "one", replacement: "One")],
                expectedRevision: 0
            )
        ) { error in
            XCTAssertEqual(error as? LocalCorrectionStoreError, .unreadable)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), corrupt)
    }

    func testFutureSchemaCannotBeSilentlyOverwritten() throws {
        let fixture = try makeFixture()
        let future = Data("{\"schema_version\":999,\"revision\":4,\"rules\":[]}".utf8)
        try future.write(to: fixture.fileURL)

        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? LocalCorrectionStoreError, .unsupportedSchema(999))
        }
        XCTAssertThrowsError(
            try fixture.store.save(rules: [], expectedRevision: 4)
        ) { error in
            XCTAssertEqual(error as? LocalCorrectionStoreError, .unsupportedSchema(999))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), future)
    }

    func testInterruptedAtomicWritePreservesPriorSnapshot() throws {
        let fixture = try makeFixture()
        let original = try fixture.store.save(
            rules: [rule(id: "one", source: "one", replacement: "One")],
            expectedRevision: 0
        )
        let failingStore = LocalCorrectionStore(
            fileURL: fixture.fileURL,
            atomicWriter: { _, _ in throw SimulatedWriteFailure() }
        )

        XCTAssertThrowsError(
            try failingStore.save(
                rules: [rule(id: "two", source: "two", replacement: "Two")],
                expectedRevision: original.revision
            )
        ) { error in
            XCTAssertEqual(error as? LocalCorrectionStoreError, .writeFailed)
        }
        XCTAssertEqual(try fixture.store.load(), original)
    }

    func testSnapshotSaveReturnsReusableCompiledRulesAndRejectsSameRevisionTampering() throws {
        let fixture = try makeFixture()
        let initial = try fixture.store.load()
        let rules = [rule(id: "supabase", source: "super base", replacement: "Supabase")]

        let saved = try fixture.store.save(
            rules: rules,
            isEnabled: true,
            expectedSnapshot: initial
        )
        let result = LocalCorrectionEngine.correct(
            "use super base",
            activeGroup: "agents",
            enabled: saved.snapshot.isEnabled,
            compiled: saved.compiled
        )
        XCTAssertEqual(result.text, "use Supabase")

        let tampered = LocalCorrectionSnapshot(
            revision: saved.snapshot.revision,
            isEnabled: true,
            rules: [rule(id: "tampered", source: "cloud code", replacement: "Claude Code")]
        )
        XCTAssertThrowsError(
            try fixture.store.save(rules: [], expectedSnapshot: tampered)
        ) { error in
            XCTAssertEqual(error as? LocalCorrectionStoreError, .unreadable)
        }
        XCTAssertEqual(try fixture.store.load(), saved.snapshot)
    }

    func testInvalidRulesNeverReplaceValidSnapshot() throws {
        let fixture = try makeFixture()
        let original = try fixture.store.save(
            rules: [rule(id: "one", source: "one", replacement: "One")],
            expectedRevision: 0
        )

        XCTAssertThrowsError(
            try fixture.store.save(
                rules: [
                    rule(id: "a", source: "same", replacement: "A"),
                    rule(id: "b", source: "SAME", replacement: "B")
                ],
                expectedRevision: original.revision
            )
        )
        XCTAssertEqual(try fixture.store.load(), original)
    }

    private func makeFixture() throws -> (store: LocalCorrectionStore, fileURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilLocalCorrectionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(LocalCorrectionStore.fileName)
        return (LocalCorrectionStore(fileURL: fileURL), fileURL)
    }

    private func rule(id: String, source: String, replacement: String) -> LocalCorrectionRule {
        LocalCorrectionRule(
            id: id,
            source: source,
            replacement: replacement,
            group: "agents",
            enabled: true,
            caseSensitive: false
        )
    }
}

private struct SimulatedWriteFailure: Error {}

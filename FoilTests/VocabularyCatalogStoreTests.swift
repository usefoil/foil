import Foundation
import XCTest
@testable import Foil

final class VocabularyCatalogStoreTests: XCTestCase {
    func testMissingLegacySourcesMigrateToVersionedOwnerOnlyCatalog() throws {
        let fixture = try makeFixture()

        let loaded = try fixture.store.loadOrMigrate(
            legacyVocabularyData: nil,
            legacyLocalCorrectionsData: nil
        )

        XCTAssertEqual(loaded.snapshot.schemaVersion, 2)
        XCTAssertEqual(loaded.snapshot.revision, 1)
        XCTAssertEqual(loaded.snapshot.vocabularyCorrections, [])
        XCTAssertEqual(loaded.snapshot.rules, [])
        XCTAssertFalse(loaded.snapshot.localCorrectionsEnabled)
        XCTAssertEqual(
            loaded.snapshot.legacySourceFingerprint,
            VocabularyLegacySourceFingerprint(
                vocabularyCorrectionsData: nil,
                localCorrectionsData: nil
            )
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.catalogURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(permissions & 0o777, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: fixture.directory.path)
        let directoryPermissions = try XCTUnwrap(
            directoryAttributes[.posixPermissions] as? NSNumber
        ).intValue
        XCTAssertEqual(directoryPermissions & 0o777, 0o700)
    }

    func testMigrationPreservesMetadataRuleBytesOrderAndFlagsWithoutTouchingLegacySources() throws {
        let fixture = try makeFixture()
        let createdAt = Date(timeIntervalSinceReferenceDate: 731_234_567.123456)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 731_234_999.654321)
        let first = VocabularyCorrection(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            writtenAs: "Cafe\u{301}",
            correctVersion: "Café",
            note: "product name",
            sourceRecordID: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
            sourceAppName: "Codex",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let second = VocabularyCorrection(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            writtenAs: "super base",
            correctVersion: "Supabase",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let rules = [
            rule(
                id: "vocabulary:\(first.id.uuidString.lowercased())",
                source: first.writtenAs,
                replacement: first.correctVersion,
                group: "agents",
                enabled: false,
                caseSensitive: true
            ),
            rule(
                id: "vocabulary:\(second.id.uuidString.lowercased())",
                source: second.writtenAs,
                replacement: second.correctVersion,
                group: nil,
                enabled: true,
                caseSensitive: false
            )
        ]
        let vocabularyData = try JSONEncoder().encode([first, second])
        let localData = try JSONEncoder().encode(
            LocalCorrectionSnapshot(revision: 17, isEnabled: true, rules: rules)
        )
        try vocabularyData.write(to: fixture.legacyVocabularyURL)
        try localData.write(to: fixture.legacyLocalURL)
        let vocabularyBytesBefore = try Data(contentsOf: fixture.legacyVocabularyURL)
        let localBytesBefore = try Data(contentsOf: fixture.legacyLocalURL)

        let loaded = try fixture.store.loadOrMigrate(
            legacyVocabularyData: vocabularyBytesBefore,
            legacyLocalCorrectionsData: localBytesBefore
        )

        XCTAssertEqual(loaded.snapshot.vocabularyCorrections, [first, second])
        XCTAssertEqual(loaded.snapshot.rules, rules)
        XCTAssertTrue(loaded.snapshot.localCorrectionsEnabled)
        XCTAssertEqual(Array(loaded.snapshot.rules[0].source.utf8), Array(first.writtenAs.utf8))
        XCTAssertEqual(Array(loaded.snapshot.rules[0].replacement.utf8), Array(first.correctVersion.utf8))
        XCTAssertEqual(loaded.snapshot.vocabularyCorrections[0].createdAt, createdAt)
        XCTAssertEqual(loaded.snapshot.vocabularyCorrections[0].updatedAt, updatedAt)
        XCTAssertEqual(try Data(contentsOf: fixture.legacyVocabularyURL), vocabularyBytesBefore)
        XCTAssertEqual(try Data(contentsOf: fixture.legacyLocalURL), localBytesBefore)

        let result = LocalCorrectionEngine.correct(
            "say super base",
            activeGroup: nil,
            enabled: loaded.snapshot.localCorrectionsEnabled,
            compiled: loaded.compiledLocalCorrections
        )
        XCTAssertEqual(result.text, "say Supabase")
    }

    func testInterruptedStagedWriteLeavesNoActiveCatalogOrLegacyMutation() throws {
        let fixture = try makeFixture(stagedWriter: { data, stagingURL in
            try data.prefix(11).write(to: stagingURL)
            throw SimulatedCatalogFailure()
        })
        let vocabularyData = try JSONEncoder().encode([correction()])
        let localData = try JSONEncoder().encode(
            LocalCorrectionSnapshot(rules: [rule()])
        )
        try vocabularyData.write(to: fixture.legacyVocabularyURL)
        try localData.write(to: fixture.legacyLocalURL)

        XCTAssertThrowsError(
            try fixture.store.loadOrMigrate(
                legacyVocabularyData: vocabularyData,
                legacyLocalCorrectionsData: localData
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyCatalogStoreError, .writeFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.catalogURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.legacyVocabularyURL), vocabularyData)
        XCTAssertEqual(try Data(contentsOf: fixture.legacyLocalURL), localData)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix(".tmp") }
                .isEmpty
        )
    }

    func testCommitFailureLeavesExistingCatalogByteIdentical() throws {
        let fixture = try makeFixture()
        let legacy = try legacyData()
        let initial = try fixture.store.loadOrMigrate(
            legacyVocabularyData: legacy.vocabulary,
            legacyLocalCorrectionsData: legacy.local
        )
        let catalogBefore = try Data(contentsOf: fixture.catalogURL)
        let failing = VocabularyCatalogStore(
            fileURL: fixture.catalogURL,
            committer: { _, _ in throw SimulatedCatalogFailure() },
            makeTemporaryName: { "commit-failure" }
        )

        XCTAssertThrowsError(
            try failing.save(
                vocabularyCorrections: initial.snapshot.vocabularyCorrections,
                localCorrectionsEnabled: false,
                rules: initial.snapshot.rules,
                appliedProposalReceipts: [],
                expectedSnapshot: initial.snapshot,
                legacyVocabularyData: legacy.vocabulary,
                legacyLocalCorrectionsData: legacy.local
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyCatalogStoreError, .writeFailed)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), catalogBefore)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.directory.appendingPathComponent(
                    ".\(VocabularyCatalogStore.fileName).commit-failure.tmp"
                ).path
            )
        )
    }

    func testLegacyEditAfterMigrationFailsClosedWithoutOverwritingEitherSide() throws {
        let fixture = try makeFixture()
        let legacy = try legacyData()
        _ = try fixture.store.loadOrMigrate(
            legacyVocabularyData: legacy.vocabulary,
            legacyLocalCorrectionsData: legacy.local
        )
        let catalogBefore = try Data(contentsOf: fixture.catalogURL)
        let changedVocabulary = try JSONEncoder().encode([
            correction(writtenAs: "code ex", correctVersion: "Codex")
        ])
        try changedVocabulary.write(to: fixture.legacyVocabularyURL)

        XCTAssertThrowsError(
            try fixture.store.loadOrMigrate(
                legacyVocabularyData: changedVocabulary,
                legacyLocalCorrectionsData: legacy.local
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyCatalogStoreError, .legacySourcesChanged)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), catalogBefore)
        XCTAssertEqual(try Data(contentsOf: fixture.legacyVocabularyURL), changedVocabulary)
    }

    func testSemanticallyEquivalentLegacyByteEditStillRequiresReconciliation() throws {
        let fixture = try makeFixture()
        let legacy = try legacyData()
        _ = try fixture.store.loadOrMigrate(
            legacyVocabularyData: legacy.vocabulary,
            legacyLocalCorrectionsData: legacy.local
        )
        let catalogBefore = try Data(contentsOf: fixture.catalogURL)
        let decodedLocal = try JSONDecoder().decode(LocalCorrectionSnapshot.self, from: legacy.local)
        let prettyEncoder = JSONEncoder()
        prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reformattedLocal = try prettyEncoder.encode(decodedLocal)
        XCTAssertEqual(
            try JSONDecoder().decode(LocalCorrectionSnapshot.self, from: reformattedLocal),
            decodedLocal
        )

        XCTAssertThrowsError(
            try fixture.store.loadOrMigrate(
                legacyVocabularyData: legacy.vocabulary,
                legacyLocalCorrectionsData: reformattedLocal
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyCatalogStoreError, .legacySourcesChanged)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), catalogBefore)
    }

    func testCorruptAndFutureLegacySourcesDoNotCreateCatalog() throws {
        let futureLocal = Data(#"{"schema_version":999,"revision":3,"is_enabled":true,"rules":[]}"#.utf8)
        let cases: [(Data?, Data?, VocabularyCatalogStoreError)] = [
            (Data("not-json".utf8), nil, .unreadableLegacyVocabulary),
            (nil, Data("not-json".utf8), .unreadableLegacyLocalCorrections),
            (nil, futureLocal, .unsupportedLegacyLocalCorrectionsSchema(999))
        ]

        for (vocabulary, local, expectedError) in cases {
            let fixture = try makeFixture()
            XCTAssertThrowsError(
                try fixture.store.loadOrMigrate(
                    legacyVocabularyData: vocabulary,
                    legacyLocalCorrectionsData: local
                )
            ) { error in
                XCTAssertEqual(error as? VocabularyCatalogStoreError, expectedError)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.catalogURL.path))
        }
    }

    func testInvalidLegacyRulesDoNotCreateCatalog() throws {
        let fixture = try makeFixture()
        let invalidRules = [
            rule(id: "a", source: "same", replacement: "A"),
            rule(id: "b", source: "SAME", replacement: "B")
        ]
        let localData = try JSONEncoder().encode(LocalCorrectionSnapshot(rules: invalidRules))

        XCTAssertThrowsError(
            try fixture.store.loadOrMigrate(
                legacyVocabularyData: nil,
                legacyLocalCorrectionsData: localData
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyCatalogStoreError, .invalidLegacyLocalCorrections)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.catalogURL.path))
    }

    func testCorruptAndFutureCatalogRemainByteIdentical() throws {
        let legacy = try legacyData()
        for (data, expectedError) in [
            (Data("not-json".utf8), VocabularyCatalogStoreError.unreadable),
            (
                Data(#"{"schema_version":999,"revision":1}"#.utf8),
                VocabularyCatalogStoreError.unsupportedSchema(999)
            )
        ] {
            let fixture = try makeFixture()
            try data.write(to: fixture.catalogURL)

            XCTAssertThrowsError(
                try fixture.store.loadOrMigrate(
                    legacyVocabularyData: legacy.vocabulary,
                    legacyLocalCorrectionsData: legacy.local
                )
            ) { error in
                XCTAssertEqual(error as? VocabularyCatalogStoreError, expectedError)
            }
            XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), data)
        }
    }

    func testSaveRejectsStaleRevisionAndSameRevisionTamperingWithoutMutation() throws {
        let fixture = try makeFixture()
        let legacy = try legacyData()
        let initial = try fixture.store.loadOrMigrate(
            legacyVocabularyData: legacy.vocabulary,
            legacyLocalCorrectionsData: legacy.local
        )
        let saved = try fixture.store.save(
            vocabularyCorrections: initial.snapshot.vocabularyCorrections,
            localCorrectionsEnabled: false,
            rules: initial.snapshot.rules,
            appliedProposalReceipts: [],
            expectedSnapshot: initial.snapshot,
            legacyVocabularyData: legacy.vocabulary,
            legacyLocalCorrectionsData: legacy.local
        )
        let bytesAfterSave = try Data(contentsOf: fixture.catalogURL)

        XCTAssertThrowsError(
            try fixture.store.save(
                vocabularyCorrections: [],
                localCorrectionsEnabled: false,
                rules: [],
                appliedProposalReceipts: [],
                expectedSnapshot: initial.snapshot,
                legacyVocabularyData: legacy.vocabulary,
                legacyLocalCorrectionsData: legacy.local
            )
        ) { error in
            XCTAssertEqual(
                error as? VocabularyCatalogStoreError,
                .revisionConflict(expected: 1, actual: 2)
            )
        }

        let tamperedExpectation = VocabularyCatalogSnapshot(
            revision: saved.snapshot.revision,
            vocabularyCorrections: [],
            localCorrectionsEnabled: saved.snapshot.localCorrectionsEnabled,
            rules: saved.snapshot.rules,
            legacySourceFingerprint: saved.snapshot.legacySourceFingerprint
        )
        XCTAssertThrowsError(
            try fixture.store.save(
                vocabularyCorrections: [],
                localCorrectionsEnabled: false,
                rules: [],
                appliedProposalReceipts: [],
                expectedSnapshot: tamperedExpectation,
                legacyVocabularyData: legacy.vocabulary,
                legacyLocalCorrectionsData: legacy.local
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyCatalogStoreError, .unreadable)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), bytesAfterSave)
    }

    func testSaveRejectsRevisionOverflowWithoutMutatingCatalog() throws {
        let fixture = try makeFixture()
        let legacy = try legacyData()
        let snapshot = VocabularyCatalogSnapshot(
            revision: .max,
            vocabularyCorrections: [correction()],
            localCorrectionsEnabled: true,
            rules: [rule()],
            legacySourceFingerprint: VocabularyLegacySourceFingerprint(
                vocabularyCorrectionsData: legacy.vocabulary,
                localCorrectionsData: legacy.local
            )
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fixture.catalogURL)

        XCTAssertThrowsError(
            try fixture.store.save(
                vocabularyCorrections: snapshot.vocabularyCorrections,
                localCorrectionsEnabled: snapshot.localCorrectionsEnabled,
                rules: snapshot.rules,
                appliedProposalReceipts: [],
                expectedSnapshot: snapshot,
                legacyVocabularyData: legacy.vocabulary,
                legacyLocalCorrectionsData: legacy.local
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyCatalogStoreError, .invalidCatalog)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), data)
    }

    func testLinkedRuleDivergenceFailsBeforeMigrationOrSave() throws {
        let fixture = try makeFixture()
        let vocabulary = try JSONEncoder().encode([correction()])
        let mismatchedLocal = try JSONEncoder().encode(
            LocalCorrectionSnapshot(rules: [rule(replacement: "Postgres")])
        )

        XCTAssertThrowsError(
            try fixture.store.loadOrMigrate(
                legacyVocabularyData: vocabulary,
                legacyLocalCorrectionsData: mismatchedLocal
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyCatalogStoreError, .invalidCatalog)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.catalogURL.path))

        let legacy = try legacyData()
        let migrated = try fixture.store.loadOrMigrate(
            legacyVocabularyData: legacy.vocabulary,
            legacyLocalCorrectionsData: legacy.local
        )
        let before = try Data(contentsOf: fixture.catalogURL)
        XCTAssertThrowsError(
            try fixture.store.save(
                vocabularyCorrections: migrated.snapshot.vocabularyCorrections,
                localCorrectionsEnabled: true,
                rules: [rule(replacement: "Postgres")],
                appliedProposalReceipts: [],
                expectedSnapshot: migrated.snapshot,
                legacyVocabularyData: legacy.vocabulary,
                legacyLocalCorrectionsData: legacy.local
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyCatalogStoreError, .invalidCatalog)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), before)
    }

    func testSaveBoundsAppliedReceiptLedgerAndReloadsCompiledSnapshot() throws {
        let fixture = try makeFixture()
        let legacy = try legacyData()
        let initial = try fixture.store.loadOrMigrate(
            legacyVocabularyData: legacy.vocabulary,
            legacyLocalCorrectionsData: legacy.local
        )
        let receipts = (0..<125).map { index in
            VocabularyAppliedProposalReceipt(
                proposalID: "proposal-\(index)",
                requestID: "request-\(index)",
                catalogRevision: 2,
                items: [],
                appliedAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        let saved = try fixture.store.save(
            vocabularyCorrections: initial.snapshot.vocabularyCorrections,
            localCorrectionsEnabled: true,
            rules: initial.snapshot.rules,
            appliedProposalReceipts: receipts,
            expectedSnapshot: initial.snapshot,
            legacyVocabularyData: legacy.vocabulary,
            legacyLocalCorrectionsData: legacy.local
        )
        let reloaded = try fixture.store.load(
            legacyVocabularyData: legacy.vocabulary,
            legacyLocalCorrectionsData: legacy.local
        )

        XCTAssertEqual(saved.snapshot.appliedProposalReceipts.count, 100)
        XCTAssertEqual(saved.snapshot.appliedProposalReceipts.first?.proposalID, "proposal-25")
        XCTAssertEqual(reloaded.snapshot, saved.snapshot)
        XCTAssertEqual(
            LocalCorrectionEngine.correct(
                "use super base",
                activeGroup: "agents",
                enabled: reloaded.snapshot.localCorrectionsEnabled,
                compiled: reloaded.compiledLocalCorrections
            ).text,
            "use Supabase"
        )
    }

    private func makeFixture(
        stagedWriter: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .withoutOverwriting)
        }
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilVocabularyCatalogStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let catalogURL = directory.appendingPathComponent(VocabularyCatalogStore.fileName)
        return Fixture(
            directory: directory,
            catalogURL: catalogURL,
            legacyVocabularyURL: directory.appendingPathComponent("legacy-vocabulary.json"),
            legacyLocalURL: directory.appendingPathComponent(LocalCorrectionStore.fileName),
            store: VocabularyCatalogStore(fileURL: catalogURL, stagedWriter: stagedWriter)
        )
    }

    private func legacyData() throws -> (vocabulary: Data, local: Data) {
        (
            try JSONEncoder().encode([correction()]),
            try JSONEncoder().encode(
                LocalCorrectionSnapshot(revision: 7, isEnabled: true, rules: [rule()])
            )
        )
    }

    private func correction(
        writtenAs: String = "super base",
        correctVersion: String = "Supabase"
    ) -> VocabularyCorrection {
        VocabularyCorrection(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            writtenAs: writtenAs,
            correctVersion: correctVersion,
            note: "database",
            createdAt: Date(timeIntervalSinceReferenceDate: 731_234_567.25),
            updatedAt: Date(timeIntervalSinceReferenceDate: 731_234_999.75)
        )
    }

    private func rule(
        id: String = "vocabulary:11111111-1111-1111-1111-111111111111",
        source: String = "super base",
        replacement: String = "Supabase",
        group: String? = "agents",
        enabled: Bool = true,
        caseSensitive: Bool = false
    ) -> LocalCorrectionRule {
        LocalCorrectionRule(
            id: id,
            source: source,
            replacement: replacement,
            group: group,
            enabled: enabled,
            caseSensitive: caseSensitive
        )
    }
}

private struct Fixture {
    let directory: URL
    let catalogURL: URL
    let legacyVocabularyURL: URL
    let legacyLocalURL: URL
    let store: VocabularyCatalogStore
}

private struct SimulatedCatalogFailure: Error {}

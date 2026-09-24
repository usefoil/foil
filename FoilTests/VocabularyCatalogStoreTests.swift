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

    @MainActor
    func testCoordinatorAppliesReviewedAliasesAtomicallyWithoutEnablingGlobalSwitch() throws {
        let fixture = try makeFixture()
        let coordinator = VocabularyCorrectionCoordinator(
            store: fixture.store,
            legacyVocabularyData: nil,
            legacyLocalCorrectionsData: nil,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        _ = try coordinator.activate()
        let token = String(repeating: "a", count: 64)
        let proposal = VocabularyProposal(
            id: "20000000-0000-0000-0000-000000000001",
            requestID: "reviewed-supabase-codex",
            requestHash: String(repeating: "b", count: 64),
            state: .pending,
            scope: .init(kind: "cleanup_group", id: "agents"),
            corrections: [
                .init(spokenForms: ["Superbase", "super base"], replacement: "Supabase"),
                .init(spokenForms: ["codecs"], replacement: "Codex", note: "Only in agent work")
            ],
            snapshotToken: token,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        let applied = try coordinator.apply(
            proposal: proposal,
            currentSnapshotToken: token,
            enabledScopeIDs: ["agents"]
        )

        XCTAssertFalse(applied.wasReplay)
        XCTAssertEqual(applied.loaded.snapshot.vocabularyCorrections.map(\.writtenAs), [
            "Superbase", "super base", "codecs"
        ])
        XCTAssertEqual(applied.loaded.snapshot.rules.count, 3)
        XCTAssertTrue(applied.loaded.snapshot.rules.allSatisfy { $0.group == "agents" })
        XCTAssertFalse(applied.loaded.snapshot.localCorrectionsEnabled)
        XCTAssertEqual(applied.receipt.items.count, 3)
        XCTAssertEqual(
            LocalCorrectionEngine.correct(
                "Superbase and codecs",
                activeGroup: "agents",
                enabled: true,
                compiled: applied.loaded.compiledLocalCorrections
            ).text,
            "Supabase and Codex"
        )
        XCTAssertEqual(
            LocalCorrectionEngine.correct(
                "Superbase and codecs",
                activeGroup: "messages",
                enabled: true,
                compiled: applied.loaded.compiledLocalCorrections
            ).text,
            "Superbase and codecs"
        )
        XCTAssertEqual(
            LocalCorrectionEngine.correct(
                "Superbase and codecs",
                activeGroup: "agents",
                enabled: applied.loaded.snapshot.localCorrectionsEnabled,
                compiled: applied.loaded.compiledLocalCorrections
            ).text,
            "Superbase and codecs"
        )

        let replay = try coordinator.apply(
            proposal: proposal,
            currentSnapshotToken: token,
            enabledScopeIDs: ["agents"]
        )
        XCTAssertTrue(replay.wasReplay)
        XCTAssertEqual(replay.loaded.snapshot.revision, applied.loaded.snapshot.revision)
        XCTAssertEqual(replay.receipt, applied.receipt)
    }

    @MainActor
    func testCoordinatorRejectsStaleProposalWithoutChangingCatalog() throws {
        let fixture = try makeFixture()
        let coordinator = VocabularyCorrectionCoordinator(
            store: fixture.store,
            legacyVocabularyData: nil,
            legacyLocalCorrectionsData: nil
        )
        _ = try coordinator.activate()
        let before = try Data(contentsOf: fixture.catalogURL)
        let proposal = VocabularyProposal(
            id: UUID().uuidString.lowercased(),
            requestID: "stale-review",
            requestHash: String(repeating: "b", count: 64),
            state: .pending,
            scope: .init(kind: "global", id: "global"),
            corrections: [.init(spokenForms: ["codecs"], replacement: "Codex")],
            snapshotToken: String(repeating: "a", count: 64),
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertThrowsError(
            try coordinator.apply(
                proposal: proposal,
                currentSnapshotToken: String(repeating: "c", count: 64),
                enabledScopeIDs: []
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyCorrectionCoordinatorError, .staleProposal)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), before)
    }

    @MainActor
    func testCoordinatorApplyCommitFailureLeavesCatalogByteIdenticalAndNoReceipt() throws {
        let fixture = try makeFixture()
        let initialCoordinator = VocabularyCorrectionCoordinator(
            store: fixture.store,
            legacyVocabularyData: nil,
            legacyLocalCorrectionsData: nil
        )
        _ = try initialCoordinator.activate()
        let before = try Data(contentsOf: fixture.catalogURL)
        let failingCoordinator = VocabularyCorrectionCoordinator(
            store: VocabularyCatalogStore(
                fileURL: fixture.catalogURL,
                committer: { _, _ in throw SimulatedCatalogFailure() },
                makeTemporaryName: { "proposal-commit-failure" }
            ),
            legacyVocabularyData: nil,
            legacyLocalCorrectionsData: nil
        )
        _ = try failingCoordinator.activate()
        let token = String(repeating: "a", count: 64)
        let proposal = VocabularyProposal(
            id: "20000000-0000-0000-0000-000000000099",
            requestID: "failed-supabase-codex-commit",
            requestHash: String(repeating: "b", count: 64),
            state: .pending,
            scope: .init(kind: "cleanup_group", id: "agents"),
            corrections: [
                .init(spokenForms: ["Superbase", "super base"], replacement: "Supabase"),
                .init(spokenForms: ["codecs"], replacement: "Codex")
            ],
            snapshotToken: token,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertThrowsError(
            try failingCoordinator.apply(
                proposal: proposal,
                currentSnapshotToken: token,
                enabledScopeIDs: ["agents"]
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyCatalogStoreError, .writeFailed)
        }

        XCTAssertEqual(try Data(contentsOf: fixture.catalogURL), before)
        let reloaded = try fixture.store.load(
            legacyVocabularyData: nil,
            legacyLocalCorrectionsData: nil
        )
        XCTAssertTrue(reloaded.snapshot.vocabularyCorrections.isEmpty)
        XCTAssertTrue(reloaded.snapshot.rules.isEmpty)
        XCTAssertTrue(reloaded.snapshot.appliedProposalReceipts.isEmpty)
    }

    @MainActor
    func testAppStateCatalogMutationLeavesLegacySourcesUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilVocabularyCoordinatorAppState-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "com.neonwatty.Foil.VocabularyCoordinator.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        addTeardownBlock { defaults.removePersistentDomain(forName: defaultsName) }
        let legacyCorrection = correction()
        let legacyVocabulary = try JSONEncoder().encode([legacyCorrection])
        defaults.set(legacyVocabulary, forKey: "transcriptCleanupVocabularyCorrections")
        let legacyLocal = try JSONEncoder().encode(
            LocalCorrectionSnapshot(revision: 7, isEnabled: false, rules: [rule()])
        )
        let localURL = directory.appendingPathComponent(LocalCorrectionStore.fileName)
        try legacyLocal.write(to: localURL)
        let catalogURL = directory.appendingPathComponent(VocabularyCatalogStore.fileName)
        let state = AppState(
            localCorrectionStore: LocalCorrectionStore(fileURL: localURL),
            vocabularyCatalogStore: VocabularyCatalogStore(fileURL: catalogURL),
            initialDefaultsOverride: defaults
        )

        let added = try XCTUnwrap(
            state.addVocabularyCorrection(writtenAs: "codecs", correctVersion: "Codex")
        )
        _ = try state.setVocabularyCorrectionLocalScope(id: added.id, groupID: nil)

        XCTAssertEqual(try Data(contentsOf: localURL), legacyLocal)
        XCTAssertEqual(defaults.data(forKey: "transcriptCleanupVocabularyCorrections"), legacyVocabulary)
        let loaded = try VocabularyCatalogStore(fileURL: catalogURL).load(
            legacyVocabularyData: legacyVocabulary,
            legacyLocalCorrectionsData: legacyLocal
        )
        XCTAssertEqual(loaded.snapshot.vocabularyCorrections.count, 2)
        XCTAssertEqual(loaded.snapshot.rules.count, 2)
        XCTAssertEqual(loaded.snapshot.rules.last?.source, "codecs")
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

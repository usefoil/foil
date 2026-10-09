import CryptoKit
import Darwin
import Foundation

struct VocabularyLegacySourceFingerprint: Codable, Equatable, Sendable {
    let vocabularyCorrectionsSHA256: String?
    let localCorrectionsSHA256: String?
    let vocabularyTermsSHA256: String?
    let preferredTermsTextSHA256: String?
    let previousCatalogSHA256: String?

    enum CodingKeys: String, CodingKey {
        case vocabularyCorrectionsSHA256 = "vocabulary_corrections_sha256"
        case localCorrectionsSHA256 = "local_corrections_sha256"
        case vocabularyTermsSHA256 = "vocabulary_terms_sha256"
        case preferredTermsTextSHA256 = "preferred_terms_text_sha256"
        case previousCatalogSHA256 = "previous_catalog_sha256"
    }

    init(vocabularyCorrectionsData: Data?, localCorrectionsData: Data?, vocabularyTermsData: Data? = nil,
         preferredTermsText: String? = nil, previousCatalogData: Data? = nil) {
        vocabularyCorrectionsSHA256 = vocabularyCorrectionsData.map(Self.digest)
        localCorrectionsSHA256 = localCorrectionsData.map(Self.digest)
        vocabularyTermsSHA256 = vocabularyTermsData.map(Self.digest)
        // Registered defaults expose an absent legacy text value as an empty string.
        preferredTermsTextSHA256 = preferredTermsText.flatMap { $0.isEmpty ? nil : Self.digest(Data($0.utf8)) }
        previousCatalogSHA256 = previousCatalogData.map(Self.digest)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct VocabularyAppliedCorrectionReceipt: Codable, Equatable, Sendable {
    let proposalItemIndex: Int
    let aliasIndex: Int
    let correctionID: UUID
    let ruleID: String

    enum CodingKeys: String, CodingKey {
        case proposalItemIndex = "proposal_item_index"
        case aliasIndex = "alias_index"
        case correctionID = "correction_id"
        case ruleID = "rule_id"
    }
}

struct VocabularyAppliedProposalReceipt: Codable, Equatable, Sendable {
    let proposalID: String
    let requestID: String
    let catalogRevision: Int
    let items: [VocabularyAppliedCorrectionReceipt]
    let appliedAt: Date
    var batchItems: [VocabularyBatchAppliedItem]? = nil
    var requestDigest: String? = nil
    var reviewedDigest: String? = nil
    var scope: VocabularyProposalScope? = nil
    var grantID: String? = nil

    enum CodingKeys: String, CodingKey {
        case proposalID = "proposal_id"
        case requestID = "request_id"
        case catalogRevision = "catalog_revision"
        case items
        case appliedAt = "applied_at"
        case batchItems = "batch_items", requestDigest = "request_digest", reviewedDigest = "reviewed_digest", scope, grantID = "grant_id"
    }
}

struct VocabularyCatalogSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3

    let schemaVersion: Int
    let revision: Int
    let vocabularyCorrections: [VocabularyCorrection]
    let vocabularyTerms: [VocabularyTerm]
    let localCorrectionsEnabled: Bool
    let rules: [LocalCorrectionRule]
    let appliedProposalReceipts: [VocabularyAppliedProposalReceipt]
    let legacySourceFingerprint: VocabularyLegacySourceFingerprint

    init(
        revision: Int,
        vocabularyCorrections: [VocabularyCorrection],
        vocabularyTerms: [VocabularyTerm] = [],
        localCorrectionsEnabled: Bool,
        rules: [LocalCorrectionRule],
        appliedProposalReceipts: [VocabularyAppliedProposalReceipt] = [],
        legacySourceFingerprint: VocabularyLegacySourceFingerprint
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.revision = revision
        self.vocabularyCorrections = vocabularyCorrections
        self.vocabularyTerms = vocabularyTerms
        self.localCorrectionsEnabled = localCorrectionsEnabled
        self.rules = rules
        self.appliedProposalReceipts = appliedProposalReceipts
        self.legacySourceFingerprint = legacySourceFingerprint
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case revision
        case vocabularyCorrections = "vocabulary_corrections"
        case vocabularyTerms = "vocabulary_terms"
        case localCorrectionsEnabled = "local_corrections_enabled"
        case rules
        case appliedProposalReceipts = "applied_proposal_receipts"
        case legacySourceFingerprint = "legacy_source_fingerprint"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        revision = try values.decode(Int.self, forKey: .revision)
        vocabularyCorrections = try values.decode([VocabularyCorrection].self, forKey: .vocabularyCorrections)
        vocabularyTerms = schemaVersion == 2 ? [] : try values.decode([VocabularyTerm].self, forKey: .vocabularyTerms)
        localCorrectionsEnabled = try values.decode(Bool.self, forKey: .localCorrectionsEnabled)
        rules = try values.decode([LocalCorrectionRule].self, forKey: .rules)
        appliedProposalReceipts = try values.decode([VocabularyAppliedProposalReceipt].self, forKey: .appliedProposalReceipts)
        legacySourceFingerprint = try values.decode(VocabularyLegacySourceFingerprint.self, forKey: .legacySourceFingerprint)
    }
}

struct LoadedVocabularyCatalog: Sendable {
    let snapshot: VocabularyCatalogSnapshot
    let compiledLocalCorrections: CompiledLocalCorrections
}

enum VocabularyCatalogStoreError: Error, Equatable {
    case unreadable
    case unsupportedSchema(Int)
    case unreadableLegacyVocabulary
    case unreadableLegacyTerms
    case unreadableLegacyLocalCorrections
    case unsupportedLegacyLocalCorrectionsSchema(Int)
    case invalidLegacyLocalCorrections
    case invalidCatalog
    case legacySourcesChanged
    case revisionConflict(expected: Int, actual: Int)
    case writeFailed
}

final class VocabularyCatalogStore: @unchecked Sendable {
    static let fileName = "vocabulary-catalog-v3.json"
    static let previousFileName = "vocabulary-catalog-v2.json"
    static let maximumAppliedProposalReceipts = 100

    let fileURL: URL
    private let fileManager: FileManager
    private let stagedWriter: @Sendable (Data, URL) throws -> Void
    private let committer: @Sendable (URL, URL) throws -> Void
    private let makeTemporaryName: @Sendable () -> String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        stagedWriter: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try VocabularyCatalogStore.writeOwnerOnly(data, to: url)
        },
        committer: @escaping @Sendable (URL, URL) throws -> Void = { stagingURL, destinationURL in
            guard rename(stagingURL.path, destinationURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        },
        makeTemporaryName: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.stagedWriter = stagedWriter
        self.committer = committer
        self.makeTemporaryName = makeTemporaryName
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
    }

    convenience init(fileManager: FileManager = .default) {
        let directory: URL
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            directory = fileManager.temporaryDirectory.appendingPathComponent(
                "Foil Vocabulary Catalog Unit Tests \(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directoryName = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                ? "Foil UI Tests"
                : AppBrand.applicationSupportDirectoryName
            directory = appSupport.appendingPathComponent(directoryName, isDirectory: true)
        }
        self.init(fileURL: directory.appendingPathComponent(Self.fileName), fileManager: fileManager)
    }

    func loadOrMigrate(
        legacyVocabularyData: Data?,
        legacyLocalCorrectionsData: Data?,
        legacyTermsData: Data? = nil,
        legacyPreferredTermsText: String? = nil
    ) throws -> LoadedVocabularyCatalog {
        lock.lock()
        defer { lock.unlock() }

        let previousData = try previousCatalogData()
        let fingerprint = VocabularyLegacySourceFingerprint(
            vocabularyCorrectionsData: legacyVocabularyData,
            localCorrectionsData: legacyLocalCorrectionsData,
            vocabularyTermsData: legacyTermsData,
            preferredTermsText: legacyPreferredTermsText,
            previousCatalogData: previousData
        )
        if fileManager.fileExists(atPath: fileURL.path) {
            let loaded = try decodeCatalog()
            guard loaded.snapshot.legacySourceFingerprint == fingerprint else {
                throw VocabularyCatalogStoreError.legacySourcesChanged
            }
            return loaded
        }

        let previous = try previousData.map { try decodeCatalog(data: $0, expectedSchema: 2).snapshot }
        if let previous {
            guard previous.legacySourceFingerprint.vocabularyCorrectionsSHA256 == fingerprint.vocabularyCorrectionsSHA256,
                  previous.legacySourceFingerprint.localCorrectionsSHA256 == fingerprint.localCorrectionsSHA256 else {
                throw VocabularyCatalogStoreError.legacySourcesChanged
            }
        }
        let vocabularyCorrections = try previous?.vocabularyCorrections ?? decodeLegacyVocabulary(legacyVocabularyData)
        let localCorrections = try previous.map {
            LocalCorrectionSnapshot(revision: $0.revision, isEnabled: $0.localCorrectionsEnabled, rules: $0.rules)
        } ?? decodeLegacyLocalCorrections(legacyLocalCorrectionsData)
        let vocabularyTerms = try decodeLegacyTerms(legacyTermsData, fallback: legacyPreferredTermsText)
        let compiled: CompiledLocalCorrections
        do {
            compiled = try LocalCorrectionEngine.compile(localCorrections.rules)
        } catch {
            throw VocabularyCatalogStoreError.invalidLegacyLocalCorrections
        }
        let snapshot = VocabularyCatalogSnapshot(
            revision: previous?.revision ?? 1,
            vocabularyCorrections: vocabularyCorrections,
            vocabularyTerms: vocabularyTerms,
            localCorrectionsEnabled: localCorrections.isEnabled,
            rules: localCorrections.rules,
            appliedProposalReceipts: previous?.appliedProposalReceipts ?? [],
            legacySourceFingerprint: fingerprint
        )
        guard Self.isValid(snapshot) else {
            throw VocabularyCatalogStoreError.invalidCatalog
        }
        try persist(snapshot)
        return LoadedVocabularyCatalog(snapshot: snapshot, compiledLocalCorrections: compiled)
    }

    func load(
        legacyVocabularyData: Data?,
        legacyLocalCorrectionsData: Data?,
        legacyTermsData: Data? = nil,
        legacyPreferredTermsText: String? = nil
    ) throws -> LoadedVocabularyCatalog {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw VocabularyCatalogStoreError.unreadable
        }
        let loaded = try decodeCatalog()
        let previousData = try previousCatalogData()
        let fingerprint = VocabularyLegacySourceFingerprint(
            vocabularyCorrectionsData: legacyVocabularyData,
            localCorrectionsData: legacyLocalCorrectionsData,
            vocabularyTermsData: legacyTermsData,
            preferredTermsText: legacyPreferredTermsText,
            previousCatalogData: previousData
        )
        guard loaded.snapshot.legacySourceFingerprint == fingerprint else {
            throw VocabularyCatalogStoreError.legacySourcesChanged
        }
        return loaded
    }

    func save(
        vocabularyCorrections: [VocabularyCorrection],
        vocabularyTerms: [VocabularyTerm]? = nil,
        localCorrectionsEnabled: Bool,
        rules: [LocalCorrectionRule],
        appliedProposalReceipts: [VocabularyAppliedProposalReceipt],
        expectedSnapshot: VocabularyCatalogSnapshot,
        preserveRevisionForReceiptOnlyCommit: Bool = false,
        legacyVocabularyData: Data?,
        legacyLocalCorrectionsData: Data?,
        legacyTermsData: Data? = nil,
        legacyPreferredTermsText: String? = nil
    ) throws -> LoadedVocabularyCatalog {
        lock.lock()
        defer { lock.unlock() }

        let current = try decodeCatalog().snapshot
        guard current == expectedSnapshot else {
            if current.revision != expectedSnapshot.revision {
                throw VocabularyCatalogStoreError.revisionConflict(
                    expected: expectedSnapshot.revision,
                    actual: current.revision
                )
            }
            throw VocabularyCatalogStoreError.unreadable
        }
        let previousData = try previousCatalogData()
        let fingerprint = VocabularyLegacySourceFingerprint(
            vocabularyCorrectionsData: legacyVocabularyData,
            localCorrectionsData: legacyLocalCorrectionsData,
            vocabularyTermsData: legacyTermsData,
            preferredTermsText: legacyPreferredTermsText,
            previousCatalogData: previousData
        )
        guard current.legacySourceFingerprint == fingerprint else {
            throw VocabularyCatalogStoreError.legacySourcesChanged
        }

        guard PreferredTermPolicy.validChanges(vocabularyTerms ?? current.vocabularyTerms, from: current.vocabularyTerms) else {
            throw VocabularyCatalogStoreError.invalidCatalog
        }
        let compiled: CompiledLocalCorrections
        do {
            compiled = try LocalCorrectionEngine.compile(rules)
        } catch {
            throw VocabularyCatalogStoreError.invalidCatalog
        }
        let snapshot = VocabularyCatalogSnapshot(
            revision: current.revision + ((preserveRevisionForReceiptOnlyCommit &&
                vocabularyCorrections == current.vocabularyCorrections &&
                (vocabularyTerms ?? current.vocabularyTerms) == current.vocabularyTerms &&
                localCorrectionsEnabled == current.localCorrectionsEnabled && rules == current.rules) ? 0 : 1),
            vocabularyCorrections: vocabularyCorrections,
            vocabularyTerms: vocabularyTerms ?? current.vocabularyTerms,
            localCorrectionsEnabled: localCorrectionsEnabled,
            rules: rules,
            appliedProposalReceipts: Array(
                appliedProposalReceipts.suffix(Self.maximumAppliedProposalReceipts)
            ),
            legacySourceFingerprint: current.legacySourceFingerprint
        )
        guard Self.isValid(snapshot) else {
            throw VocabularyCatalogStoreError.invalidCatalog
        }
        try persist(snapshot)
        return LoadedVocabularyCatalog(snapshot: snapshot, compiledLocalCorrections: compiled)
    }

    private func decodeCatalog() throws -> LoadedVocabularyCatalog {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw VocabularyCatalogStoreError.unreadable
        }
        return try decodeCatalog(data: data, expectedSchema: VocabularyCatalogSnapshot.currentSchemaVersion)
    }

    private func decodeCatalog(data: Data, expectedSchema: Int) throws -> LoadedVocabularyCatalog {
        let schemaVersion: Int
        do {
            schemaVersion = try JSONDecoder().decode(SchemaHeader.self, from: data).schemaVersion
        } catch {
            throw VocabularyCatalogStoreError.unreadable
        }
        guard schemaVersion == expectedSchema else {
            throw VocabularyCatalogStoreError.unsupportedSchema(schemaVersion)
        }
        do {
            let snapshot = try decoder.decode(VocabularyCatalogSnapshot.self, from: data)
            guard Self.isValid(snapshot) else {
                throw VocabularyCatalogStoreError.invalidCatalog
            }
            let compiled = try LocalCorrectionEngine.compile(snapshot.rules)
            return LoadedVocabularyCatalog(snapshot: snapshot, compiledLocalCorrections: compiled)
        } catch let error as VocabularyCatalogStoreError {
            throw error
        } catch {
            throw VocabularyCatalogStoreError.invalidCatalog
        }
    }

    private func previousCatalogData() throws -> Data? {
        let url = fileURL.deletingLastPathComponent().appendingPathComponent(Self.previousFileName)
        guard url != fileURL, fileManager.fileExists(atPath: url.path) else { return nil }
        do { return try Data(contentsOf: url) }
        catch { throw VocabularyCatalogStoreError.unreadable }
    }

    private func decodeLegacyTerms(_ data: Data?, fallback: String?) throws -> [VocabularyTerm] {
        var terms: [VocabularyTerm]
        if let data {
            do { terms = try decoder.decode([VocabularyTerm].self, from: data) }
            catch { throw VocabularyCatalogStoreError.unreadableLegacyTerms }
            guard Set(terms.map(\.id)).count == terms.count,
                  terms.allSatisfy({ $0.scopeID == nil && $0.createdAt <= $0.updatedAt }) else {
                throw VocabularyCatalogStoreError.unreadableLegacyTerms
            }
        } else { terms = [] }
        if terms.isEmpty {
            terms = (fallback ?? "").components(separatedBy: .newlines)
                .map { VocabularyTerm(term: PreferredTermPolicy.normalized($0)) }
                .filter { !$0.term.isEmpty }
        }
        var seen = Set<String>()
        terms = terms.compactMap { value in
            var term = value
            term.term = PreferredTermPolicy.normalized(term.term)
            guard seen.insert(PreferredTermPolicy.identity(term.term)).inserted else { return nil }
            return term
        }
        guard PreferredTermPolicy.isValidStored(terms) else { throw VocabularyCatalogStoreError.unreadableLegacyTerms }
        return terms
    }

    private func decodeLegacyVocabulary(_ data: Data?) throws -> [VocabularyCorrection] {
        guard let data else { return [] }
        do {
            let corrections = try JSONDecoder().decode([VocabularyCorrection].self, from: data)
            guard Set(corrections.map(\.id)).count == corrections.count,
                  corrections.allSatisfy({
                      !$0.writtenAs.isEmpty &&
                          !$0.correctVersion.isEmpty &&
                          $0.createdAt <= $0.updatedAt
                  }) else {
                throw VocabularyCatalogStoreError.unreadableLegacyVocabulary
            }
            return corrections
        } catch let error as VocabularyCatalogStoreError {
            throw error
        } catch {
            throw VocabularyCatalogStoreError.unreadableLegacyVocabulary
        }
    }

    private func decodeLegacyLocalCorrections(_ data: Data?) throws -> LocalCorrectionSnapshot {
        guard let data else { return LocalCorrectionSnapshot() }
        let schemaVersion: Int
        do {
            schemaVersion = try JSONDecoder().decode(SchemaHeader.self, from: data).schemaVersion
        } catch {
            throw VocabularyCatalogStoreError.unreadableLegacyLocalCorrections
        }
        guard schemaVersion == LocalCorrectionSnapshot.currentSchemaVersion else {
            throw VocabularyCatalogStoreError.unsupportedLegacyLocalCorrectionsSchema(schemaVersion)
        }
        do {
            let snapshot = try JSONDecoder().decode(LocalCorrectionSnapshot.self, from: data)
            guard snapshot.revision >= 0 else {
                throw VocabularyCatalogStoreError.unreadableLegacyLocalCorrections
            }
            return snapshot
        } catch let error as VocabularyCatalogStoreError {
            throw error
        } catch {
            throw VocabularyCatalogStoreError.unreadableLegacyLocalCorrections
        }
    }

    private func persist(_ snapshot: VocabularyCatalogSnapshot) throws {
        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            throw VocabularyCatalogStoreError.writeFailed
        }

        let directory = fileURL.deletingLastPathComponent()
        let stagingURL = directory.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(makeTemporaryName()).tmp"
        )
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try stagedWriter(data, stagingURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stagingURL.path)
            try committer(stagingURL, fileURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw VocabularyCatalogStoreError.writeFailed
        }
    }

    private static func isValid(_ snapshot: VocabularyCatalogSnapshot) -> Bool {
        guard PreferredTermPolicy.isValidStored(snapshot.vocabularyTerms),
              snapshot.revision >= 1,
              snapshot.revision < Int.max,
              snapshot.appliedProposalReceipts.count <= maximumAppliedProposalReceipts,
              Set(snapshot.vocabularyCorrections.map(\.id)).count == snapshot.vocabularyCorrections.count,
              Set(snapshot.appliedProposalReceipts.map(\.proposalID)).count == snapshot.appliedProposalReceipts.count,
              Set(snapshot.appliedProposalReceipts.map(\.requestID)).count == snapshot.appliedProposalReceipts.count,
              snapshot.vocabularyCorrections.allSatisfy({
                  !$0.writtenAs.isEmpty &&
                      !$0.correctVersion.isEmpty &&
                      $0.createdAt <= $0.updatedAt
              }),
              snapshot.appliedProposalReceipts.allSatisfy({ receipt in
                  !receipt.proposalID.isEmpty &&
                      !receipt.requestID.isEmpty &&
                      receipt.catalogRevision > 0 &&
                      receipt.catalogRevision <= snapshot.revision &&
                      receipt.items.allSatisfy({
                          $0.proposalItemIndex >= 0 &&
                              $0.aliasIndex >= 0 &&
                              !$0.ruleID.isEmpty
                      })
              }) else {
            return false
        }
        for receipt in snapshot.appliedProposalReceipts where receipt.batchItems != nil {
            guard let items = receipt.batchItems, !items.isEmpty,
                  let requestDigest = receipt.requestDigest, isSHA256Digest(requestDigest),
                  let reviewedDigest = receipt.reviewedDigest, isSHA256Digest(reviewedDigest),
                  receipt.scope != nil, Set(items.map(\.itemID)).count == items.count,
                  items.allSatisfy({ VocabularyBatchEvaluator.validID($0.itemID) &&
                    ["added", "already_present"].contains($0.disposition) && !$0.entryIDs.isEmpty &&
                    $0.entryIDs.allSatisfy { UUID(uuidString: $0) != nil } }) else { return false }
        }
        for digest in [
            snapshot.legacySourceFingerprint.vocabularyCorrectionsSHA256,
            snapshot.legacySourceFingerprint.localCorrectionsSHA256,
            snapshot.legacySourceFingerprint.vocabularyTermsSHA256,
            snapshot.legacySourceFingerprint.preferredTermsTextSHA256,
            snapshot.legacySourceFingerprint.previousCatalogSHA256
        ].compactMap({ $0 }) where !isSHA256Digest(digest) {
            return false
        }
        let correctionsByID = Dictionary(
            uniqueKeysWithValues: snapshot.vocabularyCorrections.map { ($0.id, $0) }
        )
        for rule in snapshot.rules where rule.id.hasPrefix("vocabulary:") {
            let suffix = String(rule.id.dropFirst("vocabulary:".count))
            guard let correctionID = UUID(uuidString: suffix),
                  let correction = correctionsByID[correctionID],
                  rule.source.utf8.elementsEqual(correction.writtenAs.utf8),
                  rule.replacement.utf8.elementsEqual(correction.correctVersion.utf8) else {
                return false
            }
        }
        for rule in snapshot.rules where rule.id.hasPrefix("suppression:") {
            let suffix = String(rule.id.dropFirst("suppression:".count))
            guard let separator = suffix.firstIndex(of: ":"),
                  let correctionID = UUID(uuidString: String(suffix[..<separator])),
                  let correction = correctionsByID[correctionID],
                  let groupID = rule.group,
                  String(suffix[suffix.index(after: separator)...]) == groupID,
                  rule.suppressesGlobal,
                  rule.source.utf8.elementsEqual(correction.writtenAs.utf8),
                  rule.replacement.utf8.elementsEqual(correction.writtenAs.utf8) else {
                return false
            }
        }
        return true
    }

    private static func isSHA256Digest(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }

    static func writeOwnerOnly(_ data: Data, to url: URL) throws {
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private struct SchemaHeader: Decodable {
        let schemaVersion: Int

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
        }
    }
}

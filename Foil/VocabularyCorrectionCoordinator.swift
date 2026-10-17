import Foundation

enum VocabularyCorrectionCoordinatorError: Error, Equatable {
    case notActivated
    case staleProposal
    case invalidProposalState
    case invalidScope
    case proposalIdentityConflict
}

@MainActor
final class VocabularyCorrectionCoordinator {
    private let store: VocabularyCatalogStore
    private let legacyVocabularyData: Data?
    private let legacyLocalCorrectionsData: Data?
    private let legacyTermsData: Data?
    private let legacyPreferredTermsText: String?
    private let now: () -> Date
    private let makeID: () -> UUID
    private(set) var loadedCatalog: LoadedVocabularyCatalog?

    init(
        store: VocabularyCatalogStore,
        legacyVocabularyData: Data?,
        legacyLocalCorrectionsData: Data?,
        legacyTermsData: Data? = nil,
        legacyPreferredTermsText: String? = nil,
        now: @escaping () -> Date = { Date() },
        makeID: @escaping () -> UUID = { UUID() }
    ) {
        self.store = store
        self.legacyVocabularyData = legacyVocabularyData
        self.legacyLocalCorrectionsData = legacyLocalCorrectionsData
        self.legacyTermsData = legacyTermsData
        self.legacyPreferredTermsText = legacyPreferredTermsText
        self.now = now
        self.makeID = makeID
    }

    @discardableResult
    func activate() throws -> LoadedVocabularyCatalog {
        let loaded = try store.loadOrMigrate(
            legacyVocabularyData: legacyVocabularyData,
            legacyLocalCorrectionsData: legacyLocalCorrectionsData,
            legacyTermsData: legacyTermsData,
            legacyPreferredTermsText: legacyPreferredTermsText
        )
        loadedCatalog = loaded
        return loaded
    }

    @discardableResult
    func save(
        vocabularyCorrections: [VocabularyCorrection],
        vocabularyTerms: [VocabularyTerm]? = nil,
        localCorrectionsEnabled: Bool,
        rules: [LocalCorrectionRule]
    ) throws -> LoadedVocabularyCatalog {
        guard let current = loadedCatalog else {
            throw VocabularyCorrectionCoordinatorError.notActivated
        }
        let loaded = try store.save(
            vocabularyCorrections: vocabularyCorrections,
            vocabularyTerms: vocabularyTerms,
            localCorrectionsEnabled: localCorrectionsEnabled,
            rules: rules,
            appliedProposalReceipts: current.snapshot.appliedProposalReceipts,
            expectedSnapshot: current.snapshot,
            legacyVocabularyData: legacyVocabularyData,
            legacyLocalCorrectionsData: legacyLocalCorrectionsData,
            legacyTermsData: legacyTermsData,
            legacyPreferredTermsText: legacyPreferredTermsText
        )
        loadedCatalog = loaded
        return loaded
    }

    @discardableResult
    func apply(
        proposal: VocabularyProposal,
        currentSnapshotToken: String,
        enabledScopeIDs: Set<String>
    ) throws -> (loaded: LoadedVocabularyCatalog, receipt: VocabularyAppliedProposalReceipt, wasReplay: Bool) {
        guard let current = loadedCatalog else {
            throw VocabularyCorrectionCoordinatorError.notActivated
        }
        if let receipt = current.snapshot.appliedProposalReceipts.first(where: {
            $0.proposalID == proposal.id || $0.requestID == proposal.requestID
        }) {
            guard receipt.proposalID == proposal.id, receipt.requestID == proposal.requestID else {
                throw VocabularyCorrectionCoordinatorError.proposalIdentityConflict
            }
            return (current, receipt, true)
        }
        guard proposal.state == .pending else {
            throw VocabularyCorrectionCoordinatorError.invalidProposalState
        }
        guard proposal.snapshotToken == currentSnapshotToken else {
            throw VocabularyCorrectionCoordinatorError.staleProposal
        }

        let scopeID: String?
        switch proposal.scope.kind {
        case "global":
            guard proposal.scope.id == "global" else {
                throw VocabularyCorrectionCoordinatorError.invalidScope
            }
            scopeID = nil
        case "cleanup_group":
            guard enabledScopeIDs.contains(proposal.scope.id) else {
                throw VocabularyCorrectionCoordinatorError.invalidScope
            }
            scopeID = proposal.scope.id
        default:
            throw VocabularyCorrectionCoordinatorError.invalidScope
        }

        let timestamp = now()
        var corrections = current.snapshot.vocabularyCorrections
        var rules = current.snapshot.rules
        var itemReceipts: [VocabularyAppliedCorrectionReceipt] = []
        for (proposalItemIndex, proposed) in proposal.corrections.enumerated() {
            for (aliasIndex, spokenForm) in proposed.spokenForms.enumerated() {
                let correctionID = makeID()
                let ruleID = "vocabulary:\(correctionID.uuidString.lowercased())"
                corrections.append(VocabularyCorrection(
                    id: correctionID,
                    writtenAs: spokenForm,
                    correctVersion: proposed.replacement,
                    note: proposed.note,
                    createdAt: timestamp,
                    updatedAt: timestamp
                ))
                rules.append(LocalCorrectionRule(
                    id: ruleID,
                    source: spokenForm,
                    replacement: proposed.replacement,
                    group: scopeID,
                    enabled: true,
                    caseSensitive: proposed.caseSensitive,
                    matchPunctuationVariants: proposed.matchPunctuationVariants &&
                        LocalCorrectionEngine.supportsPunctuationVariants(spokenForm)
                ))
                itemReceipts.append(VocabularyAppliedCorrectionReceipt(
                    proposalItemIndex: proposalItemIndex,
                    aliasIndex: aliasIndex,
                    correctionID: correctionID,
                    ruleID: ruleID
                ))
            }
        }

        // The catalog revision is known before the atomic save because the store
        // accepts exactly the loaded snapshot or fails closed.
        let receipt = VocabularyAppliedProposalReceipt(
            proposalID: proposal.id,
            requestID: proposal.requestID,
            catalogRevision: current.snapshot.revision + 1,
            items: itemReceipts,
            appliedAt: timestamp
        )
        let loaded = try store.save(
            vocabularyCorrections: corrections,
            localCorrectionsEnabled: current.snapshot.localCorrectionsEnabled,
            rules: rules,
            appliedProposalReceipts: current.snapshot.appliedProposalReceipts + [receipt],
            expectedSnapshot: current.snapshot,
            legacyVocabularyData: legacyVocabularyData,
            legacyLocalCorrectionsData: legacyLocalCorrectionsData,
            legacyTermsData: legacyTermsData,
            legacyPreferredTermsText: legacyPreferredTermsText
        )
        loadedCatalog = loaded
        return (loaded, receipt, false)
    }

    func applyBatch(
        _ record: VocabularyBatchRecord,
        scopes: [AgentAccessVocabularyScope],
        authorize: () throws -> Void = {}
    ) throws -> (loaded: LoadedVocabularyCatalog, receipt: VocabularyAppliedProposalReceipt) {
        guard let current = loadedCatalog else { throw VocabularyCorrectionCoordinatorError.notActivated }
        if let receipt = current.snapshot.appliedProposalReceipts.first(where: {
            $0.proposalID == record.id || $0.requestID == record.originalRequest.requestID
        }) {
            guard receipt.proposalID == record.id, receipt.requestDigest == record.requestDigest,
                  try receipt.reviewedDigest == record.reviewedRequest.digest(), receipt.batchItems != nil else {
                throw VocabularyBatchError.conflict("This request identity belongs to a different saved operation.")
            }
            return (current, receipt)
        }
        guard record.state == .pending else { throw VocabularyBatchError.conflict("This batch is no longer pending.") }
        let request = record.reviewedRequest.normalized()
        let model = VocabularyBatchEvaluator.model(snapshot: current.snapshot, scopes: scopes)
        let preview = VocabularyBatchEvaluator.preview(request, model: model)
        guard preview.valid else {
            throw VocabularyBatchError.conflict((preview.issues + preview.items.filter { $0.disposition == .conflict || $0.disposition == .invalid }.map(\.message)).joined(separator: " "))
        }
        let scopeID = request.scope.kind == "global" ? nil : request.scope.id
        let timestamp = now()
        var terms = current.snapshot.vocabularyTerms
        var corrections = current.snapshot.vocabularyCorrections
        var rules = current.snapshot.rules
        var items: [VocabularyBatchAppliedItem] = []
        for row in preview.items {
            var entryIDs = row.existingIDs
            if row.disposition == .add {
                switch row.item.kind {
                case .preferredTerm:
                    guard let term = row.item.term else { throw VocabularyBatchError.invalid("A preferred term is missing.") }
                    let id = makeID()
                    terms.append(.init(id: id, term: term, note: row.item.note, scopeID: scopeID, createdAt: timestamp, updatedAt: timestamp))
                    entryIDs.append(id.uuidString.lowercased())
                case .correction:
                    guard let correction = row.item.correction else { throw VocabularyBatchError.invalid("A correction is missing.") }
                    for alias in correction.spokenForms {
                        if model.corrections.contains(where: { row.existingIDs.contains($0.id) && $0.writtenAs == alias }) { continue }
                        let id = makeID()
                        let stringID = id.uuidString.lowercased()
                        corrections.append(.init(id: id, writtenAs: alias, correctVersion: correction.replacement, note: correction.note, createdAt: timestamp, updatedAt: timestamp))
                        rules.append(.init(id: "vocabulary:\(stringID)", source: alias, replacement: correction.replacement, group: scopeID, enabled: true, caseSensitive: correction.caseSensitive, matchPunctuationVariants: correction.matchPunctuationVariants && LocalCorrectionEngine.supportsPunctuationVariants(alias)))
                        entryIDs.append(stringID)
                    }
                }
            }
            items.append(.init(itemID: row.item.id, kind: row.item.kind, disposition: row.disposition == .alreadyPresent ? "already_present" : "added", entryIDs: entryIDs))
        }
        let changed = terms != current.snapshot.vocabularyTerms || corrections != current.snapshot.vocabularyCorrections || rules != current.snapshot.rules
        let receipt = VocabularyAppliedProposalReceipt(
            proposalID: record.id, requestID: record.originalRequest.requestID,
            catalogRevision: current.snapshot.revision + (changed ? 1 : 0), items: [], appliedAt: timestamp,
            batchItems: items, requestDigest: record.requestDigest,
            reviewedDigest: try request.digest(), scope: request.scope, grantID: record.grantID
        )
        // Authorization is checked after revalidation, immediately before the synchronous atomic save.
        try authorize()
        let loaded = try store.save(
            vocabularyCorrections: corrections, vocabularyTerms: terms,
            localCorrectionsEnabled: current.snapshot.localCorrectionsEnabled, rules: rules,
            appliedProposalReceipts: current.snapshot.appliedProposalReceipts + [receipt],
            expectedSnapshot: current.snapshot, preserveRevisionForReceiptOnlyCommit: true,
            legacyVocabularyData: legacyVocabularyData, legacyLocalCorrectionsData: legacyLocalCorrectionsData,
            legacyTermsData: legacyTermsData, legacyPreferredTermsText: legacyPreferredTermsText
        )
        loadedCatalog = loaded
        return (loaded, receipt)
    }

}

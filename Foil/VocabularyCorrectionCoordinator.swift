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
    private let now: () -> Date
    private let makeID: () -> UUID
    private(set) var loadedCatalog: LoadedVocabularyCatalog?

    init(
        store: VocabularyCatalogStore,
        legacyVocabularyData: Data?,
        legacyLocalCorrectionsData: Data?,
        now: @escaping () -> Date = { Date() },
        makeID: @escaping () -> UUID = { UUID() }
    ) {
        self.store = store
        self.legacyVocabularyData = legacyVocabularyData
        self.legacyLocalCorrectionsData = legacyLocalCorrectionsData
        self.now = now
        self.makeID = makeID
    }

    @discardableResult
    func activate() throws -> LoadedVocabularyCatalog {
        let loaded = try store.loadOrMigrate(
            legacyVocabularyData: legacyVocabularyData,
            legacyLocalCorrectionsData: legacyLocalCorrectionsData
        )
        loadedCatalog = loaded
        return loaded
    }

    @discardableResult
    func save(
        vocabularyCorrections: [VocabularyCorrection],
        localCorrectionsEnabled: Bool,
        rules: [LocalCorrectionRule]
    ) throws -> LoadedVocabularyCatalog {
        guard let current = loadedCatalog else {
            throw VocabularyCorrectionCoordinatorError.notActivated
        }
        let loaded = try store.save(
            vocabularyCorrections: vocabularyCorrections,
            localCorrectionsEnabled: localCorrectionsEnabled,
            rules: rules,
            appliedProposalReceipts: current.snapshot.appliedProposalReceipts,
            expectedSnapshot: current.snapshot,
            legacyVocabularyData: legacyVocabularyData,
            legacyLocalCorrectionsData: legacyLocalCorrectionsData
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
                    caseSensitive: proposed.caseSensitive
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
            legacyLocalCorrectionsData: legacyLocalCorrectionsData
        )
        loadedCatalog = loaded
        return (loaded, receipt, false)
    }
}

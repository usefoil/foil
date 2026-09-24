import CryptoKit
import Foundation

enum VocabularyProposalServiceError: Error, Equatable {
    case invalidRequestID
    case invalidScope
    case validation(code: String, message: String)
    case requestConflict
    case queueFull
    case notFound
    case unavailable
}

final class VocabularyProposalService: @unchecked Sendable {
    private let store: VocabularyProposalStore
    private let readModelStore: AgentAccessReadModelStore
    private let limits: AgentAccessLimits
    private let didChange: @Sendable () -> Void

    init(
        store: VocabularyProposalStore,
        readModelStore: AgentAccessReadModelStore,
        limits: AgentAccessLimits,
        didChange: @escaping @Sendable () -> Void = {}
    ) {
        self.store = store
        self.readModelStore = readModelStore
        self.limits = limits
        self.didChange = didChange
    }

    func submit(_ request: VocabularyProposalRequest) throws -> VocabularyProposalSubmission {
        let model = readModelStore.snapshot()
        let validated = try validate(request, against: model)
        do {
            let result = try store.submit(validated, snapshotToken: try snapshotToken(for: model))
            if !result.wasReplay { didChange() }
            return result
        } catch VocabularyProposalStoreError.requestIDConflict {
            throw VocabularyProposalServiceError.requestConflict
        } catch VocabularyProposalStoreError.queueFull {
            throw VocabularyProposalServiceError.queueFull
        } catch {
            throw VocabularyProposalServiceError.unavailable
        }
    }

    func status(id: String) throws -> VocabularyProposalReceipt {
        do {
            guard let proposal = try store.proposal(id: id) else {
                throw VocabularyProposalServiceError.notFound
            }
            return proposal.receipt()
        } catch let error as VocabularyProposalServiceError {
            throw error
        } catch {
            throw VocabularyProposalServiceError.unavailable
        }
    }

    func snapshot() throws -> VocabularyProposalSnapshot {
        do {
            return try store.load()
        } catch {
            throw VocabularyProposalServiceError.unavailable
        }
    }

    @discardableResult
    func revise(
        id: String,
        scope: VocabularyProposalScope,
        corrections: [VocabularyProposalCorrection]
    ) throws -> VocabularyProposal {
        let existing = try status(id: id)
        let request = VocabularyProposalRequest(
            requestID: existing.requestID,
            scope: scope,
            corrections: corrections
        )
        let validated = try validate(request, against: readModelStore.snapshot())
        do {
            let proposal = try store.revise(
                id: id,
                scope: validated.scope,
                corrections: validated.corrections
            )
            didChange()
            return proposal
        } catch VocabularyProposalStoreError.proposalNotFound {
            throw VocabularyProposalServiceError.notFound
        } catch {
            throw VocabularyProposalServiceError.unavailable
        }
    }

    @discardableResult
    func transition(id: String, to state: AgentAccessProposalState) throws -> VocabularyProposalReceipt {
        do {
            let receipt = try store.transition(id: id, to: state)
            didChange()
            return receipt
        } catch VocabularyProposalStoreError.proposalNotFound {
            throw VocabularyProposalServiceError.notFound
        } catch {
            throw VocabularyProposalServiceError.unavailable
        }
    }

    func preview(for proposal: VocabularyProposal, requestID: String = "review") -> AgentAccessPreviewResponse {
        let request = VocabularyProposalRequest(
            requestID: proposal.requestID,
            scope: proposal.scope,
            corrections: proposal.corrections
        )
        let model = readModelStore.snapshot()
        let base = preview(request: request, requestID: requestID, model: model)
        do {
            _ = try validate(request, against: model)
            return base
        } catch let VocabularyProposalServiceError.validation(code, message) {
            guard !base.issues.contains(where: { $0.code == code && $0.message == message }) else {
                return base
            }
            return AgentAccessPreviewResponse(
                requestID: requestID,
                valid: false,
                issues: base.issues + [.init(code: code, message: message, correctionIndex: nil)],
                normalizedCorrections: base.normalizedCorrections,
                examples: []
            )
        } catch VocabularyProposalServiceError.invalidScope {
            return AgentAccessPreviewResponse(
                requestID: requestID,
                valid: false,
                issues: base.issues + [.init(
                    code: "invalid_scope",
                    message: "The requested scope is no longer available.",
                    correctionIndex: nil
                )],
                normalizedCorrections: base.normalizedCorrections,
                examples: []
            )
        } catch {
            return base
        }
    }

    func currentSnapshotToken() throws -> String {
        try snapshotToken(for: readModelStore.snapshot())
    }

    func validateForApply(_ proposal: VocabularyProposal) throws -> String {
        let model = readModelStore.snapshot()
        _ = try validate(
            VocabularyProposalRequest(
                requestID: proposal.requestID,
                scope: proposal.scope,
                corrections: proposal.corrections
            ),
            against: model
        )
        return try snapshotToken(for: model)
    }

    private func validate(
        _ rawRequest: VocabularyProposalRequest,
        against model: AgentAccessVocabularyReadModel
    ) throws -> VocabularyProposalRequest {
        let request = rawRequest.canonicalized()
        guard request.schemaVersion == VocabularyProposalContract.schemaVersion else {
            throw VocabularyProposalServiceError.validation(
                code: "unsupported_schema_version",
                message: "Use proposal schema version \(VocabularyProposalContract.schemaVersion)."
            )
        }
        guard isValidRequestID(request.requestID) else {
            throw VocabularyProposalServiceError.invalidRequestID
        }

        let scopeID = try validatedScopeID(request.scope, scopes: model.scopes)
        for correction in request.corrections {
            if let note = correction.note,
               note.unicodeScalars.count > limits.maximumPhraseScalars {
                throw VocabularyProposalServiceError.validation(
                    code: "note_too_long",
                    message: "Notes may contain at most \(limits.maximumPhraseScalars) Unicode scalars."
                )
            }
        }
        let result = preview(request: request, requestID: request.requestID, model: model)
        if let issue = result.issues.first {
            throw VocabularyProposalServiceError.validation(code: issue.code, message: issue.message)
        }

        let existingRules = model.corrections.compactMap { correction -> LocalCorrectionRule? in
            guard let rule = correction.localRule, rule.enabled else { return nil }
            return LocalCorrectionRule(
                id: "existing-\(correction.id)",
                source: correction.writtenAs,
                replacement: correction.correctVersion,
                group: rule.scopeID,
                enabled: true,
                caseSensitive: rule.caseSensitive
            )
        }
        let candidateRules = request.corrections.enumerated().flatMap { correctionIndex, correction in
            correction.spokenForms.enumerated().map { formIndex, form in
                LocalCorrectionRule(
                    id: "proposal-\(correctionIndex)-\(formIndex)",
                    source: form,
                    replacement: correction.replacement,
                    group: scopeID,
                    enabled: true,
                    caseSensitive: correction.caseSensitive
                )
            }
        }
        do {
            _ = try LocalCorrectionEngine.compile(existingRules + candidateRules)
        } catch let error as LocalCorrectionValidationError {
            throw VocabularyProposalServiceError.validation(
                code: "correction_conflict",
                message: error.description
            )
        } catch {
            throw VocabularyProposalServiceError.validation(
                code: "correction_invalid",
                message: "The proposed corrections could not be compiled."
            )
        }
        return request
    }

    private func preview(
        request: VocabularyProposalRequest,
        requestID: String,
        model: AgentAccessVocabularyReadModel
    ) -> AgentAccessPreviewResponse {
        let scopeID = request.scope.kind == "global" ? nil : request.scope.id
        return AgentAccessPreviewEvaluator(limits: limits).evaluate(
            AgentAccessPreviewRequest(corrections: request.corrections.map {
                AgentAccessPreviewCorrection(
                    spokenForms: $0.spokenForms,
                    replacement: $0.replacement,
                    scopeID: scopeID,
                    caseSensitive: $0.caseSensitive
                )
            }),
            requestID: requestID,
            scopes: model.scopes
        )
    }

    private func validatedScopeID(
        _ scope: VocabularyProposalScope,
        scopes: [AgentAccessVocabularyScope]
    ) throws -> String? {
        switch scope.kind {
        case "global":
            guard scope.id == "global" else { throw VocabularyProposalServiceError.invalidScope }
            return nil
        case "cleanup_group":
            guard let match = scopes.first(where: { $0.id == scope.id }), match.isEnabled else {
                throw VocabularyProposalServiceError.invalidScope
            }
            return match.id
        default:
            throw VocabularyProposalServiceError.invalidScope
        }
    }

    private func snapshotToken(for model: AgentAccessVocabularyReadModel) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(model)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func isValidRequestID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        return value.utf8.allSatisfy { $0 >= 0x21 && $0 <= 0x7e }
    }
}

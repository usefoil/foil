import Foundation

protocol AgentAccessServing: AnyObject {
    func start() throws
    func stop()
}

extension AgentAccessServer: AgentAccessServing {}

final class AgentAccessReadModelStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value = AgentAccessVocabularyReadModel(
        scopes: [], terms: [], corrections: [], localCorrectionsEnabled: false
    )

    func update(_ value: AgentAccessVocabularyReadModel) {
        lock.withLock { self.value = value }
    }

    func snapshot() -> AgentAccessVocabularyReadModel {
        lock.withLock { value }
    }
}

final class AgentAccessProposalGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var activeGeneration: UUID?
    private var inFlightCount = 0

    func activate(_ generation: UUID) {
        condition.lock()
        activeGeneration = generation
        condition.unlock()
    }

    func deactivateAndWait() {
        condition.lock()
        activeGeneration = nil
        while inFlightCount > 0 {
            condition.wait()
        }
        condition.unlock()
    }

    func withPermit<T>(
        _ generation: UUID,
        operation: () throws -> T
    ) rethrows -> T? {
        condition.lock()
        guard activeGeneration == generation else {
            condition.unlock()
            return nil
        }
        inFlightCount += 1
        condition.unlock()

        defer {
            condition.lock()
            inFlightCount -= 1
            if inFlightCount == 0 {
                condition.broadcast()
            }
            condition.unlock()
        }
        return try operation()
    }
}

@MainActor
final class AgentAccessController {
    typealias ServerFactory = (
        AgentAccessPaths,
        AgentAccessLimits,
        @escaping AgentAccessServer.Handler
    ) -> AgentAccessServing

    private let appState: AppState
    private let paths: AgentAccessPaths
    private let limits: AgentAccessLimits
    private let openAPIDocument: Data
    private let serverFactory: ServerFactory
    private let startupDelayNanoseconds: UInt64
    private let readModelStore = AgentAccessReadModelStore()
    private let proposalGate = AgentAccessProposalGate()
    private let proposalStore: VocabularyProposalStore
    private var proposalService: VocabularyProposalService!
    private var server: AgentAccessServing?
    private var startupTask: Task<Void, Never>?
    private var lifecycleGeneration = UUID()

    init(
        appState: AppState,
        paths: AgentAccessPaths,
        limits: AgentAccessLimits = .standard,
        openAPIDocument: Data,
        proposalStore: VocabularyProposalStore? = nil,
        startupDelayNanoseconds: UInt64 = 0,
        serverFactory: @escaping ServerFactory = { paths, limits, handler in
            AgentAccessServer(paths: paths, limits: limits, handler: handler)
        }
    ) {
        self.appState = appState
        self.paths = paths
        self.limits = limits
        self.openAPIDocument = openAPIDocument
        self.proposalStore = proposalStore ?? VocabularyProposalStore(fileURL: paths.proposalStoreURL)
        self.startupDelayNanoseconds = startupDelayNanoseconds
        self.serverFactory = serverFactory
        proposalService = VocabularyProposalService(
            store: self.proposalStore,
            readModelStore: readModelStore,
            limits: limits,
            didChange: { [weak self] in
                Task { @MainActor in self?.refreshProposals() }
            }
        )
        appState.agentAccessBootstrapCommand = AgentAccessInstructionsResponse.bootstrapCommand(
            socketPath: paths.socketURL.path
        )
        appState.agentAccessPreferenceDidChange = { [weak self] enabled in
            self?.setEnabled(enabled)
        }
        appState.agentAccessReadModelDidChange = { [weak self] in
            self?.refreshReadModel()
        }
        appState.agentAccessProposalRevisionDidRequest = { [weak self] id, scope, corrections in
            self?.reviseProposal(id: id, scope: scope, corrections: corrections)
        }
        appState.agentAccessProposalTransitionDidRequest = { [weak self] id, state in
            self?.transitionProposal(id: id, to: state)
        }
        appState.agentAccessProposalApplyDidRequest = { [weak self] id in
            self?.applyProposal(id: id)
        }
        refreshReadModel()
    }

    convenience init(
        appState: AppState,
        paths: AgentAccessPaths,
        startupDelayNanoseconds: UInt64 = 0
    ) throws {
        guard let url = Bundle.main.url(forResource: "AgentAccessOpenAPI", withExtension: "json") else {
            throw AgentAccessControllerError.contractMissing
        }
        try self.init(
            appState: appState,
            paths: paths,
            openAPIDocument: Data(contentsOf: url),
            proposalStore: VocabularyProposalStore(fileURL: paths.proposalStoreURL),
            startupDelayNanoseconds: startupDelayNanoseconds
        )
    }

    func startIfEnabled() {
        guard appState.agentAccessEnabled else {
            appState.agentAccessPresentationState = .off
            return
        }
        start()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard server == nil, startupTask == nil else { return }
        appState.agentAccessPresentationState = .starting
        appState.agentAccessErrorMessage = nil
        refreshReadModel()

        let expectedGeneration = UUID()
        lifecycleGeneration = expectedGeneration
        let delay = startupDelayNanoseconds
        startupTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            } else {
                await Task.yield()
            }
            guard let self else { return }
            guard !Task.isCancelled,
                  self.lifecycleGeneration == expectedGeneration,
                  self.appState.agentAccessEnabled else {
                if self.lifecycleGeneration == expectedGeneration { self.startupTask = nil }
                return
            }
            self.startupTask = nil
            self.finishStart(generation: expectedGeneration)
        }
    }

    private func finishStart(generation expectedGeneration: UUID) {
        let proposalService = proposalService!
        let router = AgentAccessContractRouter(
            socketPath: paths.socketURL.path,
            openAPIDocument: openAPIDocument,
            limits: limits,
            vocabularyProvider: { [readModelStore] in readModelStore.snapshot() },
            proposalSubmitter: { [proposalService, proposalGate] request in
                guard let submission = try proposalGate.withPermit(expectedGeneration, operation: {
                    try proposalService.submit(request)
                }) else {
                    throw VocabularyProposalServiceError.unavailable
                }
                return submission
            },
            proposalStatusProvider: { [proposalService, proposalGate] id in
                guard let receipt = try proposalGate.withPermit(expectedGeneration, operation: {
                    try proposalService.status(id: id)
                }) else {
                    throw VocabularyProposalServiceError.unavailable
                }
                return receipt
            }
        )
        let candidate = serverFactory(paths, limits) { request in
            router.response(to: request)
        }
        do {
            proposalGate.activate(expectedGeneration)
            try candidate.start()
            guard lifecycleGeneration == expectedGeneration, appState.agentAccessEnabled else {
                proposalGate.deactivateAndWait()
                candidate.stop()
                return
            }
            server = candidate
            appState.agentAccessPresentationState = .running
            DiagnosticLog.write("AgentAccess.lifecycle: running")
        } catch {
            proposalGate.deactivateAndWait()
            candidate.stop()
            server = nil
            guard lifecycleGeneration == expectedGeneration else { return }
            appState.setAgentAccessEnabled(false, notifyController: false)
            appState.agentAccessPresentationState = .error
            appState.agentAccessErrorMessage = error.localizedDescription
            DiagnosticLog.write("AgentAccess.lifecycle: startup_failed")
        }
    }

    func stop() {
        proposalGate.deactivateAndWait()
        lifecycleGeneration = UUID()
        startupTask?.cancel()
        startupTask = nil
        let active = server
        server = nil
        active?.stop()
        appState.agentAccessPresentationState = .off
        appState.agentAccessErrorMessage = nil
        DiagnosticLog.write("AgentAccess.lifecycle: off")
    }

    func refreshReadModel() {
        readModelStore.update(Self.makeReadModel(from: appState))
        refreshProposals()
    }

    func refreshProposals() {
        do {
            try proposalStore.reconcileAppliedReceipts(appState.appliedVocabularyProposalReceipts)
            let snapshot = try proposalService.snapshot()
            let proposals = snapshot.proposals.sorted { $0.createdAt > $1.createdAt }
            appState.agentAccessProposals = proposals
            appState.agentAccessProposalPreviews = Dictionary(uniqueKeysWithValues: proposals.map {
                ($0.id, proposalService.preview(for: $0, requestID: "review-\($0.id)"))
            })
            let currentToken = try proposalService.currentSnapshotToken()
            appState.agentAccessStaleProposalIDs = Set(
                proposals.lazy.filter { $0.snapshotToken != currentToken }.map(\.id)
            )
            appState.agentAccessProposalInboxErrorMessage = nil
        } catch {
            appState.agentAccessProposals = []
            appState.agentAccessProposalPreviews = [:]
            appState.agentAccessStaleProposalIDs = []
            appState.agentAccessProposalInboxErrorMessage = "Foil could not read the proposal inbox. The stored file was left unchanged."
            DiagnosticLog.write("AgentAccess.proposals: load_failed")
        }
    }

    #if DEBUG
    func seedVocabularyProposalForUITesting() {
        let request = VocabularyProposalRequest(
            requestID: "ui-proposal",
            scope: .init(kind: "global", id: "global"),
            corrections: [
                .init(
                    spokenForms: ["super base", "Superbase"],
                    replacement: "Supabase",
                    note: "Project dependency"
                ),
                .init(
                    spokenForms: ["codecs"],
                    replacement: "Codex",
                    note: "Review scope because codecs is also an ordinary word"
                )
            ]
        )
        do {
            _ = try proposalService.submit(request)
            refreshProposals()
        } catch {
            appState.agentAccessProposalInboxErrorMessage =
                "Foil could not seed the proposal inbox for UI testing."
        }
    }
    #endif

    private func reviseProposal(
        id: String,
        scope: VocabularyProposalScope,
        corrections: [VocabularyProposalCorrection]
    ) {
        do {
            _ = try proposalService.revise(id: id, scope: scope, corrections: corrections)
            refreshProposals()
            DiagnosticLog.write("AgentAccess.proposals: revised proposal_id=\(id)")
        } catch let VocabularyProposalServiceError.validation(_, message) {
            appState.agentAccessProposalInboxErrorMessage = message
        } catch {
            appState.agentAccessProposalInboxErrorMessage = "Foil could not save the reviewed proposal."
            DiagnosticLog.write("AgentAccess.proposals: revise_failed proposal_id=\(id)")
        }
    }

    private func transitionProposal(id: String, to state: AgentAccessProposalState) {
        guard state == .rejected || state == .discarded else { return }
        do {
            _ = try proposalService.transition(id: id, to: state)
            refreshProposals()
            DiagnosticLog.write("AgentAccess.proposals: transitioned proposal_id=\(id) state=\(state.rawValue)")
        } catch {
            appState.agentAccessProposalInboxErrorMessage = "Foil could not update the proposal."
            DiagnosticLog.write("AgentAccess.proposals: transition_failed proposal_id=\(id)")
        }
    }

    private func applyProposal(id: String) {
        do {
            guard let proposal = try proposalStore.proposal(id: id) else {
                throw VocabularyProposalServiceError.notFound
            }
            let currentToken = try proposalService.validateForApply(proposal)
            let result = try appState.applyReviewedVocabularyProposal(
                proposal,
                currentSnapshotToken: currentToken
            )
            _ = try proposalStore.markApplied(from: result.receipt)
            refreshReadModel()
            DiagnosticLog.write(
                "AgentAccess.proposals: applied proposal_id=\(id) replay=\(result.wasReplay) items=\(result.receipt.items.count)"
            )
        } catch VocabularyCorrectionCoordinatorError.staleProposal {
            refreshProposals()
            appState.agentAccessProposalInboxErrorMessage =
                "Vocabulary changed after this proposal arrived. Review a fresh proposal before applying."
        } catch let VocabularyProposalServiceError.validation(_, message) {
            appState.agentAccessProposalInboxErrorMessage = message
        } catch {
            // A catalog receipt is durable before inbox reconciliation. A later
            // refresh or relaunch retries the inert proposal-state update.
            do {
                try proposalStore.reconcileAppliedReceipts(appState.appliedVocabularyProposalReceipts)
            } catch {}
            refreshProposals()
            if appState.agentAccessProposalInboxErrorMessage == nil {
                appState.agentAccessProposalInboxErrorMessage =
                    "Foil could not apply this proposal. The previous catalog is still active."
            }
            DiagnosticLog.write("AgentAccess.proposals: apply_failed proposal_id=\(id)")
        }
    }

    static func makeReadModel(from appState: AppState) -> AgentAccessVocabularyReadModel {
        let rules = Dictionary(uniqueKeysWithValues: appState.localCorrectionSnapshot.rules.map { ($0.id, $0) })
        return AgentAccessVocabularyReadModel(
            scopes: appState.cleanupGroups.map {
                AgentAccessVocabularyScope(
                    id: $0.id,
                    name: $0.name,
                    isDefault: $0.isDefault,
                    isEnabled: $0.isEnabled
                )
            },
            terms: appState.vocabularyTerms.map {
                AgentAccessVocabularyTerm(id: $0.id.uuidString.lowercased(), term: $0.term, note: $0.note)
            },
            corrections: appState.vocabularyCorrections.map { correction in
                let rule = rules["vocabulary:\(correction.id.uuidString.lowercased())"]
                return AgentAccessVocabularyCorrection(
                    id: correction.id.uuidString.lowercased(),
                    writtenAs: correction.writtenAs,
                    correctVersion: correction.correctVersion,
                    note: correction.note,
                    localRule: rule.map {
                        AgentAccessLocalRule(
                            enabled: $0.enabled,
                            caseSensitive: $0.caseSensitive,
                            scopeID: $0.group
                        )
                    }
                )
            },
            localCorrectionsEnabled: appState.localCorrectionSnapshot.isEnabled
        )
    }
}

enum AgentAccessControllerError: Error, LocalizedError {
    case contractMissing

    var errorDescription: String? {
        "Agent Access could not load its API contract. Reinstall Foil and try again."
    }
}

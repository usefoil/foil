import AppKit
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
    private var routingGroups: [CleanupGroup] = []

    func update(_ value: AgentAccessVocabularyReadModel, routingGroups: [CleanupGroup] = []) {
        lock.withLock {
            self.value = value
            self.routingGroups = routingGroups
        }
    }

    func snapshot() -> AgentAccessVocabularyReadModel {
        lock.withLock { value }
    }

    func snapshotWithRoutes() -> (model: AgentAccessVocabularyReadModel, groups: [CleanupGroup]) {
        lock.withLock { (value, routingGroups) }
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

struct AgentAccessAppTarget {
    let path: String
    let displayName: String
    let bundleID: String

    var context: CleanupAppContext {
        CleanupAppContext(displayName: displayName, bundleIdentifier: bundleID, appPath: path)
    }

    var matcher: CleanupAppMatcher {
        // A path matcher distinguishes apps that share a bundle identifier.
        CleanupAppMatcher(displayName: displayName, appPath: path)
    }
}

enum AgentAccessAppTargeting {
    static func resolve(paths: [String]) throws -> [AgentAccessAppTarget] {
        try paths.map { path in
            let url = URL(fileURLWithPath: path)
            guard url.standardizedFileURL.path == path,
                  url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                  let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else {
                throw AgentAccessActionError.validation("The app at \(path) is unavailable. Ask the agent for a new request using the installed app path.")
            }
            let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            guard RunningAppCandidatePolicy.allows(
                displayName: displayName, bundleIdentifier: bundleID, appPath: path
            ) else {
                throw AgentAccessActionError.validation("Foil cannot assign \(path) to a Cleanup Group.")
            }
            return AgentAccessAppTarget(path: path, displayName: displayName, bundleID: bundleID)
        }
    }

    static func hasExactlyThesePaths(_ group: CleanupGroup, paths: [String]) -> Bool {
        group.isEnabled && !group.isDefault && group.appMatchers.count == paths.count &&
            Set(group.appMatchers.compactMap { matcher in
                matcher.bundleIdentifier == nil ? matcher.appPath?.lowercased() : nil
            }) == Set(paths.map { $0.lowercased() })
    }

    static func canResumeCreation(_ group: CleanupGroup, name: String, paths: [String]) -> Bool {
        let expected = Set(paths.map { $0.lowercased() })
        return group.isEnabled && !group.isDefault && group.name == name &&
            group.appMatchers.allSatisfy { matcher in
                matcher.bundleIdentifier == nil &&
                    matcher.appPath.map { expected.contains($0.lowercased()) } == true
            }
    }

    static func pathAssignmentConflict(
        path: String, destinationGroupID: String, groups: [CleanupGroup]
    ) -> CleanupGroup? {
        let key = "path:\(path.lowercased())"
        return groups.first { group in
            group.id != destinationGroupID && group.appMatchers.contains { $0.membershipKey == key }
        }
    }
}

enum AgentAccessTargetInspection {
    static func verify(
        _ request: AgentAccessTargetVerificationRequest,
        requestID: String,
        groups: [CleanupGroup]
    ) throws -> AgentAccessTargetVerificationResponse {
        let paths = request.appPaths
        guard (1...8).contains(paths.count),
              Set(paths.map { $0.lowercased() }).count == paths.count,
              paths.allSatisfy({ path in
                  path.utf8.count <= 1024 && path.hasPrefix("/") &&
                      path == URL(fileURLWithPath: path).standardizedFileURL.path &&
                      !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
              }) else { throw AgentAccessActionError.invalidRequest }
        if let expected = request.expectedGroupID,
           !groups.contains(where: { $0.id == expected && $0.isEnabled }) {
            throw AgentAccessActionError.invalidRequest
        }
        let targets = try AgentAccessAppTargeting.resolve(paths: paths)
        let verified = targets.map { target in
            let group = CleanupGroupResolver.resolve(
                appContext: target.context,
                groups: groups,
                providerFactory: { _ in .none }
            ).group
            return AgentAccessVerifiedTarget(
                appPath: target.path,
                bundleID: target.bundleID,
                displayName: target.displayName,
                resolvedGroupID: group.id,
                resolvedGroupName: group.name,
                exactPathMatch: group.appMatchers.contains { matcher in
                    matcher.bundleIdentifier == nil &&
                        matcher.appPath?.caseInsensitiveCompare(target.path) == .orderedSame
                },
                matchesExpectedGroup: request.expectedGroupID.map { group.id == $0 }
            )
        }
        let expectedGroup = request.expectedGroupID.flatMap { id in groups.first { $0.id == id } }
        return AgentAccessTargetVerificationResponse(
            requestID: requestID,
            targets: verified,
            allMatchExpectedGroup: request.expectedGroupID.map { expected in
                verified.allSatisfy { $0.resolvedGroupID == expected }
            },
            groupExclusiveToRequestedPaths: expectedGroup.map {
                AgentAccessAppTargeting.hasExactlyThesePaths($0, paths: paths)
            }
        )
    }

    static func effectivePreview(
        _ request: AgentAccessEffectivePreviewRequest,
        requestID: String,
        model: AgentAccessVocabularyReadModel,
        groups: [CleanupGroup]
    ) throws -> AgentAccessEffectivePreviewResponse {
        guard request.sampleText.utf8.count <= 16 * 1024 else {
            throw AgentAccessActionError.validation("Sample text exceeds the 16 KiB preview limit.")
        }
        let verification = try verify(
            AgentAccessTargetVerificationRequest(appPaths: [request.appPath], expectedGroupID: nil),
            requestID: requestID,
            groups: groups
        )
        guard let target = verification.targets.first else { throw AgentAccessActionError.invalidRequest }
        let projectedRules = model.corrections.compactMap { correction -> LocalCorrectionRule? in
            guard let local = correction.localRule else { return nil }
            return LocalCorrectionRule(
                id: "vocabulary:\(correction.id)", source: correction.writtenAs,
                replacement: correction.correctVersion, group: local.scopeID,
                enabled: local.enabled, caseSensitive: local.caseSensitive
            )
        } + model.suppressionRules
        let rules = model.catalogRules.isEmpty ? projectedRules : model.catalogRules
        let compiled = try LocalCorrectionEngine.compile(rules)
        let result = LocalCorrectionEngine.correct(
            request.sampleText,
            activeGroup: target.resolvedGroupID,
            enabled: model.localCorrectionsEnabled,
            compiled: compiled
        )
        let effectiveRules = rules.filter {
            $0.enabled && ($0.group == nil || $0.group == target.resolvedGroupID)
        }.map { rule in
            let correctionID: String?
            if rule.id.hasPrefix("suppression:") {
                correctionID = String(rule.id.dropFirst("suppression:".count)
                    .split(separator: ":", maxSplits: 1).first ?? "")
            } else if rule.id.hasPrefix("vocabulary:") {
                correctionID = String(rule.id.dropFirst("vocabulary:".count))
            } else {
                correctionID = nil
            }
            return AgentAccessEffectiveRule(
                ruleID: rule.id,
                correctionID: correctionID,
                source: rule.source,
                replacement: rule.suppressesGlobal ? nil : rule.replacement,
                scopeID: rule.group,
                caseSensitive: rule.caseSensitive,
                suppressesGlobal: rule.suppressesGlobal
            )
        }
        return AgentAccessEffectivePreviewResponse(
            requestID: requestID,
            target: target,
            localCorrectionsEnabled: model.localCorrectionsEnabled,
            outputText: result.text,
            replacementCount: result.replacementCount,
            rules: effectiveRules
        )
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
    private let appURLForBundleID: (String) -> URL?
    private let readModelStore = AgentAccessReadModelStore()
    private let proposalGate = AgentAccessProposalGate()
    private let proposalStore: VocabularyProposalStore
    private let actionStore: AgentAccessActionStore
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
        actionStore: AgentAccessActionStore? = nil,
        startupDelayNanoseconds: UInt64 = 0,
        appURLForBundleID: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        serverFactory: @escaping ServerFactory = { paths, limits, handler in
            AgentAccessServer(paths: paths, limits: limits, handler: handler)
        }
    ) {
        self.appState = appState
        self.paths = paths
        self.limits = limits
        self.openAPIDocument = openAPIDocument
        self.proposalStore = proposalStore ?? VocabularyProposalStore(fileURL: paths.proposalStoreURL)
        self.actionStore = actionStore ?? AgentAccessActionStore(fileURL: paths.actionStoreURL)
        self.startupDelayNanoseconds = startupDelayNanoseconds
        self.appURLForBundleID = appURLForBundleID
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
        appState.agentAccessActionDecisionDidRequest = { [weak self] id, approve in
            self?.decideAction(id: id, approve: approve)
        }
        refreshReadModel()
        refreshActions()
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
            actionStore: AgentAccessActionStore(fileURL: paths.actionStoreURL),
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
            },
            actionSubmitter: { [actionStore, proposalStore, proposalGate, readModelStore] request in
                guard let result = try proposalGate.withPermit(expectedGeneration, operation: {
                    let validatedRequest = try request.validated()
                    // The original receipt is durable even if its proposal or
                    // target group has since changed. Replay before live checks.
                    if try actionStore.load().records.contains(where: {
                        $0.request.requestID == validatedRequest.requestID
                    }) {
                        return try actionStore.submit(validatedRequest)
                    }
                    let proposal = (validatedRequest.action == .applyProposal
                        || validatedRequest.action == .rescopeProposal)
                        ? try proposalStore.proposal(id: validatedRequest.proposalID ?? "")
                        : nil
                    let batchPlan: AgentAccessPolicyBatchPlanner.Plan?
                    if validatedRequest.action == .setCorrectionPolicies {
                        let snapshot = readModelStore.snapshotWithRoutes()
                        batchPlan = try AgentAccessPolicyBatchPlanner.plan(
                            validatedRequest, model: snapshot.model, groups: snapshot.groups
                        )
                    } else {
                        batchPlan = nil
                    }
                    let resultDigest: String?
                    if validatedRequest.action == .rescopeProposal,
                       let proposal, let groupID = validatedRequest.groupID {
                        let groupIsAvailable = readModelStore.snapshot().scopes.contains {
                            $0.id == groupID && $0.isEnabled && !$0.isDefault
                        }
                        guard groupIsAvailable else { throw AgentAccessActionError.invalidRequest }
                        resultDigest = try VocabularyProposalRequest(
                            requestID: proposal.requestID,
                            scope: .init(kind: "cleanup_group", id: groupID),
                            corrections: proposal.corrections
                        ).canonicalPayloadDigest()
                    } else {
                        resultDigest = batchPlan?.resultDigest
                    }
                    return try actionStore.submit(
                        validatedRequest,
                        targetDigest: batchPlan?.targetDigest ?? proposal?.reviewHash ?? proposal?.requestHash,
                        resultDigest: resultDigest,
                        targetAvailable: proposal == nil
                            ? validatedRequest.action != .applyProposal && validatedRequest.action != .rescopeProposal
                            : proposal?.state == .pending
                    )
                }) else { throw AgentAccessActionError.unavailable }
                if !result.1 {
                    Task { @MainActor [weak self] in self?.refreshActions() }
                }
                return result
            },
            actionStatusProvider: { [actionStore, proposalGate] id in
                guard let record = try proposalGate.withPermit(expectedGeneration, operation: {
                    guard let record = try actionStore.load().records.first(where: { $0.id == id }) else {
                        throw AgentAccessActionError.notFound
                    }
                    return record
                }) else { throw AgentAccessActionError.unavailable }
                return record
            },
            targetVerifier: { [readModelStore] request, requestID in
                let snapshot = readModelStore.snapshotWithRoutes()
                return try AgentAccessTargetInspection.verify(
                    request, requestID: requestID, groups: snapshot.groups
                )
            },
            effectivePreviewer: { [readModelStore] request, requestID in
                let snapshot = readModelStore.snapshotWithRoutes()
                return try AgentAccessTargetInspection.effectivePreview(
                    request, requestID: requestID, model: snapshot.model, groups: snapshot.groups
                )
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
        readModelStore.update(
            Self.makeReadModel(from: appState), routingGroups: appState.cleanupGroups
        )
        refreshProposals()
        refreshActions()
    }

    func refreshActions() {
        do {
            appState.agentAccessActions = try actionStore.load().records.sorted { $0.createdAt > $1.createdAt }
            appState.agentAccessActionErrorMessage = nil
        } catch {
            appState.agentAccessActionErrorMessage = "Foil could not read the action inbox. No action was approved."
            DiagnosticLog.write("AgentAccess.actions: load_failed")
        }
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
    func seedAgentActionForUITesting() {
        do {
            _ = try actionStore.submit(.init(
                requestID: "ui-action-\(UUID().uuidString)",
                action: .setLocalCorrectionsEnabled,
                enabled: true
            ))
            refreshActions()
        } catch {
            appState.agentAccessActionErrorMessage = "Foil could not seed the action inbox for UI testing."
        }
    }

    func seedVocabularyProposalForUITesting() {
        let request = VocabularyProposalRequest(
            requestID: "ui-proposal-\(UUID().uuidString)",
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

    @discardableResult
    private func applyProposal(id: String) -> Bool {
        do {
            let pendingScopeChange = try actionStore.load().records.contains {
                $0.request.action == .rescopeProposal && $0.request.proposalID == id &&
                    ($0.state == .pending || $0.state == .approvedPendingApply)
            }
            guard !pendingScopeChange else {
                appState.agentAccessProposalInboxErrorMessage =
                    "A scope change is awaiting review. Approve or reject it before applying this proposal."
                return false
            }
        } catch {
            appState.agentAccessProposalInboxErrorMessage =
                "Foil could not read pending action requests. Resolve that error before applying this proposal."
            return false
        }
        do {
            guard let proposal = try proposalStore.proposal(id: id) else {
                throw VocabularyProposalServiceError.notFound
            }
            let priorReceipt = appState.appliedVocabularyProposalReceipts.first {
                $0.proposalID == proposal.id || $0.requestID == proposal.requestID
            }
            // The catalog receipt is durable before the inbox and action audit
            // finish updating. Replay it before validating the now-active alias.
            let currentToken = priorReceipt == nil
                ? try proposalService.validateForApply(proposal)
                : proposal.snapshotToken
            let result = try appState.applyReviewedVocabularyProposal(
                proposal.revalidated(at: currentToken),
                currentSnapshotToken: currentToken
            )
            _ = try proposalStore.markApplied(from: result.receipt)
            refreshReadModel()
            DiagnosticLog.write(
                "AgentAccess.proposals: applied proposal_id=\(id) replay=\(result.wasReplay) items=\(result.receipt.items.count)"
            )
            return true
        } catch VocabularyCorrectionCoordinatorError.staleProposal {
            refreshProposals()
            appState.agentAccessProposalInboxErrorMessage =
                "Vocabulary changed while this proposal was being applied. Review it again."
            return false
        } catch let VocabularyProposalServiceError.validation(_, message) {
            appState.agentAccessProposalInboxErrorMessage = message
            return false
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
            return false
        }
    }

    private func decideAction(id: String, approve: Bool) {
        do {
            guard let record = try actionStore.load().records.first(where: { $0.id == id }) else {
                throw AgentAccessActionError.notFound
            }
            guard record.state == .pending || record.state == .approvedPendingApply else {
                throw AgentAccessActionError.invalidState
            }
            if approve {
                if record.state == .pending {
                    _ = try actionStore.transition(id: id, to: .approvedPendingApply)
                }
                try performApprovedAction(record)
            }
            let finalState: AgentAccessActionState = approve
                ? .approved
                : (record.state == .approvedPendingApply ? .cancelledAfterApproval : .rejected)
            _ = try actionStore.transition(id: id, to: finalState)
            refreshReadModel()
            DiagnosticLog.write("AgentAccess.actions: decided action_id=\(id) state=\(finalState.rawValue)")
        } catch {
            refreshActions()
            appState.agentAccessActionErrorMessage = error.localizedDescription
            DiagnosticLog.write("AgentAccess.actions: decision_failed action_id=\(id)")
        }
    }

    private func performApprovedAction(_ record: AgentAccessActionRecord) throws {
        let request = record.request
        switch request.action {
        case .applyProposal:
            guard let id = request.proposalID,
                  let proposal = try proposalStore.proposal(id: id) else {
                throw AgentAccessActionError.invalidState
            }
            guard (proposal.reviewHash ?? proposal.requestHash) == record.targetDigest else {
                throw AgentAccessActionError.targetChanged
            }
            guard applyProposal(id: id) else { throw AgentAccessActionError.invalidState }
        case .createCleanupGroup:
            try createApprovedCleanupGroup(record)
        case .rescopeProposal:
            try rescopeApprovedProposal(record)
        case .setLocalCorrectionsEnabled:
            guard let enabled = request.enabled else { throw AgentAccessActionError.invalidRequest }
            if appState.localCorrectionSnapshot.isEnabled != enabled {
                _ = try appState.setLocalCorrectionsEnabled(enabled)
            }
        case .setCorrectionScope:
            guard let rawID = request.correctionID, let id = UUID(uuidString: rawID),
                  let rawScope = request.scopeID else { throw AgentAccessActionError.invalidRequest }
            let groupID: String? = rawScope == "global" ? nil : rawScope
            if let existing = appState.localCorrectionRule(forVocabularyCorrectionID: id),
               existing.group == groupID { return }
            guard let result = try appState.setVocabularyCorrectionLocalScope(
                id: id, groupID: groupID, preserveEnabled: true
            ) else {
                throw AgentAccessActionError.invalidRequest
            }
            _ = result
        case .setCorrectionPolicies:
            let model = Self.makeReadModel(from: appState)
            let groups = appState.cleanupGroups
            let currentDigest = try AgentAccessPolicyBatchPlanner.digest(model: model, groups: groups)
            if currentDigest == record.resultDigest { return }
            guard currentDigest == record.targetDigest else { throw AgentAccessActionError.targetChanged }
            let plan = try AgentAccessPolicyBatchPlanner.plan(request, model: model, groups: groups)
            guard plan.targetDigest == record.targetDigest,
                  plan.resultDigest == record.resultDigest else {
                throw AgentAccessActionError.targetChanged
            }
            _ = try appState.saveLocalCorrections(plan.rules, isEnabled: plan.localCorrectionsEnabled)
            let appliedDigest = try AgentAccessPolicyBatchPlanner.digest(
                model: Self.makeReadModel(from: appState), groups: appState.cleanupGroups
            )
            guard appliedDigest == record.resultDigest else { throw AgentAccessActionError.targetChanged }
        case .assignAppToGroup:
            guard let bundleID = request.appBundleID, let groupID = request.groupID,
                  appState.cleanupGroups.contains(where: { $0.id == groupID && $0.isEnabled }),
                  let appURL = appURLForBundleID(bundleID),
                  Bundle(url: appURL)?.bundleIdentifier == bundleID else {
                throw AgentAccessActionError.invalidRequest
            }
            let displayName = (Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
            let matcher = CleanupAppMatcher(displayName: displayName, bundleIdentifier: bundleID, appPath: appURL.path)
            let context = CleanupAppContext(
                displayName: displayName, bundleIdentifier: bundleID, appPath: appURL.path
            )
            let targetHasMatcher = appState.cleanupGroups.first(where: { $0.id == groupID })?.appMatchers.contains {
                $0.bundleIdentifier == bundleID
            } == true
            if !targetHasMatcher || appState.resolveCleanupGroup(for: context).group.id != groupID {
                appState.addAppMatcher(matcher, toCleanupGroupID: groupID)
            }
            guard appState.resolveCleanupGroup(for: context).group.id == groupID else {
                throw AgentAccessActionError.invalidRequest
            }
        }
    }

    private func createApprovedCleanupGroup(_ record: AgentAccessActionRecord) throws {
        guard let name = record.request.groupName,
              let paths = record.request.appPaths else { throw AgentAccessActionError.invalidRequest }
        let targets = try AgentAccessAppTargeting.resolve(paths: paths)
        guard !appState.cleanupGroups.contains(where: {
            $0.id != record.id && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            throw AgentAccessActionError.validation("A Cleanup Group named \(name) already exists. Ask the agent for a different name.")
        }
        guard targets.allSatisfy({ target in
            !appState.cleanupGroups.contains { group in
                group.id != record.id && group.appMatchers.contains { matcher in
                    matcher.bundleIdentifier?.caseInsensitiveCompare(target.bundleID) == .orderedSame
                }
            }
        }) else {
            throw AgentAccessActionError.validation(
                "A stronger existing app match prevents exact routing to \(name). Review app assignments in Cleanup Groups, then retry."
            )
        }
        guard targets.allSatisfy({
            AgentAccessAppTargeting.pathAssignmentConflict(
                path: $0.path, destinationGroupID: record.id, groups: appState.cleanupGroups
            ) == nil
        }) else {
            throw AgentAccessActionError.validation(
                "An app path is already assigned to another Cleanup Group. Remove that assignment in Settings, then retry."
            )
        }
        if let existing = appState.cleanupGroups.first(where: { $0.id == record.id }) {
            guard AgentAccessAppTargeting.canResumeCreation(existing, name: name, paths: paths) else {
                throw AgentAccessActionError.validation("The requested Cleanup Group changed. Review it in Settings before retrying.")
            }
        } else {
            _ = appState.createCleanupGroup(named: name, id: record.id)
        }
        for target in targets {
            let alreadyMatched = appState.cleanupGroups.first(where: { $0.id == record.id })?.appMatchers.contains {
                $0.bundleIdentifier == nil && $0.appPath?.caseInsensitiveCompare(target.path) == .orderedSame
            } == true
            if !alreadyMatched {
                appState.addAppMatcher(target.matcher, toCleanupGroupID: record.id)
            }
        }
        guard let group = appState.cleanupGroups.first(where: { $0.id == record.id }),
              AgentAccessAppTargeting.hasExactlyThesePaths(group, paths: paths),
              targets.allSatisfy({ appState.resolveCleanupGroup(for: $0.context).group.id == record.id }) else {
            throw AgentAccessActionError.validation(
                "A stronger existing app match prevents exact routing to \(name). Review app assignments in Cleanup Groups, then retry."
            )
        }
    }

    private func rescopeApprovedProposal(_ record: AgentAccessActionRecord) throws {
        guard let proposalID = record.request.proposalID,
              let groupID = record.request.groupID,
              let paths = record.request.appPaths,
              let proposal = try proposalStore.proposal(id: proposalID) else {
            throw AgentAccessActionError.invalidRequest
        }
        let currentDigest = proposal.reviewHash ?? proposal.requestHash
        let requestedScope = VocabularyProposalScope(kind: "cleanup_group", id: groupID)
        let isCompletedRevision = proposal.scope == requestedScope && currentDigest == record.resultDigest
        guard proposal.state == .pending,
              isCompletedRevision || currentDigest == record.targetDigest else {
            throw AgentAccessActionError.targetChanged
        }
        guard let group = appState.cleanupGroups.first(where: { $0.id == groupID }),
              AgentAccessAppTargeting.hasExactlyThesePaths(group, paths: paths) else {
            throw AgentAccessActionError.validation(
                "The target Cleanup Group no longer contains exactly the requested apps. Review its app assignments before retrying."
            )
        }
        let targets = try AgentAccessAppTargeting.resolve(paths: paths)
        guard targets.allSatisfy({ appState.resolveCleanupGroup(for: $0.context).group.id == groupID }) else {
            throw AgentAccessActionError.validation(
                "One of the requested apps currently routes to another Cleanup Group. Review app assignments before retrying."
            )
        }
        if isCompletedRevision {
            return // A prior approval saved the revision before the audit finalized.
        }
        do {
            let revised = try proposalService.revise(
                id: proposalID, scope: requestedScope, corrections: proposal.corrections
            )
            guard revised.reviewHash == record.resultDigest else {
                throw AgentAccessActionError.targetChanged
            }
            refreshProposals()
        } catch let VocabularyProposalServiceError.validation(_, message) {
            throw AgentAccessActionError.validation(message)
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
            localCorrectionsEnabled: appState.localCorrectionSnapshot.isEnabled,
            suppressionRules: appState.localCorrectionSnapshot.rules.filter(\.suppressesGlobal),
            catalogRules: appState.localCorrectionSnapshot.rules
        )
    }
}

enum AgentAccessControllerError: Error, LocalizedError {
    case contractMissing

    var errorDescription: String? {
        "Agent Access could not load its API contract. Reinstall Foil and try again."
    }
}

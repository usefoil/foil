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
    private var server: AgentAccessServing?
    private var startupTask: Task<Void, Never>?
    private var lifecycleGeneration = UUID()

    init(
        appState: AppState,
        paths: AgentAccessPaths,
        limits: AgentAccessLimits = .standard,
        openAPIDocument: Data,
        startupDelayNanoseconds: UInt64 = 0,
        serverFactory: @escaping ServerFactory = { paths, limits, handler in
            AgentAccessServer(paths: paths, limits: limits, handler: handler)
        }
    ) {
        self.appState = appState
        self.paths = paths
        self.limits = limits
        self.openAPIDocument = openAPIDocument
        self.startupDelayNanoseconds = startupDelayNanoseconds
        self.serverFactory = serverFactory
        appState.agentAccessBootstrapCommand = AgentAccessInstructionsResponse.bootstrapCommand(
            socketPath: paths.socketURL.path
        )
        appState.agentAccessPreferenceDidChange = { [weak self] enabled in
            self?.setEnabled(enabled)
        }
        appState.agentAccessReadModelDidChange = { [weak self] in
            self?.refreshReadModel()
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
        let router = AgentAccessContractRouter(
            socketPath: paths.socketURL.path,
            openAPIDocument: openAPIDocument,
            limits: limits,
            vocabularyProvider: { [readModelStore] in readModelStore.snapshot() }
        )
        let candidate = serverFactory(paths, limits) { request in
            router.response(to: request)
        }
        do {
            try candidate.start()
            guard lifecycleGeneration == expectedGeneration, appState.agentAccessEnabled else {
                candidate.stop()
                return
            }
            server = candidate
            appState.agentAccessPresentationState = .running
            DiagnosticLog.write("AgentAccess.lifecycle: running")
        } catch {
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

import Foundation
import Observation

@MainActor @Observable
final class ManagedLocalModelCoordinator {
    enum State: Equatable { case idle, recovering, downloading(String, Int64, Int64), verifying(String), starting(String), cancelled, failed(String) }
    private(set) var state: State = .idle
    private(set) var installed: [ManagedLocalModel] = []
    private(set) var selectedID: String?
    private(set) var candidateID: String?
    private(set) var recovery: [String] = []
    let runtime: ManagedLocalRuntime
    let store: ManagedLocalModelStore
    var activeID: String? {
        guard let session = runtime.session, session.isRunning else { return nil }
        return session.model.id
    }
    @ObservationIgnored private var operation: Task<Void, Error>?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var generation = UUID()

    init(runtime: ManagedLocalRuntime, store: ManagedLocalModelStore) {
        self.runtime = runtime; self.store = store
    }
    func refresh() async throws {
        try await perform { _ in try await self.readStore() }
    }

    func restore() async throws {
        try await perform { generation in
            try await self.readStore()
            guard let selected = self.selectedID else { self.state = .idle; return }
            guard let model = self.installed.first(where: { $0.id == selected }) else {
                throw ManagedLocalModelStore.Failure.unavailable
            }
            self.candidateID = selected; self.state = .starting(selected)
            _ = try await self.runtime.start(model: model, beforeCommit: {
                guard self.generation == generation else { throw CancellationError() }
            })
        }
    }

    func installAndSelect(_ id: String) async throws {
        try await perform { generation in
            let entry = try self.store.catalog.model(id)
            try await self.readStore()
            try Task.checkCancellation()
            self.candidateID = id
            let model: ManagedLocalModel
            if let existing = self.installed.first(where: { $0.id == id }) {
                model = existing
            } else {
                self.state = .downloading(id, 0, entry.bytes)
                model = try await self.store.install(id) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == generation else { return }
                        guard case .downloading = self.state else { return }
                        switch progress {
                        case let .downloading(bytes, total): self.state = .downloading(id, bytes, total)
                        case .verifying: self.state = .verifying(id)
                        }
                    }
                }
                self.installed.append(model)
            }
            try Task.checkCancellation()
            guard self.generation == generation else { throw CancellationError() }
            self.state = .starting(id)
            _ = try await self.runtime.start(model: model, beforeCommit: {
                guard self.generation == generation else { throw CancellationError() }
                try self.store.commitSelection(id)
                self.selectedID = id
            })
        }
    }

    func cancel() {
        generation = UUID()
        operation?.cancel()
        runtime.cancelPending()
        candidateID = nil
        state = .cancelled
    }

    func deactivate() {
        cancel()
        runtime.stop()
    }

    #if DEBUG
    /// Presentation-only state injection for deterministic UI coverage. It never
    /// installs, selects, starts, or marks a model ready.
    func configureForUITesting(state: State, selectedID: String? = nil,
                               candidateID: String? = nil, recovery: [String] = []) {
        cancel()
        self.state = state
        self.selectedID = selectedID
        self.candidateID = candidateID
        self.recovery = recovery
    }
    #endif

    func remove(_ id: String) async throws {
        guard operation == nil, !runtime.protectedModelIDs.contains(id), selectedID != id else {
            throw ManagedLocalModelStore.Failure.unavailable
        }
        try await perform { _ in
            try await self.store.remove(id)
            self.installed.removeAll { $0.id == id }
        }
    }

    private func readStore() async throws {
        state = .recovering
        let snapshot = try await store.reconstruct()
        try Task.checkCancellation()
        installed = snapshot.installed; selectedID = snapshot.selectedID; recovery = snapshot.recovery
    }

    private func perform(_ body: @escaping @MainActor (UUID) async throws -> Void) async throws {
        let previous = operation
        cancel()
        let generation = UUID(); self.generation = generation
        let task = Task { @MainActor in
            if let previous { _ = try? await previous.value }
            try Task.checkCancellation()
            guard self.generation == generation else { throw CancellationError() }
            try await body(generation)
        }
        operation = task
        operationID = generation
        defer {
            if operationID == generation { operation = nil; operationID = nil }
        }
        do {
            try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard self.generation == generation else { throw CancellationError() }
            candidateID = nil; state = .idle; operation = nil
        } catch {
            if self.generation == generation {
                candidateID = nil; operation = nil
                state = error is CancellationError ? .cancelled : .failed(error.localizedDescription)
            }
            throw error
        }
    }
}

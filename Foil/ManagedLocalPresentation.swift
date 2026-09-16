import Foundation

enum ManagedLocalPresentation {
    static let serviceAddress = "transcribe.foil.localhost"
    static let temporaryHeadroom: Int64 = 64 * 1024 * 1024

    struct Status: Equatable {
        let title: String
        let detail: String
        let progress: Double?
        let isReady: Bool
        let canRetry: Bool
    }

    static func name(for id: String) -> String {
        switch id {
        case "base.en": "Base English"
        case "base": "Base Multilingual"
        default: id
        }
    }

    static func downloadSize(for model: ManagedLocalModelCatalog.Model) -> String {
        bytes(model.bytes)
    }

    static func installedSize(for model: ManagedLocalModelCatalog.Model) -> String {
        bytes(model.bytes)
    }

    static func temporarySpace(for model: ManagedLocalModelCatalog.Model) -> String {
        bytes(temporaryHeadroom)
    }

    static func requiredSpace(for model: ManagedLocalModelCatalog.Model) -> String {
        bytes(model.bytes + temporaryHeadroom)
    }

    static func status(
        state: ManagedLocalModelCoordinator.State,
        selectedID: String?,
        activeID: String?,
        candidateID: String?,
        recovery: [String]
    ) -> Status {
        status(coordinatorState: state, selectedID: selectedID, activeID: activeID,
               candidateID: candidateID, recovery: recovery, externalError: nil)
    }

    static func status(
        coordinatorState: ManagedLocalModelCoordinator.State?,
        selectedID: String?,
        activeID: String?,
        candidateID: String?,
        recovery: [String],
        externalError: String?
    ) -> Status {
        let operationOwnsPresentation: Bool = switch coordinatorState {
        case .recovering, .downloading, .verifying, .starting, .cancelled: true
        default: false
        }
        if let externalError, !externalError.isEmpty, activeID == nil, !operationOwnsPresentation {
            return Status(title: coordinatorState == nil ? "Local model unavailable" : "Restore local model",
                          detail: externalError, progress: nil, isReady: false,
                          canRetry: coordinatorState != nil)
        }
        guard let state = coordinatorState else {
            return Status(title: "Local model unavailable",
                          detail: "Foil could not create the managed local model coordinator.",
                          progress: nil, isReady: false, canRetry: false)
        }
        switch state {
        case .recovering:
            return Status(title: "Checking installed models", detail: "Verifying the model store…",
                          progress: nil, isReady: false, canRetry: false)
        case let .downloading(id, received, total):
            let progress = total > 0 ? min(max(Double(received) / Double(total), 0), 1) : nil
            return Status(title: "Downloading \(name(for: id))",
                          detail: "\(bytes(received)) of \(bytes(total))", progress: progress,
                          isReady: activeID != nil, canRetry: false)
        case let .verifying(id):
            return Status(title: "Verifying \(name(for: id))",
                          detail: "Checking the complete download before installation.", progress: nil,
                          isReady: activeID != nil, canRetry: false)
        case let .starting(id):
            let detail = candidateActiveDetail(candidateID ?? id, activeID: activeID)
            return Status(title: "Starting \(name(for: id))", detail: detail, progress: nil,
                          isReady: activeID != nil, canRetry: false)
        case let .failed(message):
            let active = activeID.map { " Still active: \(name(for: $0))" } ?? ""
            return Status(title: activeID == nil ? "Local model needs attention" : "Model change failed",
                          detail: message + active, progress: nil, isReady: activeID != nil, canRetry: true)
        case .cancelled:
            return Status(title: "Model operation cancelled",
                          detail: activeID.map { "Still active: \(name(for: $0))" } ?? "No model is active.",
                          progress: nil, isReady: activeID != nil, canRetry: true)
        case .idle:
            if activeID != nil, let activeID {
                let selected = selectedID.map { "Selected: \(name(for: $0)) · " } ?? ""
                return Status(title: "Ready on this Mac",
                              detail: "\(selected)Active: \(name(for: activeID)) · \(serviceAddress)",
                              progress: nil, isReady: true, canRetry: false)
            }
            if let first = recovery.first {
                return Status(title: "Restore local model", detail: first, progress: nil,
                              isReady: false, canRetry: true)
            }
            if let selectedID {
                return Status(title: "Restore \(name(for: selectedID))",
                              detail: "The selected model is installed but no owned session is active.",
                              progress: nil, isReady: false, canRetry: true)
            }
            return Status(title: "Choose a language", detail: "No model has been downloaded.",
                          progress: nil, isReady: false, canRetry: false)
        }
    }

    static func removalReason(
        id: String,
        selectedID: String?,
        activeID: String?,
        candidateID: String?,
        protectedIDs: Set<String>
    ) -> String? {
        if selectedID == id { return "Selected models cannot be removed. Select another model first." }
        if activeID == id || protectedIDs.contains(id) {
            return "Active or in-use models cannot be removed."
        }
        if candidateID == id { return "A model being installed or started cannot be removed." }
        return nil
    }

    private static func candidateActiveDetail(_ candidateID: String, activeID: String?) -> String {
        let candidate = "Candidate: \(name(for: candidateID))"
        guard let activeID else { return candidate }
        return "\(candidate) · Active: \(name(for: activeID))"
    }

    private static func bytes(_ value: Int64) -> String {
        "\((max(value, 0) + 500_000) / 1_000_000) MB"
    }
}

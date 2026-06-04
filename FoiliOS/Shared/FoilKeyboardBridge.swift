import Foundation

enum FoilKeyboardPhase: String, Codable, Equatable {
    case idle
    case handoffRequested
    case listening
    case processing
    case complete

    var displayName: String {
        switch self {
        case .idle:
            "Ready"
        case .handoffRequested:
            "Opening Foil"
        case .listening:
            "Listening"
        case .processing:
            "Processing"
        case .complete:
            "Transcript Ready"
        }
    }
}

struct FoilKeyboardSnapshot: Codable, Equatable {
    var phase: FoilKeyboardPhase
    var transcript: String?
    var message: String
    var updatedAt: Date

    static let initial = FoilKeyboardSnapshot(
        phase: .idle,
        transcript: nil,
        message: "Ready",
        updatedAt: Date()
    )
}

struct FoilKeyboardBridge {
    private let defaultsKey = "foil.keyboard.snapshot.v1"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: FoilIOSConstants.appGroupIdentifier) ?? .standard
    }

    func load() -> FoilKeyboardSnapshot {
        guard let data = defaults.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(FoilKeyboardSnapshot.self, from: data) else {
            return .initial
        }
        return snapshot
    }

    func save(_ snapshot: FoilKeyboardSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    func requestHandoff() {
        save(
            FoilKeyboardSnapshot(
                phase: .handoffRequested,
                transcript: nil,
                message: "Swipe back after Foil opens",
                updatedAt: Date()
            )
        )
    }

    func markListening() {
        save(
            FoilKeyboardSnapshot(
                phase: .listening,
                transcript: nil,
                message: "Listening placeholder",
                updatedAt: Date()
            )
        )
    }

    func completeFakeTranscript() {
        save(
            FoilKeyboardSnapshot(
                phase: .complete,
                transcript: FoilIOSConstants.fakeTranscript,
                message: "Fake transcript ready",
                updatedAt: Date()
            )
        )
    }

    func reset() {
        save(.initial)
    }
}

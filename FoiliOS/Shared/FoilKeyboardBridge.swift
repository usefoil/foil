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

    static var initial: FoilKeyboardSnapshot {
        FoilKeyboardSnapshot(
            phase: .idle,
            transcript: nil,
            message: "Ready",
            updatedAt: Date()
        )
    }
}

struct FoilKeyboardBridge {
    private let defaultsKey = "foil.keyboard.snapshot.v1"
    private let snapshotFileName = "foil-keyboard-snapshot.json"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: FoilIOSConstants.appGroupIdentifier) ?? .standard
    }

    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FoilIOSConstants.appGroupIdentifier)
    }

    private var snapshotFileURL: URL? {
        sharedContainerURL?
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(snapshotFileName)
    }

    private var readableSnapshotFileURLs: [URL] {
        guard let sharedContainerURL else { return [] }
        return [
            sharedContainerURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent(snapshotFileName),
            sharedContainerURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
                .appendingPathComponent(snapshotFileName),
            sharedContainerURL.appendingPathComponent(snapshotFileName)
        ]
    }

    func load() -> FoilKeyboardSnapshot {
        var snapshots: [FoilKeyboardSnapshot] = []

        for url in readableSnapshotFileURLs {
            if let data = try? Data(contentsOf: url),
               let snapshot = try? JSONDecoder().decode(FoilKeyboardSnapshot.self, from: data) {
                snapshots.append(snapshot)
            }
        }

        if let data = defaults.data(forKey: defaultsKey),
           let snapshot = try? JSONDecoder().decode(FoilKeyboardSnapshot.self, from: data) {
            snapshots.append(snapshot)
        }

        return snapshots.max { $0.updatedAt < $1.updatedAt } ?? .initial
    }

    func save(_ snapshot: FoilKeyboardSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let snapshotFileURL {
            try? data.write(to: snapshotFileURL, options: [.atomic])
        }
        defaults.set(data, forKey: defaultsKey)
        defaults.synchronize()
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
        complete(transcript: FoilIOSConstants.fakeTranscript, message: "Fake transcript ready")
    }

    func complete(transcript: String, message: String = "Transcript ready") {
        save(
            FoilKeyboardSnapshot(
                phase: .complete,
                transcript: transcript,
                message: message,
                updatedAt: Date()
            )
        )
    }

    func reset() {
        for url in readableSnapshotFileURLs.dropFirst() {
            try? FileManager.default.removeItem(at: url)
        }
        save(.initial)
    }
}

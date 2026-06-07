import Foundation

enum FoilKeyboardPhase: String, Codable, Equatable {
    case idle
    case handoffRequested
    case listening
    case processing
    case complete
    case failed

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
        case .failed:
            "Needs Attention"
        }
    }
}

struct FoilKeyboardSnapshot: Codable, Equatable {
    var phase: FoilKeyboardPhase
    var transcript: String?
    var message: String
    var updatedAt: Date

    var insertableTranscript: String? {
        guard phase == .complete else { return nil }
        let trimmedTranscript = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedTranscript, !trimmedTranscript.isEmpty else { return nil }
        return trimmedTranscript
    }

    static var initial: FoilKeyboardSnapshot {
        FoilKeyboardSnapshot(
            phase: .idle,
            transcript: nil,
            message: "Ready",
            updatedAt: Date()
        )
    }
}

struct FoilKeyboardStoragePathResult: Codable, Equatable {
    var path: String
    var succeeded: Bool
    var error: String?
}

struct FoilKeyboardStorageReport: Codable, Equatable {
    var operation: String
    var phase: FoilKeyboardPhase
    var hasTranscript: Bool
    var canonicalPath: String?
    var canonicalWriteSucceeded: Bool
    var canonicalWriteError: String?
    var canonicalVerificationPhase: FoilKeyboardPhase?
    var canonicalVerificationHasTranscript: Bool?
    var defaultsWriteAttempted: Bool
    var fallbackRemovalResults: [FoilKeyboardStoragePathResult]
    var updatedAt: Date

    static var initial: FoilKeyboardStorageReport {
        FoilKeyboardStorageReport(
            operation: "none",
            phase: .idle,
            hasTranscript: false,
            canonicalPath: nil,
            canonicalWriteSucceeded: false,
            canonicalWriteError: nil,
            canonicalVerificationPhase: nil,
            canonicalVerificationHasTranscript: nil,
            defaultsWriteAttempted: false,
            fallbackRemovalResults: [],
            updatedAt: Date()
        )
    }
}

enum FoilKeyboardFullAccessState: String, Codable, Equatable {
    case unverified
    case disabled
    case enabled

    var displayName: String {
        switch self {
        case .unverified:
            "Not verified"
        case .disabled:
            "Full Access off"
        case .enabled:
            "Full Access on"
        }
    }
}

struct FoilKeyboardHealthReport: Codable, Equatable {
    var fullAccessState: FoilKeyboardFullAccessState
    var snapshotPhase: FoilKeyboardPhase
    var snapshotHasTranscript: Bool
    var message: String
    var updatedAt: Date

    static var initial: FoilKeyboardHealthReport {
        FoilKeyboardHealthReport(
            fullAccessState: .unverified,
            snapshotPhase: .idle,
            snapshotHasTranscript: false,
            message: "Open Foil Keyboard to verify setup",
            updatedAt: .distantPast
        )
    }
}

enum FoilIOSCommandAction: String, Codable, Equatable {
    case startRecording
    case stopRecording
    case transcribeLatest
    case resetSharedState
    case completeFakeTranscript
}

struct FoilIOSCommand: Codable, Equatable {
    var id: String
    var action: FoilIOSCommandAction
    var updatedAt: Date
}

struct FoilKeyboardBridge {
    private let defaultsKey = "foil.keyboard.snapshot.v1"
    private let reportDefaultsKey = "foil.keyboard.storageReport.v1"
    private let healthDefaultsKey = "foil.keyboard.healthReport.v1"
    private let snapshotFileName = "foil-keyboard-snapshot.json"
    private let commandFileName = "foil-ios-command.json"

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

    private var commandFileURL: URL? {
        sharedContainerURL?
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(commandFileName)
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
        persist(snapshot, operation: "save")
    }

    func storageReport() -> FoilKeyboardStorageReport {
        guard let data = defaults.data(forKey: reportDefaultsKey),
              let report = try? JSONDecoder().decode(FoilKeyboardStorageReport.self, from: data) else {
            return .initial
        }
        return report
    }

    func keyboardHealthReport() -> FoilKeyboardHealthReport {
        guard let data = defaults.data(forKey: healthDefaultsKey),
              let report = try? JSONDecoder().decode(FoilKeyboardHealthReport.self, from: data) else {
            return .initial
        }
        return report
    }

    func loadCommand() -> FoilIOSCommand? {
        guard let commandFileURL,
              let data = try? Data(contentsOf: commandFileURL),
              let command = try? JSONDecoder().decode(FoilIOSCommand.self, from: data) else {
            return nil
        }
        return command
    }

    func clearCommand() {
        guard let commandFileURL else { return }
        try? FileManager.default.removeItem(at: commandFileURL)
    }

    func recordKeyboardHealth(fullAccessEnabled: Bool, snapshot: FoilKeyboardSnapshot) {
        let report = FoilKeyboardHealthReport(
            fullAccessState: fullAccessEnabled ? .enabled : .disabled,
            snapshotPhase: snapshot.phase,
            snapshotHasTranscript: snapshot.transcript?.isEmpty == false,
            message: fullAccessEnabled ? "Foil Keyboard verified" : "Allow Full Access required",
            updatedAt: Date()
        )
        saveKeyboardHealthReport(report)
    }

    private func persist(_ snapshot: FoilKeyboardSnapshot, operation: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let removalResults = removeSnapshotFiles(Array(readableSnapshotFileURLs.dropFirst()))
        let writeResult = writeSnapshotFile(data)
        defaults.set(data, forKey: defaultsKey)
        defaults.synchronize()
        saveStorageReport(
            snapshot: snapshot,
            operation: operation,
            writeResult: writeResult,
            defaultsWriteAttempted: true,
            removalResults: removalResults
        )
    }

    func requestHandoff() {
        save(
            FoilKeyboardSnapshot(
                phase: .handoffRequested,
                transcript: nil,
                message: "Foil is opening. Dictate there, then switch back to insert.",
                updatedAt: Date()
            )
        )
    }

    func markListening() {
        save(
            FoilKeyboardSnapshot(
                phase: .listening,
                transcript: nil,
                message: "Recording in Foil. Stop when finished.",
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

    func fail(message: String) {
        save(
            FoilKeyboardSnapshot(
                phase: .failed,
                transcript: nil,
                message: message,
                updatedAt: Date()
            )
        )
    }

    func consumeTranscriptForInsertion() -> String? {
        let snapshot = load()
        let transcript = snapshot.insertableTranscript
        persist(.initial, operation: "insert")
        let currentHealth = keyboardHealthReport()
        saveKeyboardHealthReport(
            FoilKeyboardHealthReport(
                fullAccessState: currentHealth.fullAccessState,
                snapshotPhase: .idle,
                snapshotHasTranscript: false,
                message: currentHealth.fullAccessState == .enabled ? "Foil Keyboard verified" : currentHealth.message,
                updatedAt: Date()
            )
        )
        return transcript
    }

    func reset() {
        persist(.initial, operation: "reset")
        let currentHealth = keyboardHealthReport()
        saveKeyboardHealthReport(
            FoilKeyboardHealthReport(
                fullAccessState: currentHealth.fullAccessState,
                snapshotPhase: .idle,
                snapshotHasTranscript: false,
                message: currentHealth.fullAccessState == .enabled ? "Foil Keyboard verified" : currentHealth.message,
                updatedAt: Date()
            )
        )
    }

    private func writeSnapshotFile(_ data: Data) -> FoilKeyboardStoragePathResult {
        guard let snapshotFileURL else {
            return FoilKeyboardStoragePathResult(path: "missing app group container", succeeded: false, error: "Missing app group container")
        }

        let path = snapshotFileURL.path
        do {
            try FileManager.default.createDirectory(
                at: snapshotFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return FoilKeyboardStoragePathResult(path: path, succeeded: false, error: error.localizedDescription)
        }

        do {
            try data.write(to: snapshotFileURL, options: [])
            return FoilKeyboardStoragePathResult(path: path, succeeded: true, error: nil)
        } catch {
            guard FileManager.default.fileExists(atPath: snapshotFileURL.path),
                  let handle = try? FileHandle(forWritingTo: snapshotFileURL) else {
                return FoilKeyboardStoragePathResult(path: path, succeeded: false, error: error.localizedDescription)
            }
            handle.truncateFile(atOffset: 0)
            handle.write(data)
            handle.closeFile()
            return FoilKeyboardStoragePathResult(path: path, succeeded: true, error: nil)
        }
    }

    private func removeSnapshotFiles(_ urls: [URL]) -> [FoilKeyboardStoragePathResult] {
        urls.map { url in
            do {
                try FileManager.default.removeItem(at: url)
                return FoilKeyboardStoragePathResult(path: url.path, succeeded: true, error: nil)
            } catch {
                if !FileManager.default.fileExists(atPath: url.path) {
                    return FoilKeyboardStoragePathResult(path: url.path, succeeded: true, error: "Already absent")
                }
                return FoilKeyboardStoragePathResult(path: url.path, succeeded: false, error: error.localizedDescription)
            }
        }
    }

    private func saveStorageReport(
        snapshot: FoilKeyboardSnapshot,
        operation: String,
        writeResult: FoilKeyboardStoragePathResult,
        defaultsWriteAttempted: Bool,
        removalResults: [FoilKeyboardStoragePathResult]
    ) {
        let verifiedSnapshot: FoilKeyboardSnapshot? = snapshotFileURL.flatMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(FoilKeyboardSnapshot.self, from: data)
        }
        let report = FoilKeyboardStorageReport(
            operation: operation,
            phase: snapshot.phase,
            hasTranscript: snapshot.transcript?.isEmpty == false,
            canonicalPath: snapshotFileURL?.path,
            canonicalWriteSucceeded: writeResult.succeeded,
            canonicalWriteError: writeResult.error,
            canonicalVerificationPhase: verifiedSnapshot?.phase,
            canonicalVerificationHasTranscript: verifiedSnapshot?.transcript?.isEmpty == false,
            defaultsWriteAttempted: defaultsWriteAttempted,
            fallbackRemovalResults: removalResults,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(report) else { return }
        defaults.set(data, forKey: reportDefaultsKey)
        defaults.synchronize()
    }

    private func saveKeyboardHealthReport(_ report: FoilKeyboardHealthReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        defaults.set(data, forKey: healthDefaultsKey)
        defaults.synchronize()
    }
}

import Foundation
import Observation

struct TranscriptionRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    var sourceAppName: String?
    var sourceAppBundleIdentifier: String? = nil
    var sourceAppPath: String? = nil
    var sourceRecordID: UUID?
    var transformKind: HistoryTransformKind?
    var outcome: Outcome

    enum Outcome: Codable {
        case success(text: String)
        case failure(error: String, audioFileURL: URL?)
    }

    var text: String? {
        if case .success(let t) = outcome { return t }
        return nil
    }

    var error: String? {
        if case .failure(let e, _) = outcome { return e }
        return nil
    }

    var audioFileURL: URL? {
        if case .failure(_, let url) = outcome { return url }
        return nil
    }

    var isFailure: Bool {
        if case .failure = outcome { return true }
        return false
    }

    var sourceAppContext: CleanupAppContext? {
        let context = CleanupAppContext(
            displayName: sourceAppName,
            bundleIdentifier: sourceAppBundleIdentifier,
            appPath: sourceAppPath
        )
        guard context.displayName != nil || context.bundleIdentifier != nil || context.appPath != nil else {
            return nil
        }
        return context
    }

    var previewText: String {
        let source = text ?? error ?? ""
        if source.count <= 40 { return source }
        return String(source.prefix(40)) + "..."
    }

    var relativeTimestamp: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

@MainActor @Observable
final class TranscriptionHistory {
    nonisolated static let maxRecords = 500

    /// Transcription records, sorted newest-first.
    /// Insertion order is load-bearing for retry logic.
    private(set) var records: [TranscriptionRecord] = []
    /// Kept only until Foil quits or history is cleared, including when disk history is off.
    private(set) var lastSessionTranscript: String?
    /// The provider transcript before local correction and Cleanup. Never written to disk.
    private(set) var lastSessionOriginalTranscript: String?
    private var lastSessionRecordID: UUID?
    var lastRecoverableText: String? {
        if let lastSessionRecordID {
            return records.first { $0.id == lastSessionRecordID }?.text ?? successfulRecords.first?.text
        }
        return lastSessionTranscript ?? successfulRecords.first?.text
    }
    var lastRecoverableOriginalText: String? {
        guard let original = lastSessionOriginalTranscript,
              let final = lastSessionTranscript,
              !original.utf8.elementsEqual(final.utf8) else {
            return nil
        }
        if let lastSessionRecordID {
            guard let currentText = records.first(where: { $0.id == lastSessionRecordID })?.text,
                  currentText.utf8.elementsEqual(final.utf8) else {
                return nil
            }
        }
        return original
    }
    var canClear: Bool {
        !records.isEmpty || lastSessionTranscript != nil || lastSessionOriginalTranscript != nil
    }
    private(set) var preferencesError: String?

    private struct Preferences: Codable {
        var retentionLimit: Int
        var isPersistenceEnabled: Bool
    }

    var retentionLimit: Int {
        didSet {
            savePreferences()
            trimToRetentionLimit()
            save()
        }
    }

    var isPersistenceEnabled: Bool {
        didSet { savePreferences() }
    }

    private let historyFileURL: URL
    private let retryAudioDirectory: URL
    private let preferencesFileURL: URL

    init(
        storageDirectory: URL,
        retentionLimit: Int? = nil,
        isPersistenceEnabled: Bool? = nil
    ) {
        self.historyFileURL = storageDirectory.appendingPathComponent("history.json")
        self.retryAudioDirectory = storageDirectory.appendingPathComponent("retry-audio")
        self.preferencesFileURL = storageDirectory.appendingPathComponent("history-preferences.json")
        var stored: Preferences?
        if FileManager.default.fileExists(atPath: preferencesFileURL.path) {
            do {
                let decoded = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: preferencesFileURL))
                guard decoded.retentionLimit > 0 else { throw CocoaError(.fileReadCorruptFile) }
                stored = decoded
            } catch {
                // Never silently turn history back on when a saved privacy choice cannot be read.
                stored = Preferences(retentionLimit: Self.maxRecords, isPersistenceEnabled: false)
                preferencesError = "History settings could not be read. New history is off. Choose a retention setting to save your preference again."
            }
        }
        self.retentionLimit = retentionLimit ?? stored?.retentionLimit ?? Self.maxRecords
        self.isPersistenceEnabled = isPersistenceEnabled ?? stored?.isPersistenceEnabled ?? true
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        load()
        if retentionLimit != nil || isPersistenceEnabled != nil { savePreferences() }
    }

    private func savePreferences() {
        do {
            let data = try JSONEncoder().encode(Preferences(
                retentionLimit: retentionLimit,
                isPersistenceEnabled: isPersistenceEnabled
            ))
            try data.write(to: preferencesFileURL, options: .atomic)
            preferencesError = nil
        } catch {
            preferencesError = "Could not save history settings. Your choice may not survive restarting Foil. Check available disk space and folder access."
        }
    }

    /// Convenience init using the default Application Support directory.
    convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent(AppBrand.applicationSupportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(storageDirectory: dir)
    }

    func addSuccess(
        text: String,
        originalText: String? = nil,
        sourceAppName: String? = nil
    ) {
        let record = TranscriptionRecord(
            id: UUID(),
            timestamp: Date(),
            sourceAppName: Self.normalizedSourceAppName(sourceAppName),
            outcome: .success(text: text)
        )
        rememberLastSession(
            text: text,
            originalText: originalText,
            recordID: insert(record) ? record.id : nil
        )
    }

    func addTransformResult(
        text: String,
        sourceRecordID: UUID,
        transformKind: HistoryTransformKind,
        sourceAppName: String? = nil
    ) {
        let record = TranscriptionRecord(
            id: UUID(),
            timestamp: Date(),
            sourceAppName: Self.normalizedSourceAppName(sourceAppName),
            sourceRecordID: sourceRecordID,
            transformKind: transformKind,
            outcome: .success(text: text)
        )
        rememberLastSession(text: text, originalText: nil, recordID: insert(record) ? record.id : nil)
    }

    func addFailure(
        error: String,
        audioFileURL: URL?,
        sourceAppName: String? = nil,
        sourceAppBundleIdentifier: String? = nil,
        sourceAppPath: String? = nil
    ) {
        guard isPersistenceEnabled else {
            if let audioFileURL { try? FileManager.default.removeItem(at: audioFileURL) }
            return
        }
        let retainedAudioURL = retainFailedAudio(audioFileURL)
        let record = TranscriptionRecord(
            id: UUID(),
            timestamp: Date(),
            sourceAppName: Self.normalizedSourceAppName(sourceAppName),
            sourceAppBundleIdentifier: Self.normalizedSourceAppName(sourceAppBundleIdentifier),
            sourceAppPath: Self.normalizedSourceAppName(sourceAppPath),
            outcome: .failure(error: error, audioFileURL: retainedAudioURL)
        )
        _ = insert(record)
    }

    func resolveRetry(
        id: UUID,
        text: String,
        originalText: String? = nil,
        sourceAppName: String? = nil
    ) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        // Delete the audio file since retry succeeded
        if let audioURL = records[index].audioFileURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        if let normalizedSourceAppName = Self.normalizedSourceAppName(sourceAppName) {
            records[index].sourceAppName = normalizedSourceAppName
        }
        records[index].outcome = .success(text: text)
        rememberLastSession(text: text, originalText: originalText, recordID: records[index].id)
        save()
    }

    func resolveRetryFailure(id: UUID, error: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let audioURL = records[index].audioFileURL
        records[index].outcome = .failure(error: error, audioFileURL: audioURL)
        save()
    }

    func updateSuccess(id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = records.firstIndex(where: { $0.id == id }),
              !records[index].isFailure else { return }
        records[index].outcome = .success(text: trimmed)
        if lastSessionRecordID == id {
            lastSessionTranscript = trimmed
            lastSessionOriginalTranscript = nil
        }
        save()
    }

    /// Returns the most recent record if it is a failure with a retryable audio file.
    var retryableRecord: TranscriptionRecord? {
        guard let first = records.first,
              first.isFailure,
              let url = first.audioFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return first
    }

    var successfulRecords: [TranscriptionRecord] {
        records.filter { !$0.isFailure }
    }

    func recentSuccessfulRecords(limit: Int) -> [TranscriptionRecord] {
        guard limit > 0 else { return [] }
        return Array(successfulRecords.prefix(limit))
    }

    func recentRecords(limit: Int) -> [TranscriptionRecord] {
        Array(records.prefix(limit))
    }

    func delete(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let removed = records.remove(at: index)
        if lastSessionRecordID == removed.id {
            lastSessionTranscript = nil
            lastSessionRecordID = nil
            lastSessionOriginalTranscript = nil
        }
        if let audioURL = removed.audioFileURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        save()
    }

    func clear() {
        lastSessionTranscript = nil
        lastSessionOriginalTranscript = nil
        lastSessionRecordID = nil
        for record in records {
            if let audioURL = record.audioFileURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        records = []
        save()
    }

    /// Delete all records older than the given date.
    func deleteOlderThan(_ date: Date) {
        let toDelete = records.filter { $0.timestamp < date }
        clearLastSessionRecovery(ifDeleting: Set(toDelete.map(\.id)))
        for record in toDelete {
            if let url = record.audioFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        records.removeAll { $0.timestamp < date }
        save()
    }

    /// Delete all records matching the given IDs.
    func deleteAll(ids: Set<UUID>) {
        clearLastSessionRecovery(ifDeleting: ids)
        for record in records where ids.contains(record.id) {
            if let url = record.audioFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        records.removeAll { ids.contains($0.id) }
        save()
    }

    /// Delete records from a given array (e.g., filtered results).
    func deleteFiltered(_ recordsToDelete: [TranscriptionRecord]) {
        let ids = Set(recordsToDelete.map(\.id))
        deleteAll(ids: ids)
    }

    var retainedFailedAudioCount: Int {
        records.reduce(0) { count, record in
            guard let url = record.audioFileURL,
                  FileManager.default.fileExists(atPath: url.path) else {
                return count
            }
            return count + 1
        }
    }

    func clearRetainedFailedAudio() {
        var updated = false
        for index in records.indices {
            guard case .failure(let error, let audioURL) = records[index].outcome,
                  let audioURL else { continue }
            try? FileManager.default.removeItem(at: audioURL)
            records[index].outcome = .failure(error: error, audioFileURL: nil)
            updated = true
        }
        if updated { save() }
    }

    func exportMarkdown() -> String {
        records.map { record in
            let kind = if record.isFailure {
                "Failure"
            } else if let transformKind = record.transformKind {
                "\(transformKind.displayName) Transform"
            } else {
                "Transcript"
            }
            let body = record.text ?? record.error ?? ""
            return """
            ## \(kind) - \(Self.exportDateFormatter.string(from: record.timestamp))

            \(body)
            """
        }
        .joined(separator: "\n\n")
    }

    func exportJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - Private

    private func rememberLastSession(text: String, originalText: String?, recordID: UUID?) {
        lastSessionTranscript = text
        lastSessionOriginalTranscript = originalText.flatMap { original in
            original.utf8.elementsEqual(text.utf8) ? nil : original
        }
        lastSessionRecordID = recordID
    }

    private func clearLastSessionRecovery(ifDeleting ids: Set<UUID>) {
        guard let lastSessionRecordID, ids.contains(lastSessionRecordID) else { return }
        lastSessionTranscript = nil
        lastSessionOriginalTranscript = nil
        self.lastSessionRecordID = nil
    }

    private func insert(_ record: TranscriptionRecord) -> Bool {
        guard isPersistenceEnabled, effectiveRetentionLimit > 0 else {
            if let audioURL = record.audioFileURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
            return false
        }
        records.insert(record, at: 0)
        trimToRetentionLimit()
        save()
        return true
    }

    private static func normalizedSourceAppName(_ sourceAppName: String?) -> String? {
        let trimmed = sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func trimToRetentionLimit() {
        while records.count > effectiveRetentionLimit {
            let evicted = records.removeLast()
            if let audioURL = evicted.audioFileURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
    }

    private var effectiveRetentionLimit: Int {
        max(0, retentionLimit)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(records)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            print("TranscriptionHistory: failed to save — \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([TranscriptionRecord].self, from: data)
            if isPersistenceEnabled && migrateRetainedAudioIntoStorage() {
                save()
            }
        } catch {
            print("TranscriptionHistory: failed to load — \(error)")
            records = []
        }
    }

    private func retainFailedAudio(_ audioFileURL: URL?) -> URL? {
        guard let audioFileURL else { return nil }
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else { return nil }
        if isRetryAudioURL(audioFileURL) { return audioFileURL }

        try? FileManager.default.createDirectory(at: retryAudioDirectory, withIntermediateDirectories: true)
        let destination = retryAudioDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(audioFileURL.pathExtension.isEmpty ? "audio" : audioFileURL.pathExtension)

        do {
            try FileManager.default.moveItem(at: audioFileURL, to: destination)
            return destination
        } catch {
            do {
                try FileManager.default.copyItem(at: audioFileURL, to: destination)
                try? FileManager.default.removeItem(at: audioFileURL)
                return destination
            } catch {
                print("TranscriptionHistory: failed to retain retry audio — \(error)")
                return audioFileURL
            }
        }
    }

    private func migrateRetainedAudioIntoStorage() -> Bool {
        var didChange = false
        for index in records.indices {
            guard case .failure(let error, let audioURL) = records[index].outcome,
                  let audioURL,
                  !isRetryAudioURL(audioURL),
                  let retainedURL = retainFailedAudio(audioURL) else { continue }
            records[index].outcome = .failure(error: error, audioFileURL: retainedURL)
            didChange = retainedURL != audioURL || didChange
        }
        return didChange
    }

    private func isRetryAudioURL(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(retryAudioDirectory.standardizedFileURL.path + "/")
    }

    private static let exportDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

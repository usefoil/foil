import Foundation

struct TranscriptionRecord: Codable, Identifiable {
    let id: UUID
    var text: String?
    var error: String?
    let timestamp: Date
    var audioFileURL: URL?

    var isFailure: Bool { error != nil }

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

final class TranscriptionHistory {
    private static let maxRecords = 20

    private(set) var records: [TranscriptionRecord] = []  // newest first
    private let historyFileURL: URL

    init(storageDirectory: URL) {
        self.historyFileURL = storageDirectory.appendingPathComponent("history.json")
        load()
    }

    /// Convenience init using the default Application Support directory.
    convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("GroqTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(storageDirectory: dir)
    }

    func addSuccess(text: String) {
        let record = TranscriptionRecord(
            id: UUID(), text: text, error: nil,
            timestamp: Date(), audioFileURL: nil
        )
        insert(record)
    }

    func addFailure(error: String, audioFileURL: URL?) {
        let record = TranscriptionRecord(
            id: UUID(), text: nil, error: error,
            timestamp: Date(), audioFileURL: audioFileURL
        )
        insert(record)
    }

    func resolveRetry(id: UUID, text: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        // Delete the audio file since retry succeeded
        if let audioURL = records[index].audioFileURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        records[index].text = text
        records[index].error = nil
        records[index].audioFileURL = nil
        save()
    }

    func resolveRetryFailure(id: UUID, error: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].error = error
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

    // MARK: - Private

    private func insert(_ record: TranscriptionRecord) {
        records.insert(record, at: 0)
        while records.count > Self.maxRecords {
            let evicted = records.removeLast()
            if let audioURL = evicted.audioFileURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: historyFileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([TranscriptionRecord].self, from: data)) ?? []
    }
}

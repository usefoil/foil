import Foundation

struct UsageEvent: Codable, Equatable, Identifiable {
    enum Outcome: String, Codable {
        case success
        case cleanupFailedFallback
        case failed
    }

    let id: UUID
    let timestamp: Date
    let wordCount: Int
    let sourceAppName: String?
    let sourceBundleIdentifier: String?
    let cleanupGroupID: String?
    let cleanupGroupName: String?
    let processingMode: TranscriptProcessingMode
    let cleanupProviderID: TranscriptCleanupProviderID?
    let cleanupModel: String?
    let cleanupFailed: Bool
    let outcome: Outcome

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        wordCount: Int,
        sourceAppName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        cleanupGroupID: String? = nil,
        cleanupGroupName: String? = nil,
        processingMode: TranscriptProcessingMode,
        cleanupProviderID: TranscriptCleanupProviderID? = nil,
        cleanupModel: String? = nil,
        cleanupFailed: Bool = false,
        outcome: Outcome = .success
    ) {
        self.id = id
        self.timestamp = timestamp
        self.wordCount = max(0, wordCount)
        self.sourceAppName = Self.normalized(sourceAppName)
        self.sourceBundleIdentifier = Self.normalized(sourceBundleIdentifier)
        self.cleanupGroupID = Self.normalized(cleanupGroupID)
        self.cleanupGroupName = Self.normalized(cleanupGroupName)
        self.processingMode = processingMode.normalizedActiveMode
        self.cleanupProviderID = cleanupProviderID
        self.cleanupModel = Self.normalized(cleanupModel)
        self.cleanupFailed = cleanupFailed
        self.outcome = outcome
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum UsageEventStoreError: String, Codable, Equatable {
    case loadFailed
    case saveFailed
    case deleteFailed
}

enum UsageEventMutationResult: Equatable {
    case stored
    case disabled
    case deleted
    case failed(UsageEventStoreError)
}

struct UsageSummary: Equatable {
    let totalWords: Int
    let totalSessions: Int
    let estimatedTimeSavedSeconds: Int
    let rawSessions: Int
    let cleanupSessions: Int
    let cleanupFailureCount: Int
}

struct UsageTrendBucket: Equatable {
    let startDate: Date
    let wordCount: Int
    let sessionCount: Int
}

struct UsageTopApp: Equatable {
    let displayName: String
    let bundleIdentifier: String?
    let wordCount: Int
    let sessionCount: Int
}

final class UsageEventStore {
    static let estimatedTypingWordsPerMinute = 40.0

    private(set) var events: [UsageEvent] = []
    var isEnabled: Bool
    private(set) var lastError: UsageEventStoreError?

    private let fileURL: URL
    private let fileManager: FileManager

    init(
        storageDirectory: URL? = nil,
        isEnabled: Bool = true,
        fileManager: FileManager = .default
    ) {
        let directory = storageDirectory ?? Self.defaultStorageDirectory(fileManager: fileManager)
        self.fileURL = directory.appendingPathComponent("usage-events.json")
        self.isEnabled = isEnabled
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    @discardableResult
    func record(_ event: UsageEvent) -> UsageEventMutationResult {
        guard isEnabled else { return .disabled }
        events.insert(event, at: 0)
        guard save() else {
            events.removeAll { $0.id == event.id }
            return .failed(.saveFailed)
        }
        return .stored
    }

    @discardableResult
    func deleteAll() -> UsageEventMutationResult {
        events = []
        guard fileManager.fileExists(atPath: fileURL.path) else {
            lastError = nil
            return .deleted
        }
        do {
            try fileManager.removeItem(at: fileURL)
            lastError = nil
            return .deleted
        } catch {
            lastError = .deleteFailed
            return .failed(.deleteFailed)
        }
    }

    func summary() -> UsageSummary {
        let totalWords = events.reduce(0) { $0 + $1.wordCount }
        let rawSessions = events.filter { $0.processingMode == .raw }.count
        let cleanupFailureCount = events.filter(\.cleanupFailed).count
        return UsageSummary(
            totalWords: totalWords,
            totalSessions: events.count,
            estimatedTimeSavedSeconds: Self.estimatedTimeSavedSeconds(for: totalWords),
            rawSessions: rawSessions,
            cleanupSessions: events.count - rawSessions,
            cleanupFailureCount: cleanupFailureCount
        )
    }

    func dailyTrend() -> [UsageTrendBucket] {
        trend(component: .day)
    }

    func weeklyTrend() -> [UsageTrendBucket] {
        trend(component: .weekOfYear)
    }

    func topApps(limit: Int = 10) -> [UsageTopApp] {
        guard limit > 0 else { return [] }
        var grouped: [AppKey: (wordCount: Int, sessionCount: Int)] = [:]
        for event in events {
            let key = AppKey(
                displayName: event.sourceAppName ?? "Unknown App",
                bundleIdentifier: event.sourceBundleIdentifier
            )
            let current = grouped[key] ?? (0, 0)
            grouped[key] = (
                wordCount: current.wordCount + event.wordCount,
                sessionCount: current.sessionCount + 1
            )
        }

        return grouped.map { key, value in
            UsageTopApp(
                displayName: key.displayName,
                bundleIdentifier: key.bundleIdentifier,
                wordCount: value.wordCount,
                sessionCount: value.sessionCount
            )
        }
        .sorted {
            if $0.wordCount != $1.wordCount { return $0.wordCount > $1.wordCount }
            if $0.sessionCount != $1.sessionCount { return $0.sessionCount > $1.sessionCount }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        .prefix(limit)
        .map { $0 }
    }

    private func trend(component: Calendar.Component) -> [UsageTrendBucket] {
        var grouped: [Date: (wordCount: Int, sessionCount: Int)] = [:]
        for event in events {
            let startDate = Self.bucketStart(for: event.timestamp, component: component)
            let current = grouped[startDate] ?? (0, 0)
            grouped[startDate] = (
                wordCount: current.wordCount + event.wordCount,
                sessionCount: current.sessionCount + 1
            )
        }
        return grouped.map { startDate, value in
            UsageTrendBucket(
                startDate: startDate,
                wordCount: value.wordCount,
                sessionCount: value.sessionCount
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private func save() -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(events)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
            return true
        } catch {
            lastError = .saveFailed
            return false
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            events = try decoder.decode([UsageEvent].self, from: data)
            lastError = nil
        } catch {
            events = []
            lastError = .loadFailed
        }
    }

    private static func estimatedTimeSavedSeconds(for wordCount: Int) -> Int {
        Int((Double(max(0, wordCount)) / estimatedTypingWordsPerMinute * 60.0).rounded())
    }

    private static func bucketStart(for date: Date, component: Calendar.Component) -> Date {
        let calendar = isoUTCCalendar
        switch component {
        case .day:
            return calendar.startOfDay(for: date)
        case .weekOfYear:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        default:
            return calendar.startOfDay(for: date)
        }
    }

    private static var isoUTCCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private static func defaultStorageDirectory(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent(AppBrand.applicationSupportDirectoryName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private struct AppKey: Hashable {
        let displayName: String
        let bundleIdentifier: String?
    }
}

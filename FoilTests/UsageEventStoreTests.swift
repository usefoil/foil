import XCTest
@testable import Foil

@MainActor
final class UsageEventStoreTests: XCTestCase {
    private var testDir: URL!

    override func setUpWithError() throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilUsageEventStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testDir)
        testDir = nil
    }

    func testPersistsUsageEventsWhenTranscriptHistoryPersistenceIsDisabled() throws {
        let history = TranscriptionHistory(
            storageDirectory: testDir.appendingPathComponent("history", isDirectory: true),
            isPersistenceEnabled: false
        )
        history.addSuccess(text: "private transcript text")
        XCTAssertTrue(history.records.isEmpty)
        let store = UsageEventStore(storageDirectory: testDir.appendingPathComponent("usage", isDirectory: true))

        let result = store.record(event(words: 12, appName: "Terminal"))

        XCTAssertEqual(result, .stored)
        let reloaded = UsageEventStore(storageDirectory: testDir.appendingPathComponent("usage", isDirectory: true))
        XCTAssertEqual(reloaded.events.count, 1)
        XCTAssertEqual(reloaded.events.first?.wordCount, 12)
        XCTAssertEqual(reloaded.events.first?.sourceAppName, "Terminal")
    }

    func testEncodedUsageEventsAreMetadataOnly() throws {
        let store = UsageEventStore(storageDirectory: testDir)
        let forbidden = [
            "RAW TRANSCRIPT SENTINEL",
            "CLEANED TRANSCRIPT SENTINEL",
            "PROMPT SENTINEL",
            "VOCABULARY SENTINEL",
            "sk-secret",
            "/tmp/audio/private.wav",
            "/Applications/Secret.app",
            "https://example.com/v1?api_key=secret"
        ]

        XCTAssertEqual(
            store.record(
                event(
                    words: 42,
                    appName: "Secret",
                    bundleIdentifier: "com.example.Secret",
                    cleanupGroupID: "agentic-ides",
                    cleanupGroupName: "Agentic IDEs"
                )
            ),
            .stored
        )
        let rawJSON = try String(
            contentsOf: testDir.appendingPathComponent("usage-events.json"),
            encoding: .utf8
        )

        for sentinel in forbidden {
            XCTAssertFalse(rawJSON.contains(sentinel), "Unexpected sentinel in usage JSON: \(sentinel)\n\(rawJSON)")
        }
        for disallowedField in ["transcript", "prompt", "vocabulary", "apiKey", "audioFileURL", "appPath", "baseURL"] {
            XCTAssertFalse(rawJSON.localizedCaseInsensitiveContains(disallowedField), rawJSON)
        }
        XCTAssertTrue(rawJSON.contains(#""wordCount":42"#), rawJSON)
        XCTAssertTrue(rawJSON.contains(#""sourceBundleIdentifier":"com.example.Secret""#), rawJSON)
    }

    func testDisabledStoreDropsNewWritesButPreservesExistingEventsUntilDelete() {
        let store = UsageEventStore(storageDirectory: testDir)
        XCTAssertEqual(store.record(event(words: 5, appName: "Mail")), .stored)

        store.isEnabled = false
        let result = store.record(event(words: 9, appName: "Terminal"))

        XCTAssertEqual(result, .disabled)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events.first?.sourceAppName, "Mail")
        XCTAssertEqual(store.deleteAll(), .deleted)
        XCTAssertTrue(store.events.isEmpty)
        let reloaded = UsageEventStore(storageDirectory: testDir)
        XCTAssertTrue(reloaded.events.isEmpty)
    }

    func testDeleteUsageEventsDoesNotTouchTranscriptHistoryFiles() throws {
        let historyDirectory = testDir.appendingPathComponent("history", isDirectory: true)
        let history = TranscriptionHistory(storageDirectory: historyDirectory)
        history.addSuccess(text: "kept history text")
        let historyFile = historyDirectory.appendingPathComponent("history.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyFile.path))
        let store = UsageEventStore(storageDirectory: testDir.appendingPathComponent("usage", isDirectory: true))
        XCTAssertEqual(store.record(event(words: 5, appName: "Mail")), .stored)

        XCTAssertEqual(store.deleteAll(), .deleted)

        XCTAssertTrue(FileManager.default.fileExists(atPath: historyFile.path))
        let reloadedHistory = TranscriptionHistory(storageDirectory: historyDirectory)
        XCTAssertEqual(reloadedHistory.records.first?.text, "kept history text")
    }

    func testSummaryDailyWeeklyAndTopAppAggregatesAreDeterministic() {
        let store = UsageEventStore(storageDirectory: testDir)
        XCTAssertEqual(store.record(event(words: 80, appName: "Terminal", timestamp: isoDate("2026-01-04T23:30:00Z"), mode: .raw)), .stored)
        XCTAssertEqual(store.record(event(words: 120, appName: "Mail", timestamp: isoDate("2026-01-05T00:30:00Z"), mode: .cleanUp)), .stored)
        XCTAssertEqual(store.record(event(words: 40, appName: "Terminal", timestamp: isoDate("2026-01-11T10:00:00Z"), mode: .cleanUp, cleanupFailed: true)), .stored)

        let summary = store.summary()
        XCTAssertEqual(summary.totalWords, 240)
        XCTAssertEqual(summary.totalSessions, 3)
        XCTAssertEqual(summary.rawSessions, 1)
        XCTAssertEqual(summary.cleanupSessions, 2)
        XCTAssertEqual(summary.cleanupFailureCount, 1)
        XCTAssertEqual(summary.estimatedTimeSavedSeconds, 360)

        let daily = store.dailyTrend()
        XCTAssertEqual(daily.map(\.wordCount), [80, 120, 40])
        XCTAssertEqual(daily.map(\.sessionCount), [1, 1, 1])

        let weekly = store.weeklyTrend()
        XCTAssertEqual(weekly.map(\.wordCount), [80, 160])
        XCTAssertEqual(weekly.map(\.sessionCount), [1, 2])
        XCTAssertEqual(weekly.map { isoString($0.startDate) }, ["2025-12-29T00:00:00Z", "2026-01-05T00:00:00Z"])

        let topApps = store.topApps()
        XCTAssertEqual(topApps.map(\.displayName), ["Terminal", "Mail"])
        XCTAssertEqual(topApps.map(\.wordCount), [120, 120])
        XCTAssertEqual(topApps.map(\.sessionCount), [2, 1])
    }

    func testStorageFailureIsObservableAndNonThrowing() throws {
        let blockedFile = testDir.appendingPathComponent("blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blockedFile, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: blockedFile.appendingPathComponent("usage-events.json", isDirectory: true),
            withIntermediateDirectories: true
        )
        let store = UsageEventStore(storageDirectory: blockedFile)

        let result = store.record(event(words: 3, appName: "Mail"))

        XCTAssertEqual(result, .failed(.saveFailed))
        XCTAssertEqual(store.lastError, .saveFailed)
        XCTAssertTrue(store.events.isEmpty)
    }

    private func event(
        words: Int,
        appName: String,
        bundleIdentifier: String? = nil,
        cleanupGroupID: String? = nil,
        cleanupGroupName: String? = nil,
        timestamp: Date = Date(),
        mode: TranscriptProcessingMode = .cleanUp,
        cleanupFailed: Bool = false
    ) -> UsageEvent {
        UsageEvent(
            timestamp: timestamp,
            wordCount: words,
            sourceAppName: appName,
            sourceBundleIdentifier: bundleIdentifier,
            cleanupGroupID: cleanupGroupID,
            cleanupGroupName: cleanupGroupName,
            processingMode: mode,
            cleanupProviderID: .groq,
            cleanupModel: mode == .raw ? nil : "llama-3.1-8b-instant",
            cleanupFailed: cleanupFailed,
            outcome: cleanupFailed ? .cleanupFailedFallback : .success
        )
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

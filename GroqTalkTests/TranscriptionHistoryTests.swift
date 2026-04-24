import XCTest
@testable import GroqTalk

final class TranscriptionHistoryTests: XCTestCase {
    private var history: TranscriptionHistory!
    private var testDir: URL!

    override func setUp() {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("groqtalk-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        history = TranscriptionHistory(storageDirectory: testDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
    }

    func testStartsEmpty() {
        XCTAssertTrue(history.records.isEmpty)
    }

    func testAddSuccess() {
        history.addSuccess(text: "hello world")
        XCTAssertEqual(history.records.count, 1)
        XCTAssertEqual(history.records.first?.text, "hello world")
        XCTAssertNil(history.records.first?.error)
    }

    func testAddFailure() {
        let audioURL = testDir.appendingPathComponent("test.wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data([0x00]))

        history.addFailure(error: "API error (429)", audioFileURL: audioURL)
        XCTAssertEqual(history.records.count, 1)
        XCTAssertNil(history.records.first?.text)
        XCTAssertEqual(history.records.first?.error, "API error (429)")
        XCTAssertNotNil(history.records.first?.audioFileURL)
    }

    func testCapsAt20() {
        for i in 0..<25 {
            history.addSuccess(text: "entry \(i)")
        }
        XCTAssertEqual(history.records.count, 20)
        // Oldest entries should be removed — first remaining should be "entry 5"
        XCTAssertEqual(history.records.last?.text, "entry 5")
        // Newest should be "entry 24"
        XCTAssertEqual(history.records.first?.text, "entry 24")
    }

    func testPersistsToDisk() {
        history.addSuccess(text: "persisted")
        // Create a new instance reading from the same directory
        let history2 = TranscriptionHistory(storageDirectory: testDir)
        XCTAssertEqual(history2.records.count, 1)
        XCTAssertEqual(history2.records.first?.text, "persisted")
    }

    func testRetryUpdatesRecord() {
        let audioURL = testDir.appendingPathComponent("retry.wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data([0x00]))

        history.addFailure(error: "timeout", audioFileURL: audioURL)
        let recordID = history.records.first!.id

        history.resolveRetry(id: recordID, text: "retried text")

        XCTAssertEqual(history.records.first?.text, "retried text")
        XCTAssertNil(history.records.first?.error)
        XCTAssertNil(history.records.first?.audioFileURL)
        // Audio file should be deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testRetryFailureUpdatesError() {
        let audioURL = testDir.appendingPathComponent("retry2.wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data([0x00]))

        history.addFailure(error: "timeout", audioFileURL: audioURL)
        let recordID = history.records.first!.id

        history.resolveRetryFailure(id: recordID, error: "still broken")

        XCTAssertEqual(history.records.first?.error, "still broken")
        // Audio file should still exist for another retry attempt
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testRetryableRecord() {
        let audioURL = testDir.appendingPathComponent("retryable.wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data([0x00]))

        history.addFailure(error: "fail", audioFileURL: audioURL)
        XCTAssertNotNil(history.retryableRecord)

        history.addSuccess(text: "ok")
        // Most recent is a success — no retryable record
        XCTAssertNil(history.retryableRecord)
    }

    func testCapCleanupDeletesAudioFiles() {
        // Fill history with failures that have audio files
        for i in 0..<20 {
            let audioURL = testDir.appendingPathComponent("audio-\(i).wav")
            FileManager.default.createFile(atPath: audioURL.path, contents: Data([0x00]))
            history.addFailure(error: "fail \(i)", audioFileURL: audioURL)
        }
        // All 20 audio files should exist
        XCTAssertEqual(history.records.count, 20)

        // Adding one more should evict the oldest and delete its audio file
        let evictedURL = testDir.appendingPathComponent("audio-0.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: evictedURL.path))

        history.addSuccess(text: "new")
        XCTAssertEqual(history.records.count, 20)
        XCTAssertFalse(FileManager.default.fileExists(atPath: evictedURL.path))
    }

    func testPreviewText() {
        history.addSuccess(text: "This is a long transcription that should be truncated for display in the menu")
        let record = history.records.first!
        XCTAssertTrue(record.previewText.count <= 43) // 40 chars + "..."
    }
}

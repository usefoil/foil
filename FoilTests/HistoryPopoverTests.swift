import XCTest
@testable import Foil

@MainActor
final class HistoryPopoverTests: XCTestCase {
    private var testDir: URL!

    override func setUp() {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-popover-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
    }

    func testFilteredRecordsMatchesSearchText() {
        let history = TranscriptionHistory(storageDirectory: testDir)
        history.addSuccess(text: "hello world")
        history.addSuccess(text: "goodbye moon")
        history.addSuccess(text: "hello again")

        let filtered = history.records.filter { record in
            guard let text = record.text else { return false }
            return text.localizedCaseInsensitiveContains("hello")
        }
        XCTAssertEqual(filtered.count, 2)
    }

    func testFilteredRecordsEmptySearchReturnsAll() {
        let history = TranscriptionHistory(storageDirectory: testDir)
        history.addSuccess(text: "one")
        history.addSuccess(text: "two")

        let searchText = ""
        let filtered = history.records.filter { record in
            searchText.isEmpty || (record.text?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        XCTAssertEqual(filtered.count, 2)
    }

    func testFilteredRecordsExcludesFailures() {
        let history = TranscriptionHistory(storageDirectory: testDir)
        history.addSuccess(text: "hello world")
        history.addFailure(error: "timeout", audioFileURL: nil)

        let filtered = history.records.filter { record in
            guard let text = record.text else { return false }
            return text.localizedCaseInsensitiveContains("hello")
        }
        XCTAssertEqual(filtered.count, 1)
    }

    func testRetryableRecordDistinguishesMissingAudio() {
        let history = TranscriptionHistory(storageDirectory: testDir)
        history.addFailure(error: "timeout", audioFileURL: nil)

        XCTAssertNil(history.retryableRecord)
    }

    func testRetryableRecordExistsWhenAudioFileIsRetained() throws {
        let audioURL = testDir.appendingPathComponent("retry.wav")
        try Data("audio".utf8).write(to: audioURL)
        let history = TranscriptionHistory(storageDirectory: testDir)
        history.addFailure(error: "timeout", audioFileURL: audioURL)

        XCTAssertNotNil(history.retryableRecord)
    }

    func testFilteredRecordsCaseInsensitive() {
        let history = TranscriptionHistory(storageDirectory: testDir)
        history.addSuccess(text: "Hello World")

        let filtered = history.records.filter { record in
            guard let text = record.text else { return false }
            return text.localizedCaseInsensitiveContains("hello")
        }
        XCTAssertEqual(filtered.count, 1)
    }
}

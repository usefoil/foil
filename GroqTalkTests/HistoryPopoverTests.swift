import XCTest
@testable import GroqTalk

@MainActor
final class HistoryPopoverTests: XCTestCase {
    private var testDir: URL!

    override func setUp() {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("groqtalk-popover-test-\(UUID().uuidString)")
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

import XCTest
@testable import GroqTalk

final class KeychainHelperTests: XCTestCase {
    override func tearDown() {
        KeychainHelper.delete()
    }

    func testReadReturnsNilWhenEmpty() {
        KeychainHelper.delete()
        XCTAssertNil(KeychainHelper.readApiKey())
    }

    func testSaveAndRead() throws {
        try KeychainHelper.save(apiKey: "test-key-abc")
        XCTAssertEqual(KeychainHelper.readApiKey(), "test-key-abc")
    }

    func testSaveOverwritesExisting() throws {
        try KeychainHelper.save(apiKey: "old-key")
        try KeychainHelper.save(apiKey: "new-key")
        XCTAssertEqual(KeychainHelper.readApiKey(), "new-key")
    }

    func testDeleteRemovesKey() throws {
        try KeychainHelper.save(apiKey: "doomed-key")
        KeychainHelper.delete()
        XCTAssertNil(KeychainHelper.readApiKey())
    }
}

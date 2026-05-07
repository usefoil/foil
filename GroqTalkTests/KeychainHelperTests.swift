import XCTest
@testable import GroqTalk

final class KeychainHelperTests: XCTestCase {
    private var testDirectory: URL!

    override func setUpWithError() throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GroqTalkKeychainHelperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        KeychainHelper.storageDirectoryOverride = testDirectory
        KeychainHelper.legacyKeychainEnabled = false
    }

    override func tearDown() {
        KeychainHelper.delete()
        KeychainHelper.storageDirectoryOverride = nil
        KeychainHelper.legacyKeychainEnabled = true
        try? FileManager.default.removeItem(at: testDirectory)
        testDirectory = nil
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

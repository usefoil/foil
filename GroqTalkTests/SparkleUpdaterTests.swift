import XCTest
@testable import GroqTalk

@MainActor
final class SparkleUpdaterTests: XCTestCase {
    func testSparkleUpdaterInitializes() {
        let updater = SparkleUpdater()
        _ = updater.canCheckForUpdates
    }

    func testAutomaticallyChecksDefaultsToTrue() {
        let updater = SparkleUpdater()
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
    }

    func testCanToggleAutomaticUpdates() {
        let updater = SparkleUpdater()
        updater.automaticallyChecksForUpdates = false
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        updater.automaticallyChecksForUpdates = true
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
    }
}

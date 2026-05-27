import XCTest
@testable import Foil

@MainActor
final class SparkleUpdaterTests: XCTestCase {
    func testSparkleUpdaterInitializes() {
        let updater = SparkleUpdater.shared
        _ = updater.canCheckForUpdates
    }

    func testAutomaticallyChecksCanBeEnabled() {
        let updater = SparkleUpdater.shared

        updater.automaticallyChecksForUpdates = true

        XCTAssertTrue(updater.automaticallyChecksForUpdates)
    }

    func testCanToggleAutomaticUpdates() {
        let updater = SparkleUpdater.shared
        updater.automaticallyChecksForUpdates = false
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        updater.automaticallyChecksForUpdates = true
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
    }
}

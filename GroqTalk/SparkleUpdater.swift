import Sparkle
import SwiftUI

@MainActor
@Observable
final class SparkleUpdater {
    static let shared = SparkleUpdater()

    private let updaterController: SPUStandardUpdaterController
    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    var canCheckForUpdates: Bool {
        guard !Self.isUITesting else { return false }
        return updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    private init() {
        if Self.isUITesting {
            UserDefaults.standard.set(false, forKey: "SUEnableAutomaticChecks")
            UserDefaults.standard.set(false, forKey: "SUSendProfileInfo")
        }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !Self.isUITesting,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard !Self.isUITesting else { return }
        updaterController.checkForUpdates(nil)
    }
}

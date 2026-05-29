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

    private static var isUpdaterEnabled: Bool {
        !isUITesting && !AppBrand.isDevelopmentBuild
    }

    var canCheckForUpdates: Bool {
        guard Self.isUpdaterEnabled else { return false }
        return updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { Self.isUpdaterEnabled && updaterController.updater.automaticallyChecksForUpdates }
        set {
            guard Self.isUpdaterEnabled else { return }
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    private init() {
        if !Self.isUpdaterEnabled {
            UserDefaults.standard.set(false, forKey: "SUEnableAutomaticChecks")
            UserDefaults.standard.set(false, forKey: "SUSendProfileInfo")
        }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: Self.isUpdaterEnabled,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard Self.isUpdaterEnabled else { return }
        updaterController.checkForUpdates(nil)
    }
}

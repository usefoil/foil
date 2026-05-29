import Foundation

enum AppBrand {
    static let productionBundleIdentifier = "com.neonwatty.Foil"
    static let developmentBundleIdentifier = "com.neonwatty.Foil.Dev"

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? productionBundleIdentifier
    }

    static var isDevelopmentBuild: Bool {
        bundleIdentifier == developmentBundleIdentifier
    }

    static var name: String {
        isDevelopmentBuild ? "Foil Dev" : "Foil"
    }

    static var applicationSupportDirectoryName: String {
        name
    }

    static var keychainService: String {
        bundleIdentifier
    }
}

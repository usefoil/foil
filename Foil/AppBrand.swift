import Foundation
import SwiftUI

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

    static var versionDisplay: String {
        versionDisplay(bundle: .main)
    }

    static func versionDisplay(bundle: Bundle) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let trimmedVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBuild = build?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayBuild = trimmedBuild.flatMap(shortBuildDisplay)

        switch (trimmedVersion?.isEmpty == false ? trimmedVersion : nil, displayBuild) {
        case let (.some(version), .some(build)):
            return "\(name) \(version) (build \(build))"
        case let (.some(version), nil):
            return "\(name) \(version)"
        case (nil, .some(let build)):
            return "\(name) build \(build)"
        case (nil, nil):
            return "\(name) version unknown"
        }
    }

    static func shortBuildDisplay(_ build: String) -> String? {
        let trimmed = build.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > 7 else { return trimmed }
        return String(trimmed.suffix(6))
    }
}

struct AppVersionFooter: View {
    let accessibilityIdentifier: String

    var body: some View {
        Text(AppBrand.versionDisplay)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

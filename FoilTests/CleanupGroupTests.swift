import XCTest
@testable import Foil

final class CleanupGroupTests: XCTestCase {
    func testRunningAppCandidatePolicyExcludesFoilAndCommonNonTextApps() {
        let blockedCandidates: [(name: String, bundleID: String?, path: String?)] = [
            ("Foil", "com.neonwatty.Foil", "/Applications/Foil.app"),
            ("Foil Dev", "com.neonwatty.Foil.Dev", "/Applications/Foil Dev.app"),
            ("Foil", nil, "/Users/me/DerivedData/Foil.app"),
            ("Finder", "com.apple.finder", "/System/Library/CoreServices/Finder.app"),
            ("Photos", "com.apple.Photos", "/System/Applications/Photos.app"),
            ("System Settings", "com.apple.systempreferences", "/System/Applications/System Settings.app"),
            ("Activity Monitor", "com.apple.ActivityMonitor", "/System/Applications/Utilities/Activity Monitor.app"),
            ("Preview", "com.apple.Preview", "/System/Applications/Preview.app"),
            ("App Store", "com.apple.AppStore", "/System/Applications/App Store.app")
        ]

        for candidate in blockedCandidates {
            XCTAssertFalse(
                RunningAppCandidatePolicy.allows(
                    displayName: candidate.name,
                    bundleIdentifier: candidate.bundleID,
                    appPath: candidate.path,
                    currentBundleIdentifier: "com.neonwatty.Foil"
                ),
                "\(candidate.name) should not be offered as a running app candidate"
            )
        }
    }

    func testRunningAppCandidatePolicyAllowsTextLikelyApps() {
        let allowedCandidates: [(name: String, bundleID: String?, path: String?)] = [
            ("Ghostty", "com.mitchellh.ghostty", "/Applications/Ghostty.app"),
            ("Terminal", "com.apple.Terminal", "/System/Applications/Utilities/Terminal.app"),
            ("Codex", "com.openai.codex", "/Applications/Codex.app"),
            ("Google Chrome", "com.google.Chrome", "/Applications/Google Chrome.app"),
            ("Messages (iMessage)", "com.apple.MobileSMS", "/System/Applications/Messages.app"),
            ("Mail", "com.apple.mail", "/System/Applications/Mail.app")
        ]

        for candidate in allowedCandidates {
            XCTAssertTrue(
                RunningAppCandidatePolicy.allows(
                    displayName: candidate.name,
                    bundleIdentifier: candidate.bundleID,
                    appPath: candidate.path,
                    currentBundleIdentifier: "com.neonwatty.Foil"
                ),
                "\(candidate.name) should remain available when it is running"
            )
        }
    }

    func testAppMatcherMembershipIsUniqueAcrossGroupsMostRecentWins() {
        let originalGroup = CleanupGroup(
            id: "agentic-ides",
            name: "Agentic IDEs",
            sortOrder: 1,
            appMatchers: [
                CleanupAppMatcher(displayName: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92")
            ],
            processingMode: .raw
        )
        let replacementGroup = CleanupGroup(
            id: "messaging",
            name: "Messaging",
            sortOrder: 2,
            appMatchers: [
                CleanupAppMatcher(displayName: "Cursor", bundleIdentifier: "COM.TODESKTOP.230313MZL4W4U92")
            ],
            processingMode: .cleanUp
        )

        let groups = CleanupGroupResolver.normalizedGroups([
            CleanupGroup.defaultGroup(),
            originalGroup,
            replacementGroup
        ])

        XCTAssertEqual(groups.first { $0.id == "agentic-ides" }?.appMatchers, [])
        XCTAssertEqual(groups.first { $0.id == "messaging" }?.appMatchers.count, 1)
    }

    func testUnassignedAndNilAppContextsResolveToDefaultGroup() {
        let defaultGroup = CleanupGroup.defaultGroup(processingMode: .raw)
        let assignedGroup = CleanupGroup(
            id: "terminal",
            name: "Terminal",
            sortOrder: 1,
            appMatchers: [
                CleanupAppMatcher(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
            ],
            processingMode: .cleanUp
        )

        let nilResolution = CleanupGroupResolver.resolve(
            appContext: nil,
            groups: [defaultGroup, assignedGroup],
            providerFactory: { _ in .groq(model: "llama-3.1-8b-instant") }
        )
        let unassignedResolution = CleanupGroupResolver.resolve(
            appContext: CleanupAppContext(displayName: "Notes", bundleIdentifier: "com.apple.Notes"),
            groups: [defaultGroup, assignedGroup],
            providerFactory: { _ in .groq(model: "llama-3.1-8b-instant") }
        )

        XCTAssertEqual(nilResolution.group.id, CleanupGroup.defaultGroupID)
        XCTAssertEqual(unassignedResolution.group.id, CleanupGroup.defaultGroupID)
        XCTAssertEqual(nilResolution.provider.id, .none)
        XCTAssertEqual(unassignedResolution.provider.id, .none)
    }

    func testDisabledNonDefaultGroupIsSkippedAndAppFallsThroughToDefault() {
        let disabledGroup = CleanupGroup(
            id: "terminal",
            name: "Terminal",
            sortOrder: 1,
            isEnabled: false,
            appMatchers: [
                CleanupAppMatcher(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
            ],
            processingMode: .cleanUp
        )

        let resolution = CleanupGroupResolver.resolve(
            appContext: CleanupAppContext(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
            groups: [
                CleanupGroup.defaultGroup(processingMode: .raw),
                disabledGroup
            ],
            providerFactory: { _ in .groq(model: "llama-3.1-8b-instant") }
        )

        XCTAssertEqual(resolution.group.id, CleanupGroup.defaultGroupID)
        XCTAssertEqual(resolution.processingMode, .raw)
        XCTAssertEqual(resolution.provider.id, .none)
    }

    func testDefaultGroupNormalizesToDeterministicEnabledDefault() {
        let malformedDefault = CleanupGroup(
            id: "random-default",
            name: "Renamed default",
            sortOrder: 99,
            isEnabled: false,
            processingMode: .cleanUp,
            isDefault: true
        )

        let normalized = CleanupGroupResolver.normalizedGroups([malformedDefault])

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].id, CleanupGroup.defaultGroupID)
        XCTAssertEqual(normalized[0].name, CleanupGroup.defaultGroupName)
        XCTAssertEqual(normalized[0].sortOrder, 0)
        XCTAssertTrue(normalized[0].isDefault)
        XCTAssertTrue(normalized[0].isEnabled)
        XCTAssertEqual(normalized[0].processingMode, .cleanUp)
    }
}

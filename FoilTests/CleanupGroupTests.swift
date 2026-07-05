import XCTest
@testable import Foil

final class CleanupGroupTests: XCTestCase {
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

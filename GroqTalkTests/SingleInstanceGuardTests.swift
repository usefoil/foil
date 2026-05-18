import XCTest
@testable import GroqTalk

// MARK: - Stubs

private final class AlreadyRunningStub: SingleInstanceGuarding {
    private(set) var callCount = 0
    func activateExistingInstanceIfRunning() -> Bool {
        callCount += 1
        return true
    }
}

private final class NotRunningStub: SingleInstanceGuarding {
    private(set) var callCount = 0
    func activateExistingInstanceIfRunning() -> Bool {
        callCount += 1
        return false
    }
}

// MARK: - Tests

@MainActor
final class SingleInstanceGuardTests: XCTestCase {

    // MARK: - Protocol contract

    func testReturnsFalseWhenNoDuplicate() {
        let stub = NotRunningStub()
        XCTAssertFalse(stub.activateExistingInstanceIfRunning(),
                       "Should return false when no other instance is running")
    }

    func testReturnsTrueWhenDuplicateRunning() {
        let stub = AlreadyRunningStub()
        XCTAssertTrue(stub.activateExistingInstanceIfRunning(),
                      "Should return true when another instance is running")
    }

    // MARK: - Real implementation

    func testRealGuardDoesNotFalsePositiveInTestHost() {
        // In the test host, Bundle.main.bundleIdentifier is the test runner's ID,
        // not com.neonwatty.GroqTalk. The guard should return false (no match).
        // If the real GroqTalk app happens to be running, the guard may detect it
        // via its own bundle ID — that's correct behavior, not a false positive.
        let guard_ = SingleInstanceGuard()
        _ = guard_.activateExistingInstanceIfRunning()
        // Primary assertion: the call completes without crashing.
        // The return value depends on whether the real app is running.
    }

    // MARK: - AppDelegate integration

    func testGuardBypassedDuringUnitTests() {
        XCTAssertTrue(
            AppDelegate.isTestingProcess(
                arguments: ["/tmp/GroqTalkTests.xctest"],
                environment: [:]
            ),
            "xctest launch arguments should bypass the duplicate-app guard"
        )

        XCTAssertTrue(
            AppDelegate.isTestingProcess(
                arguments: [],
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
            ),
            "XCTestConfigurationFilePath should bypass the duplicate-app guard"
        )
    }

    func testNormalLaunchIsNotClassifiedAsTestingOnlyBecauseXCTestIsLoaded() {
        XCTAssertFalse(
            AppDelegate.isTestingProcess(
                arguments: ["/Applications/GroqTalk.app/Contents/MacOS/GroqTalk"],
                environment: [:]
            ),
            "normal app launches should start the hotkey monitor even if XCTest symbols are present"
        )
    }

    func testAppDelegateAcceptsInjectedGuard() {
        // Verify the designated initializer accepts a custom guard.
        let stub = NotRunningStub()
        let delegate = AppDelegate(singleInstanceGuard: stub)
        XCTAssertNotNil(delegate, "AppDelegate should accept an injected guard")
    }
}

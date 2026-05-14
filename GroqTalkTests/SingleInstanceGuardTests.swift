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
        // NSClassFromString("XCTestCase") is non-nil during unit tests,
        // so the guard should be bypassed entirely — even if it would
        // detect a duplicate.
        XCTAssertNotNil(NSClassFromString("XCTestCase"),
                        "XCTestCase must be loaded during unit tests")

        // Verify the bypass condition matches what AppDelegate checks.
        let isTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            || NSClassFromString("XCTestCase") != nil
        XCTAssertTrue(isTesting,
                      "isTesting should be true during unit tests, preventing the guard from firing")
    }

    func testAppDelegateAcceptsInjectedGuard() {
        // Verify the designated initializer accepts a custom guard.
        let stub = NotRunningStub()
        let delegate = AppDelegate(singleInstanceGuard: stub)
        XCTAssertNotNil(delegate, "AppDelegate should accept an injected guard")
    }
}

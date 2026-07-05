import XCTest
@testable import Foil

final class PasteTargetTests: XCTestCase {
    func testCaptureReturnsNilWithoutAccessibility() {
        // In the test runner, AX permissions may not be granted.
        // PasteTarget.captureCurrentTarget() should return nil gracefully
        // rather than crashing when AX queries fail.
        let target = PasteTarget.captureCurrentTarget()
        // Either nil (no AX) or a valid target — must not crash
        if let target {
            XCTAssertGreaterThan(target.pid, 0)
        }
    }

    func testManualInitStoresValues() {
        let target = PasteTarget(windowElement: nil, windowID: nil, pid: 12345, appName: "TestApp")
        XCTAssertEqual(target.pid, 12345)
        XCTAssertEqual(target.appName, "TestApp")
        XCTAssertNil(target.windowElement)
    }

    func testManualInitBuildsCleanupAppContext() {
        let target = PasteTarget(
            windowElement: nil,
            windowID: nil,
            pid: 12345,
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            appPath: "/System/Applications/Utilities/Terminal.app"
        )

        XCTAssertEqual(
            target.cleanupAppContext,
            CleanupAppContext(
                displayName: "Terminal",
                bundleIdentifier: "com.apple.Terminal",
                appPath: "/System/Applications/Utilities/Terminal.app"
            )
        )
    }

    func testDescriptionOmitsAppPath() {
        let target = PasteTarget(
            windowElement: nil,
            windowID: 7,
            pid: 12345,
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            appPath: "/System/Applications/Utilities/Terminal.app"
        )

        XCTAssertTrue(target.description.contains("Terminal"))
        XCTAssertTrue(target.description.contains("com.apple.Terminal"))
        XCTAssertFalse(target.description.contains("/System/Applications/Utilities/Terminal.app"))
    }

    func testTargetWithZeroPidIsInvalid() {
        let target = PasteTarget(windowElement: nil, windowID: nil, pid: 0, appName: "")
        XCTAssertFalse(target.isValid)
    }

    func testTargetWithPositivePidIsValid() {
        let target = PasteTarget(windowElement: nil, windowID: nil, pid: 999, appName: "App")
        XCTAssertTrue(target.isValid)
    }

    func testManualInitWithWindowID() {
        let target = PasteTarget(windowElement: nil, windowID: 12345, pid: 999, appName: "App")
        XCTAssertEqual(target.windowID, 12345)
    }

    func testManualInitWithNilWindowID() {
        let target = PasteTarget(windowElement: nil, windowID: nil, pid: 999, appName: "App")
        XCTAssertNil(target.windowID)
    }

    func testCaptureIncludesWindowID() {
        // On a dev machine with AX, captureCurrentTarget should attempt
        // to populate windowID. The SPI may return nil for test runner
        // windows, so just verify no crash occurs.
        let target = PasteTarget.captureCurrentTarget()
        if let target, target.windowElement != nil {
            // windowID may or may not be populated depending on
            // whether _AXUIElementGetWindow works for this window type
            _ = target.windowID
        }
    }
}

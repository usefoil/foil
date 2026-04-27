import XCTest
@testable import GroqTalk

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
        // to populate windowID. We can't guarantee it's non-nil (depends
        // on AX permissions) but it must not crash.
        let target = PasteTarget.captureCurrentTarget()
        if let target, target.windowElement != nil {
            // If we got a window element, windowID should also be populated
            // (both come from the same focused window).
            XCTAssertNotNil(target.windowID)
        }
    }
}

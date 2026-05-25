import XCTest
@testable import Foil

final class SkyLightBridgeTests: XCTestCase {
    func testIsAvailableReturnsBool() {
        // Smoke test: must not crash. On a dev machine with SkyLight, this is true.
        _ = SkyLightBridge.isAvailable
    }

    func testFocusWithoutRaiseReturnsFalseForInvalidPid() {
        let result = SkyLightBridge.focusWithoutRaise(targetPid: 0, targetWindowID: 0)
        XCTAssertFalse(result)
    }

    func testWindowIDFromNilElementReturnsNil() {
        let fakeElement = AXUIElementCreateApplication(0)
        let wid = SkyLightBridge.windowID(from: fakeElement)
        XCTAssertNil(wid)
    }
}

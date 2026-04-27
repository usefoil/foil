import XCTest
@testable import GroqTalk

final class SkyLightBridgeTests: XCTestCase {
    func testIsAvailableReturnsBool() {
        let available = SkyLightBridge.isAvailable
        XCTAssertTrue(available is Bool)
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

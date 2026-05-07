import XCTest
@testable import GroqTalk

final class BackgroundPasteTests: XCTestCase {
    func testAttemptReturnsFalseWhenWindowIDIsNil() async {
        let target = PasteTarget(windowElement: nil, windowID: nil, pid: 999, appName: "App")
        let result = await BackgroundPaste.attempt(
            text: "hello", target: target, keepOnClipboard: false
        )
        XCTAssertFalse(result)
    }

    func testAttemptReturnsFalseForInvalidPid() async {
        let target = PasteTarget(windowElement: nil, windowID: 12345, pid: 0, appName: "")
        let result = await BackgroundPaste.attempt(
            text: "hello", target: target, keepOnClipboard: false
        )
        XCTAssertFalse(result)
    }

    func testAttemptReturnsFalseForTerminatedProcess() async {
        // pid 99999 is almost certainly not running
        let target = PasteTarget(windowElement: nil, windowID: 12345, pid: 99999, appName: "Ghost")
        let result = await BackgroundPaste.attempt(
            text: "hello", target: target, keepOnClipboard: false
        )
        XCTAssertFalse(result)
    }
}

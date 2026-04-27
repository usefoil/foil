import XCTest
@testable import GroqTalk

final class PasteQueueTests: XCTestCase {
    func testEnqueueAndDrain() async {
        var pastedTexts: [String] = []

        let queue = PasteQueue { text, _, _ in
            pastedTexts.append(text)
        }

        await queue.enqueue(text: "hello", target: PasteTarget(windowElement: nil, windowID: nil, pid: 1, appName: "A"), keepOnClipboard: false)
        await queue.enqueue(text: "world", target: PasteTarget(windowElement: nil, windowID: nil, pid: 2, appName: "B"), keepOnClipboard: false)

        XCTAssertEqual(pastedTexts, ["hello", "world"])
    }

    func testSerializesExecution() async {
        var order: [Int] = []
        let expectation = XCTestExpectation(description: "all pastes complete")
        expectation.expectedFulfillmentCount = 3

        let queue = PasteQueue { text, _, _ in
            let index = Int(text)!
            // Simulate variable paste durations
            try? await Task.sleep(for: .milliseconds(50 - index * 10))
            order.append(index)
            expectation.fulfill()
        }

        // Enqueue sequentially — each must execute in the order submitted
        // (serialization prevents the shortest-sleep item from winning the race).
        await queue.enqueue(text: "1", target: PasteTarget(windowElement: nil, windowID: nil, pid: 1, appName: "A"), keepOnClipboard: false)
        await queue.enqueue(text: "2", target: PasteTarget(windowElement: nil, windowID: nil, pid: 1, appName: "A"), keepOnClipboard: false)
        await queue.enqueue(text: "3", target: PasteTarget(windowElement: nil, windowID: nil, pid: 1, appName: "A"), keepOnClipboard: false)

        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(order, [1, 2, 3])
    }

    func testInvalidTargetSkips() async {
        var called = false

        let queue = PasteQueue { _, _, _ in
            called = true
        }

        let invalidTarget = PasteTarget(windowElement: nil, windowID: nil, pid: 0, appName: "")
        await queue.enqueue(text: "skip me", target: invalidTarget, keepOnClipboard: false)

        XCTAssertFalse(called)
    }
}

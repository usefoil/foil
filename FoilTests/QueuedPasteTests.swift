import XCTest
@testable import Foil

@MainActor
final class QueuedPasteTests: XCTestCase {
    private let targetA = PasteTarget(windowElement: nil, windowID: nil, pid: 1, appName: "A")
    private let targetB = PasteTarget(windowElement: nil, windowID: nil, pid: 2, appName: "B")

    func testOrdersItemsByRecordingStartTime() {
        let queue = QueuedPasteQueue { _, _ in .asyncQueued }
        let later = Date(timeIntervalSince1970: 20)
        let earlier = Date(timeIntervalSince1970: 10)

        queue.enqueue(text: "second", target: targetB, recordingStartTime: later)
        queue.enqueue(text: "first", target: targetA, recordingStartTime: earlier)

        XCTAssertEqual(queue.items.map(\.text), ["first", "second"])
    }

    func testStepThroughDeliversExactlyOnePendingItem() async {
        var delivered: [String] = []
        let queue = QueuedPasteQueue { text, _ in
            delivered.append(text)
            return .asyncQueued
        }

        queue.enqueue(text: "one", target: targetA, recordingStartTime: Date(timeIntervalSince1970: 1))
        queue.enqueue(text: "two", target: targetB, recordingStartTime: Date(timeIntervalSince1970: 2))

        let delivery = await queue.deliverNext()

        XCTAssertEqual(delivery, .asyncQueued)
        XCTAssertEqual(delivered, ["one"])
        XCTAssertEqual(queue.items.map(\.text), ["two"])
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testDrainAttemptsAllPendingItemsInOrder() async {
        var delivered: [String] = []
        let queue = QueuedPasteQueue { text, _ in
            delivered.append(text)
            return .asyncQueued
        }

        queue.enqueue(text: "two", target: targetB, recordingStartTime: Date(timeIntervalSince1970: 2))
        queue.enqueue(text: "one", target: targetA, recordingStartTime: Date(timeIntervalSince1970: 1))

        let deliveries = await queue.drain()

        XCTAssertEqual(deliveries, [.asyncQueued, .asyncQueued])
        XCTAssertEqual(delivered, ["one", "two"])
        XCTAssertFalse(queue.hasItems)
    }

    func testFallbackDeliveryRetainsItemForManualPaste() async {
        let queue = QueuedPasteQueue { _, _ in .clipboardFallback }
        queue.enqueue(text: "keep me", target: targetA, recordingStartTime: Date())

        let delivery = await queue.deliverNext()

        XCTAssertEqual(delivery, .clipboardFallback)
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(queue.items.first?.status, .needsManualPaste)
        XCTAssertEqual(queue.items.first?.text, "keep me")
        XCTAssertEqual(queue.blockedCount, 1)
    }

    func testMissingTargetCreatesManualPasteItem() {
        let queue = QueuedPasteQueue { _, _ in .asyncQueued }

        queue.enqueue(text: "manual", target: nil, recordingStartTime: Date())

        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(queue.items.first?.status, .needsManualPaste)
        XCTAssertEqual(queue.items.first?.failureReason, "Original target unavailable")
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(queue.blockedCount, 1)
    }

    func testRemoveDeletesQueuedItem() {
        let queue = QueuedPasteQueue { _, _ in .asyncQueued }
        let id = queue.enqueue(text: "remove", target: targetA, recordingStartTime: Date())

        queue.remove(id: id)

        XCTAssertFalse(queue.hasItems)
    }
}

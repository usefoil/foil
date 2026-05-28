import XCTest
@testable import Foil

@MainActor
final class QueuedPasteTests: XCTestCase {
    private let targetA = PasteTarget(windowElement: nil, windowID: nil, pid: 1, appName: "A")
    private let targetB = PasteTarget(windowElement: nil, windowID: nil, pid: 2, appName: "B")

    override func setUp() {
        super.setUp()
        clearPersistedAppStateDefaults()
    }

    override func tearDown() {
        clearPersistedAppStateDefaults()
        super.tearDown()
    }

    private func clearPersistedAppStateDefaults() {
        UserDefaults.standard.removeObject(forKey: "hotkeyChoice")
        UserDefaults.standard.removeObject(forKey: "customHotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "customHotkeyModifiers")
        UserDefaults.standard.removeObject(forKey: "customHotkeyLabel")
        UserDefaults.standard.removeObject(forKey: "asyncPasteEnabled")
        UserDefaults.standard.removeObject(forKey: "queuedPasteEnabled")
        UserDefaults.standard.removeObject(forKey: "queuedPasteMode")
    }

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
        XCTAssertEqual(queue.items.first?.failureReason, "Target unavailable; text copied to clipboard")
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

    func testHotkeyDeliveryNoopsWhenQueuedPasteDisabled() async {
        var delivered: [String] = []
        let appState = AppState()
        appState.queuedPasteEnabled = false
        appState.queuedPasteMode = .stepThrough
        let queue = QueuedPasteQueue { text, _ in
            delivered.append(text)
            return .asyncQueued
        }
        queue.enqueue(text: "keep queued", target: targetA, recordingStartTime: Date())

        let result = await QueuedPasteDeliveryController(appState: appState, queue: queue).deliverFromHotkey()

        XCTAssertEqual(result, .disabled)
        XCTAssertEqual(delivered, [])
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testHotkeyStepThroughDeliversOneItem() async {
        var delivered: [String] = []
        let appState = AppState()
        appState.queuedPasteEnabled = true
        appState.queuedPasteMode = .stepThrough
        let queue = QueuedPasteQueue { text, _ in
            delivered.append(text)
            return .asyncQueued
        }
        queue.enqueue(text: "one", target: targetA, recordingStartTime: Date(timeIntervalSince1970: 1))
        queue.enqueue(text: "two", target: targetB, recordingStartTime: Date(timeIntervalSince1970: 2))

        let result = await QueuedPasteDeliveryController(appState: appState, queue: queue).deliverFromHotkey()

        XCTAssertEqual(result, .deliveredNext(.asyncQueued))
        XCTAssertEqual(delivered, ["one"])
        XCTAssertEqual(queue.items.map(\.text), ["two"])
    }

    func testHotkeyDrainDeliversAllPendingItems() async {
        var delivered: [String] = []
        let appState = AppState()
        appState.queuedPasteEnabled = true
        appState.queuedPasteMode = .drain
        let queue = QueuedPasteQueue { text, _ in
            delivered.append(text)
            return .asyncQueued
        }
        queue.enqueue(text: "two", target: targetB, recordingStartTime: Date(timeIntervalSince1970: 2))
        queue.enqueue(text: "one", target: targetA, recordingStartTime: Date(timeIntervalSince1970: 1))

        let result = await QueuedPasteDeliveryController(appState: appState, queue: queue).deliverFromHotkey()

        XCTAssertEqual(result, .drained(2))
        XCTAssertEqual(delivered, ["one", "two"])
        XCTAssertFalse(queue.hasItems)
    }

    func testHotkeyNoopsWhenQueueIsEmpty() async {
        let appState = AppState()
        appState.queuedPasteEnabled = true
        appState.queuedPasteMode = .stepThrough
        let queue = QueuedPasteQueue { _, _ in .asyncQueued }

        let result = await QueuedPasteDeliveryController(appState: appState, queue: queue).deliverFromHotkey()

        XCTAssertEqual(result, .empty)
        XCTAssertEqual(appState.feedbackMessage, "Paste queue empty")
    }

    func testHotkeyNoopsWhenShortcutConflictsWithCustomRecordingShortcut() async {
        let appState = AppState()
        appState.queuedPasteEnabled = true
        appState.hotkeyChoice = .custom
        appState.customHotkeyKeyCode = QueuedPasteDeliveryShortcut.default.keyCode
        appState.customHotkeyModifiers = QueuedPasteDeliveryShortcut.default.modifiers.rawValue
        let queue = QueuedPasteQueue { _, _ in .asyncQueued }
        queue.enqueue(text: "blocked", target: targetA, recordingStartTime: Date())

        let result = await QueuedPasteDeliveryController(appState: appState, queue: queue).deliverFromHotkey()

        XCTAssertEqual(result, .conflict)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(appState.feedbackMessage, "Queued paste shortcut conflicts with recording shortcut")
    }
}

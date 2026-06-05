import XCTest
@testable import Foil

final class HotkeyMonitorCustomKeyTests: XCTestCase {
    private var events: [String] = []

    override func setUp() {
        events = []
    }

    func testConfigureCustomKeySetsProperties() {
        let monitor = HotkeyMonitor()
        monitor.configureCustomKey(keyCode: 0x31, modifiers: 0x100108)
        XCTAssertEqual(monitor.customKeyCode, 0x31)
        XCTAssertEqual(monitor.customModifiers, 0x100108)
    }

    func testCustomHotkeyChoiceLabel() {
        XCTAssertEqual(HotkeyMonitor.HotkeyChoice.custom.label, "Custom")
    }

    func testAllHotkeyChoicesIncludesCustom() {
        XCTAssertTrue(HotkeyMonitor.HotkeyChoice.allCases.contains(.custom))
    }

    func testCustomHotkeyChoiceDeviceFlagBitIsZero() {
        XCTAssertEqual(HotkeyMonitor.HotkeyChoice.custom.deviceFlagBit, 0)
    }

    func testCustomHotkeyChoiceRawValue() {
        XCTAssertEqual(HotkeyMonitor.HotkeyChoice.custom.rawValue, "custom")
    }

    func testConfigureCustomKeyOverwritesPreviousValues() {
        let monitor = HotkeyMonitor()
        monitor.configureCustomKey(keyCode: 0x10, modifiers: 0xFF)
        monitor.configureCustomKey(keyCode: 0x31, modifiers: 0x100108)
        XCTAssertEqual(monitor.customKeyCode, 0x31)
        XCTAssertEqual(monitor.customModifiers, 0x100108)
    }

    func testCustomChoiceDefaultsToZeroKeyCodeAndModifiers() {
        let monitor = HotkeyMonitor()
        XCTAssertEqual(monitor.customKeyCode, 0)
        XCTAssertEqual(monitor.customModifiers, 0)
    }

    func testAllCasesContainsAllExpectedChoices() {
        let all = HotkeyMonitor.HotkeyChoice.allCases
        XCTAssertTrue(all.contains(.rightCommand))
        XCTAssertTrue(all.contains(.rightOption))
        XCTAssertTrue(all.contains(.globeFn))
        XCTAssertTrue(all.contains(.custom))
        XCTAssertEqual(all.count, 4)
    }

    func testMatchingCustomHotkeyKeyDownIsConsumedAndStartsRecording() {
        let monitor = HotkeyMonitor()
        monitor.configure(hotkeyChoice: .custom, recordingMode: .hold)
        monitor.configureCustomKey(keyCode: 0x7E, modifiers: 0)
        monitor.onRecordingStarted = { [weak self] in self?.events.append("started") }

        let consumed = monitor.handleCGEventForTesting(
            type: .keyDown,
            keyCode: 0x7E,
            flags: []
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(events, ["started"])
    }

    func testMatchingCustomHotkeyKeyUpIsConsumedAndStopsRecording() {
        let monitor = HotkeyMonitor()
        monitor.configure(hotkeyChoice: .custom, recordingMode: .hold)
        monitor.configureCustomKey(keyCode: 0x7E, modifiers: 0)
        monitor.onRecordingStarted = { [weak self] in self?.events.append("started") }
        monitor.onRecordingStopped = { [weak self] in self?.events.append("stopped") }

        XCTAssertTrue(monitor.handleCGEventForTesting(type: .keyDown, keyCode: 0x7E, flags: []))
        Thread.sleep(forTimeInterval: 0.25)
        let consumed = monitor.handleCGEventForTesting(type: .keyUp, keyCode: 0x7E, flags: [])

        XCTAssertTrue(consumed)
        XCTAssertEqual(events, ["started", "stopped"])
    }

    func testNonMatchingCustomHotkeyIsPassedThrough() {
        let monitor = HotkeyMonitor()
        monitor.configure(hotkeyChoice: .custom, recordingMode: .hold)
        monitor.configureCustomKey(keyCode: 0x7E, modifiers: 0)
        monitor.onRecordingStarted = { [weak self] in self?.events.append("started") }

        let consumed = monitor.handleCGEventForTesting(
            type: .keyDown,
            keyCode: 0x7D,
            flags: []
        )

        XCTAssertFalse(consumed)
        XCTAssertEqual(events, [])
    }
}

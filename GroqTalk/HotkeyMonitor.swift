import Foundation
import IOKit
import IOKit.hid

final class HotkeyMonitor {
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    var onRecordingCancelled: (() -> Void)?

    private var manager: IOHIDManager?
    private var fnKeyDown = false
    private var otherKeysDuringFn = false
    private var fnPressTime: Date?
    private let debounceInterval: TimeInterval = 0.2

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        // Match Apple Vendor Top Case — this is where the Fn/Globe key lives
        // Page 0x00FF = kHIDPage_AppleVendorTopCase
        // Usage 0x0001 = kHIDUsage_AppleVendorTopCase_Keyboard
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: 0x00FF,
            kIOHIDDeviceUsageKey: 0x0001
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let callback: IOHIDValueCallback = { context, _, _, value in
            guard let context else { return }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleHIDValue(value)
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, callback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usage = IOHIDElementGetUsage(element)
        let pressed = IOHIDValueGetIntegerValue(value) == 1

        // 0x0003 = kHIDUsage_AppleVendorTopCase_KeyboardFn (Globe/Fn key)
        if usage == 0x0003 {
            if pressed {
                fnKeyDown = true
                otherKeysDuringFn = false
                fnPressTime = Date()
                onRecordingStarted?()
            } else {
                let wasSoloPress = !otherKeysDuringFn
                let longEnough = fnPressTime.map {
                    Date().timeIntervalSince($0) >= debounceInterval
                } ?? false

                fnKeyDown = false
                otherKeysDuringFn = false
                fnPressTime = nil

                if wasSoloPress && longEnough {
                    onRecordingStopped?()
                } else {
                    onRecordingCancelled?()
                }
            }
        } else if fnKeyDown {
            // Another key pressed while Fn held — Fn is being used as modifier
            if !otherKeysDuringFn {
                otherKeysDuringFn = true
                onRecordingCancelled?()
            }
        }
    }
}

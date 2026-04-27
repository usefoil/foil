import ApplicationServices
import AppKit
import CoreGraphics
import Darwin
import Foundation

/// Thin wrapper around macOS SkyLight private framework APIs.
/// All raw dlsym / function-pointer work is confined here.
enum SkyLightBridge {

    // MARK: - Function pointer types

    private typealias PostEventRecordToFn =
        @convention(c) (UnsafeRawPointer, UnsafePointer<UInt8>) -> Int32
    private typealias GetFrontProcessFn =
        @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias GetProcessForPIDFn =
        @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    private typealias AXGetWindowFn =
        @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32

    // MARK: - Resolved symbols

    private static let skyLightHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    }()

    private static let postEventRecordToFn: PostEventRecordToFn? = {
        _ = skyLightHandle
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SLPSPostEventRecordTo") else { return nil }
        return unsafeBitCast(sym, to: PostEventRecordToFn.self)
    }()

    private static let getFrontProcessFn: GetFrontProcessFn? = {
        _ = skyLightHandle
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_SLPSGetFrontProcess") else { return nil }
        return unsafeBitCast(sym, to: GetFrontProcessFn.self)
    }()

    private static let getProcessForPIDFn: GetProcessForPIDFn? = {
        _ = skyLightHandle
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID") else { return nil }
        return unsafeBitCast(sym, to: GetProcessForPIDFn.self)
    }()

    private static let axGetWindowFn: AXGetWindowFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: AXGetWindowFn.self)
    }()

    // MARK: - Public API

    /// True when all three core SkyLight SPIs resolved.
    static var isAvailable: Bool {
        postEventRecordToFn != nil
            && getFrontProcessFn != nil
            && getProcessForPIDFn != nil
    }

    /// Focus a window without raising it (SkyLight event injection).
    /// Returns true on success.
    static func focusWithoutRaise(targetPid: pid_t, targetWindowID: CGWindowID) -> Bool {
        guard let postEvent = postEventRecordToFn,
              let getFront = getFrontProcessFn,
              let getForPID = getProcessForPIDFn else { return false }

        // Get current frontmost PSN (8 bytes)
        var prevPSN = [UInt8](repeating: 0, count: 8)
        guard getFront(&prevPSN) == 0 else { return false }

        // Get target PSN
        var targetPSN = [UInt8](repeating: 0, count: 8)
        guard getForPID(targetPid, &targetPSN) == 0 else { return false }

        // Build 0xF8 (248) byte event record
        var buf = [UInt8](repeating: 0, count: 0xF8)
        buf[0x04] = 0xF8  // opcode high
        buf[0x08] = 0x0D  // opcode low

        // Little-endian UInt32 of targetWindowID at offset 0x3C
        let wid = UInt32(targetWindowID)
        buf[0x3C] = UInt8(wid & 0xFF)
        buf[0x3D] = UInt8((wid >> 8) & 0xFF)
        buf[0x3E] = UInt8((wid >> 16) & 0xFF)
        buf[0x3F] = UInt8((wid >> 24) & 0xFF)

        // Defocus previous window
        buf[0x8A] = 0x02
        let r1 = prevPSN.withUnsafeBufferPointer { psnPtr in
            buf.withUnsafeBufferPointer { bufPtr in
                postEvent(UnsafeRawPointer(psnPtr.baseAddress!), bufPtr.baseAddress!)
            }
        }

        usleep(40_000) // 40ms empirical delay (from yabai)

        // Focus target window
        buf[0x8A] = 0x01
        let r2 = targetPSN.withUnsafeBufferPointer { psnPtr in
            buf.withUnsafeBufferPointer { bufPtr in
                postEvent(UnsafeRawPointer(psnPtr.baseAddress!), bufPtr.baseAddress!)
            }
        }

        return r1 == 0 && r2 == 0
    }

    /// Extract the CGWindowID from an AXUIElement, if possible.
    static func windowID(from element: AXUIElement) -> CGWindowID? {
        guard let axGetWindow = axGetWindowFn else { return nil }
        var wid: UInt32 = 0
        let result = axGetWindow(element, &wid)
        guard result == 0, wid != 0 else { return nil }
        return CGWindowID(wid)
    }

    /// Snapshot the currently focused window (pid + windowID).
    static func currentFocus() -> (pid: pid_t, windowID: CGWindowID)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        guard pid > 0 else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        guard axResult == .success, let windowElement = value else { return nil }

        // AXUIElement is a CFTypeRef — bridge to the typed version
        let axWindow = windowElement as! AXUIElement // swiftlint:disable:this force_cast
        guard let wid = windowID(from: axWindow) else { return nil }
        return (pid: pid, windowID: wid)
    }
}

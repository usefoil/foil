import ApplicationServices
import AppKit
import CoreGraphics

/// Captures the identity of the window that should receive a paste.
/// Stored at the moment the user triggers recording so that focus changes
/// during transcription don't redirect the paste to the wrong app.
struct PasteTarget {
    let windowElement: AXUIElement?
    let windowID: CGWindowID?
    let pid: pid_t
    let appName: String

    /// A target is valid when it refers to a real process.
    var isValid: Bool { pid > 0 }

    /// Captures the currently focused window and owning process.
    /// Returns nil when Accessibility permissions are not granted or no
    /// focused window can be determined.
    static func captureCurrentTarget() -> PasteTarget? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let pid = frontApp.processIdentifier
        guard pid > 0 else { return nil }

        let appName = frontApp.localizedName ?? ""
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        )

        let window: AXUIElement?
        if result == .success, let ref = windowRef {
            // swiftlint:disable:next force_cast
            window = (ref as! AXUIElement)
        } else {
            window = nil
        }

        let windowID = window.flatMap { SkyLightBridge.windowID(from: $0) }
        return PasteTarget(windowElement: window, windowID: windowID, pid: pid, appName: appName)
    }
}

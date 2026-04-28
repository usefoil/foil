import AppKit
import CoreGraphics
import Foundation

/// Tier 1 async paste: invisible background paste via SkyLight APIs.
/// Attempts focus-without-raise → CMD+V → restore focus.
/// Returns true on success, false if unavailable or failed (caller
/// should fall back to Tier 2: window choreography).
struct BackgroundPaste {
    static func attempt(
        text: String,
        target: PasteTarget,
        keepOnClipboard: Bool
    ) async -> Bool {
        // Gate: need SkyLight SPIs and a valid window ID
        guard SkyLightBridge.isAvailable,
              let targetWindowID = target.windowID,
              target.isValid
        else { return false }

        // Gate: target process must still be running
        guard let targetApp = NSRunningApplication(processIdentifier: target.pid),
              !targetApp.isTerminated
        else { return false }

        // Snapshot where the user is now (to restore after paste)
        guard let current = SkyLightBridge.currentFocus() else { return false }

        // Prepare clipboard
        let pasteboard = NSPasteboard.general
        let saved = keepOnClipboard ? [] : savePasteboardContents(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Focus target without raising
        let focused = SkyLightBridge.focusWithoutRaise(
            targetPid: target.pid, targetWindowID: targetWindowID
        )
        guard focused else {
            // Restore clipboard and bail
            if !keepOnClipboard { restorePasteboardContents(pasteboard, saved: saved) }
            return false
        }

        // Let AppKit state settle
        try? await Task.sleep(for: .milliseconds(50))

        // Send CMD+V to the target PID (prefer SkyLight auth-signed path)
        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            if !SkyLightBridge.postKeyEventViaSkyLight(to: target.pid, event: keyDown) {
                keyDown.postToPid(target.pid)
            }
            if !SkyLightBridge.postKeyEventViaSkyLight(to: target.pid, event: keyUp) {
                keyUp.postToPid(target.pid)
            }
        }

        // Let paste land
        try? await Task.sleep(for: .milliseconds(100))

        // Restore focus to where the user was
        SkyLightBridge.focusWithoutRaise(
            targetPid: current.pid, targetWindowID: current.windowID
        )

        // Restore clipboard
        if !keepOnClipboard {
            restorePasteboardContents(pasteboard, saved: saved)
        }

        return true
    }

    // MARK: - Clipboard save/restore

    private static func savePasteboardContents(
        _ pb: NSPasteboard
    ) -> [(NSPasteboard.PasteboardType, Data)] {
        var saved: [(NSPasteboard.PasteboardType, Data)] = []
        guard let items = pb.pasteboardItems else { return saved }
        for item in items {
            for type in item.types {
                if let data = item.data(forType: type) {
                    saved.append((type, data))
                }
            }
        }
        return saved
    }

    private static func restorePasteboardContents(
        _ pb: NSPasteboard,
        saved: [(NSPasteboard.PasteboardType, Data)]
    ) {
        pb.clearContents()
        guard !saved.isEmpty else { return }
        let item = NSPasteboardItem()
        for (type, data) in saved {
            item.setData(data, forType: type)
        }
        pb.writeObjects([item])
    }
}

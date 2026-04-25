import AppKit
import ApplicationServices
import CoreGraphics

struct TextInserter {
    func insert(text: String, keepOnClipboard: Bool = false) async {
        let pasteboard = NSPasteboard.general
        let saved = keepOnClipboard ? [] : savePasteboardContents(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulatePaste()

        try? await Task.sleep(for: .milliseconds(100))

        if !keepOnClipboard {
            restorePasteboardContents(pasteboard, saved: saved)
        }
    }

    /// Paste text into a previously captured target window, then return focus
    /// to wherever the user is currently working.
    ///
    /// Flow: snapshot current app → activate target → paste → reactivate current app.
    func insertAtTarget(text: String, target: PasteTarget, keepOnClipboard: Bool) async {
        // 1. Remember where the user is right now
        let currentApp = NSWorkspace.shared.frontmostApplication

        // 2. Activate the target app and raise the specific window
        guard let targetApp = NSRunningApplication(processIdentifier: target.pid),
              targetApp.isTerminated == false else {
            // Target app is gone — fall back to clipboard only
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return
        }

        targetApp.activate()

        if let window = target.windowElement {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }

        // 3. Wait for activation to settle
        try? await Task.sleep(for: .milliseconds(100))

        // 4. Paste using the existing mechanism
        await insert(text: text, keepOnClipboard: keepOnClipboard)

        // 5. Wait for paste to land
        try? await Task.sleep(for: .milliseconds(100))

        // 6. Return focus to where the user was
        currentApp?.activate()
    }

    private func savePasteboardContents(_ pb: NSPasteboard) -> [(NSPasteboard.PasteboardType, Data)] {
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

    private func restorePasteboardContents(
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

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        // 0x09 is the virtual key code for "V"
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

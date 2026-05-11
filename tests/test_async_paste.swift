#!/usr/bin/env swift
//
// Automated test for async paste mechanics.
// Opens two TextEdit windows, captures target A, waits (simulating transcription),
// switches to window B, then pastes into A and returns to B.
//
// Usage: swift test_async_paste.swift
// Requires: Accessibility permission for Terminal/Ghostty

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Helpers (copied from GroqTalk sources)

func captureCurrentTarget() -> (window: AXUIElement?, pid: pid_t, appName: String)? {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
    let pid = frontApp.processIdentifier
    let appName = frontApp.localizedName ?? "Unknown"

    let appElement = AXUIElementCreateApplication(pid)
    var windowRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)

    let window: AXUIElement?
    if result == .success, let ref = windowRef {
        window = (ref as! AXUIElement)
    } else {
        window = nil
    }

    return (window: window, pid: pid, appName: appName)
}

func simulatePaste() {
    let source = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    keyDown?.flags = .maskCommand
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

func pasteText(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
    simulatePaste()
}

func activateAndRaise(pid: pid_t, window: AXUIElement?) {
    guard let app = NSRunningApplication(processIdentifier: pid) else {
        print("  ERROR: No app for pid \(pid)")
        return
    }
    // Raise the specific window first, then activate the app.
    // This order ensures macOS brings the correct window to front.
    if let w = window {
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    }
    app.activate()
}

// MARK: - AX permission check

print("=== Async Paste Test ===")
print()

if !AXIsProcessTrusted() {
    print("ERROR: No Accessibility permission.")
    print("Grant it to your terminal in System Settings > Privacy & Security > Accessibility")
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(opts)
    exit(1)
}
print("✓ Accessibility permission granted")

// MARK: - Open two TextEdit windows

print()
print("Step 1: Opening two TextEdit windows...")

// Close existing TextEdit
let ws = NSWorkspace.shared
_ = Process.launchedProcess(launchPath: "/usr/bin/pkill", arguments: ["-x", "TextEdit"])
Thread.sleep(forTimeInterval: 2)

// Create two temp files
let fileA = FileManager.default.temporaryDirectory.appendingPathComponent("AsyncPasteTestA.txt")
let fileB = FileManager.default.temporaryDirectory.appendingPathComponent("AsyncPasteTestB.txt")
try! "Window A - target\n".write(to: fileA, atomically: true, encoding: .utf8)
try! "Window B - user is here\n".write(to: fileB, atomically: true, encoding: .utf8)

// Open both
ws.open(fileA)
Thread.sleep(forTimeInterval: 2)
ws.open(fileB)
Thread.sleep(forTimeInterval: 2)

print("✓ Two TextEdit windows open")

// MARK: - Step 2: Activate Window A and capture target

print()
print("Step 2: Focusing Window A and capturing target...")

// The most recent open should be B (frontmost). We need to find A.
// List TextEdit windows via AX
guard let textEditApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else {
    print("ERROR: TextEdit not running")
    exit(1)
}

let textEditPid = textEditApp.processIdentifier
let axApp = AXUIElementCreateApplication(textEditPid)

var windowList: CFTypeRef?
AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowList)

guard let windows = windowList as? [AXUIElement], windows.count >= 2 else {
    print("ERROR: Expected 2 TextEdit windows, got \((windowList as? [AXUIElement])?.count ?? 0)")
    exit(1)
}

// Figure out which window is A and which is B by checking titles
func windowTitle(_ w: AXUIElement) -> String {
    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &titleRef)
    return (titleRef as? String) ?? "unknown"
}

var windowA: AXUIElement?
var windowB: AXUIElement?
for w in windows {
    let title = windowTitle(w)
    print("  Found window: \(title)")
    if title.contains("AsyncPasteTestA") { windowA = w }
    if title.contains("AsyncPasteTestB") { windowB = w }
}

guard let wA = windowA, let wB = windowB else {
    print("ERROR: Could not identify windows A and B")
    exit(1)
}

// Activate window A and capture it as the paste target
AXUIElementPerformAction(wA, kAXRaiseAction as CFString)
textEditApp.activate()
Thread.sleep(forTimeInterval: 0.5)

// Capture target (should be window A)
guard let target = captureCurrentTarget() else {
    print("ERROR: Failed to capture target")
    exit(1)
}
print("✓ Captured target: \(target.appName) pid=\(target.pid)")
print("  Window element: \(target.window != nil ? "captured" : "nil")")

// MARK: - Step 3: Switch to Window B (simulate user moving away)

print()
print("Step 3: Switching to Window B (simulating user moving away)...")
AXUIElementPerformAction(wB, kAXRaiseAction as CFString)
Thread.sleep(forTimeInterval: 0.5)

// Verify B is now frontmost
if let front = captureCurrentTarget() {
    print("  Frontmost after switch: \(front.appName) (should still be TextEdit)")
}
print("✓ User is now in Window B")

// MARK: - Step 4: Simulate async transcription delay

print()
print("Step 4: Simulating 2-second transcription delay...")
Thread.sleep(forTimeInterval: 2.0)
print("✓ Transcription complete: 'ASYNC_PASTE_TEST_SUCCESS'")

// MARK: - Step 5: Async paste into target A, then return to B

print()
print("Step 5: Pasting into Window A (target) then returning to Window B...")

// Remember current app (Window B)
let currentApp = NSWorkspace.shared.frontmostApplication
print("  Current app before paste: \(currentApp?.localizedName ?? "nil")")

// Activate target
print("  Activating target (pid \(target.pid))...")
activateAndRaise(pid: target.pid, window: target.window)
Thread.sleep(forTimeInterval: 0.2)

// Verify we switched
if let front = NSWorkspace.shared.frontmostApplication {
    print("  Frontmost after activate: \(front.localizedName ?? "?")")
}

// Paste
print("  Pasting text...")
pasteText("ASYNC_PASTE_TEST_SUCCESS")
Thread.sleep(forTimeInterval: 0.5)

// Return focus
print("  Returning focus to Window B...")
if let wBElement = windowB {
    AXUIElementPerformAction(wBElement, kAXRaiseAction as CFString)
}
currentApp?.activate()
Thread.sleep(forTimeInterval: 0.3)

// Verify we returned
if let front = NSWorkspace.shared.frontmostApplication {
    print("  Frontmost after return: \(front.localizedName ?? "?")")
}

// MARK: - Step 6: Verify results

print()
print("Step 6: Verifying results...")

// Read window A contents via AX
func getWindowText(_ w: AXUIElement) -> String {
    // First raise the window
    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    textEditApp.activate()
    Thread.sleep(forTimeInterval: 0.3)

    // Get the text area from the window's children
    var childrenRef: CFTypeRef?
    AXUIElementCopyAttributeValue(w, kAXChildrenAttribute as CFString, &childrenRef)

    if let children = childrenRef as? [AXUIElement] {
        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            if let role = roleRef as? String {
                if role == "AXScrollArea" || role == "AXTextArea" {
                    // Look deeper for text area
                    var valueRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef)
                    if let value = valueRef as? String { return value }

                    // Check children of scroll area
                    var subChildrenRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &subChildrenRef)
                    if let subChildren = subChildrenRef as? [AXUIElement] {
                        for sub in subChildren {
                            AXUIElementCopyAttributeValue(sub, kAXValueAttribute as CFString, &valueRef)
                            if let value = valueRef as? String { return value }
                        }
                    }
                }
            }
        }
    }
    return "<could not read>"
}

let textA = getWindowText(wA)
let textB = getWindowText(wB)

print("  Window A contents: \(textA.prefix(100))")
print("  Window B contents: \(textB.prefix(100))")

// Return to B
AXUIElementPerformAction(wB, kAXRaiseAction as CFString)

print()
let passed: Bool
if textA.contains("ASYNC_PASTE_TEST_SUCCESS") && !textB.contains("ASYNC_PASTE_TEST_SUCCESS") {
    print("✅ SUCCESS: Text landed in Window A (target), not Window B (current)")
    passed = true
} else if textB.contains("ASYNC_PASTE_TEST_SUCCESS") {
    print("❌ FAIL: Text landed in Window B (current) instead of Window A (target)")
    passed = false
} else if textA.contains("ASYNC_PASTE_TEST_SUCCESS") && textB.contains("ASYNC_PASTE_TEST_SUCCESS") {
    print("❌ FAIL: Text landed in BOTH windows")
    passed = false
} else {
    print("❌ FAIL: Text not found in either window")
    passed = false
}

// Cleanup
print()
print("Cleaning up...")
try? FileManager.default.removeItem(at: fileA)
try? FileManager.default.removeItem(at: fileB)
print("Done.")
exit(passed ? 0 : 1)

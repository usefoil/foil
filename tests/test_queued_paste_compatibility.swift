#!/usr/bin/env swift
//
// Real-target queued paste compatibility smoke.
//
// This drives Foil's --automation-smoke hooks against disposable TextEdit and
// browser targets. It is visible desktop automation, not a headless test.

import AppKit
import ApplicationServices
import Foundation

let appBundleID = "com.neonwatty.Foil"
let appPath = "/Applications/Foil.app"
let queuedText = "Mock queued paste automation smoke"
let enqueueNotification = Notification.Name("com.neonwatty.Foil.automation.queuedEnqueue")
let deliverNotification = Notification.Name("com.neonwatty.Foil.automation.queuedDeliverNext")
let diagnosticLogURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Foil", isDirectory: true)
    .appendingPathComponent("Diagnostics", isDirectory: true)
    .appendingPathComponent("foil.log", isDirectory: false)
var diagnosticLogStartOffset: UInt64 = 0

struct SmokeResult {
    let name: String
    let passed: Bool
    let detail: String
}

func frontmostAppName() -> String {
    NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"
}

@discardableResult
func run(_ launchPath: String, _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ""
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func waitUntil(timeout: TimeInterval, poll: TimeInterval = 0.25, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        Thread.sleep(forTimeInterval: poll)
    }
    return condition()
}

func readDiagnosticLog() -> String {
    guard let handle = try? FileHandle(forReadingFrom: diagnosticLogURL) else { return "" }
    defer { try? handle.close() }
    let endOffset = (try? handle.seekToEnd()) ?? 0
    try? handle.seek(toOffset: min(diagnosticLogStartOffset, endOffset))
    let data = handle.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func markDiagnosticLogStart() {
    diagnosticLogStartOffset = ((try? diagnosticLogURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init)) ?? 0
}

func post(_ notification: Notification.Name) {
    DistributedNotificationCenter.default().postNotificationName(
        notification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
}

func windowTitle(_ element: AXUIElement) -> String {
    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    return titleRef as? String ?? ""
}

func windows(forBundleID bundleID: String) -> [AXUIElement] {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        return []
    }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var windowsRef: CFTypeRef?
    AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
    return windowsRef as? [AXUIElement] ?? []
}

func findAXElement(in element: AXUIElement, role wantedRole: String) -> AXUIElement? {
    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    if roleRef as? String == wantedRole { return element }

    var childrenRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    guard let children = childrenRef as? [AXUIElement] else { return nil }
    for child in children {
        if let found = findAXElement(in: child, role: wantedRole) {
            return found
        }
    }
    return nil
}

func axValue(_ element: AXUIElement) -> String {
    var valueRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
    return valueRef as? String ?? ""
}

func textValue(in window: AXUIElement) -> String {
    guard let textArea = findAXElement(in: window, role: "AXTextArea")
            ?? findAXElement(in: window, role: "AXTextField") else {
        return ""
    }
    return axValue(textArea)
}

func activateWindow(_ window: AXUIElement, app: NSRunningApplication) {
    app.activate()
    Thread.sleep(forTimeInterval: 0.2)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFTypeRef)
    AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)
    Thread.sleep(forTimeInterval: 0.5)
}

func switchToFinder() {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
    Thread.sleep(forTimeInterval: 0.5)
}

func launchFoil() -> Bool {
    run("/usr/bin/defaults", ["write", appBundleID, "queuedPasteEnabled", "-bool", "true"])
    run("/usr/bin/defaults", ["write", appBundleID, "asyncPasteEnabled", "-bool", "false"])
    run("/usr/bin/defaults", ["write", appBundleID, "keepOnClipboard", "-bool", "false"])
    run("/usr/bin/defaults", ["write", appBundleID, "showFloatingStatus", "-bool", "false"])
    run("/usr/bin/pkill", ["-x", "Foil"])
    Thread.sleep(forTimeInterval: 1.0)
    run("/usr/bin/open", ["-n", appPath, "--args", "--automation-smoke"])
    return waitUntil(timeout: 8) {
        NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).first != nil
            && readDiagnosticLog().contains("automation smoke: enabled")
    }
}

func enqueueAndDeliver(switchAwayBeforeDelivery: Bool = true) -> Bool {
    markDiagnosticLogStart()
    print("  Frontmost before enqueue: \(frontmostAppName())")
    post(enqueueNotification)
    let enqueued = waitUntil(timeout: 5) {
        let log = readDiagnosticLog()
        return log.contains("automation queued smoke: enqueued")
            && log.contains("QueuedPaste.enqueue: status=pending")
    }
    if switchAwayBeforeDelivery {
        switchToFinder()
    }
    print("  Frontmost before deliver: \(frontmostAppName())")
    post(deliverNotification)
    let delivered = waitUntil(timeout: 8) {
        readDiagnosticLog().contains("automation queued smoke: deliver next result=")
    }
    print("  Frontmost after deliver: \(frontmostAppName())")
    return enqueued && delivered
}

func testTextEdit() -> SmokeResult {
    run("/usr/bin/pkill", ["-x", "TextEdit"])
    Thread.sleep(forTimeInterval: 1.0)
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("FoilQueuedTextEditTarget.txt")
    try? "Foil queued TextEdit target\n".write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    NSWorkspace.shared.open(fileURL)
    Thread.sleep(forTimeInterval: 1.5)
    guard let textEdit = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else {
        return SmokeResult(name: "TextEdit queued delivery", passed: false, detail: "TextEdit did not launch")
    }
    guard let window = windows(forBundleID: "com.apple.TextEdit").first(where: { windowTitle($0).contains("FoilQueuedTextEditTarget") }) else {
        return SmokeResult(name: "TextEdit queued delivery", passed: false, detail: "Target window not found")
    }

    let title = windowTitle(window)
    activateWindow(window, app: textEdit)
    guard enqueueAndDeliver(switchAwayBeforeDelivery: false) else {
        return SmokeResult(name: "TextEdit queued delivery", passed: false, detail: "Queue enqueue/deliver notifications did not complete")
    }

    let pasted = waitUntil(timeout: 6) {
        activateWindow(window, app: textEdit)
        return textValue(in: window).contains(queuedText)
    }
    let detail = "target=TextEdit pid=\(textEdit.processIdentifier) title=\(title)"
    return SmokeResult(name: "TextEdit queued delivery", passed: pasted, detail: detail)
}

func testChrome() -> SmokeResult {
    let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    guard FileManager.default.fileExists(atPath: chromeURL.path) else {
        return SmokeResult(name: "Chrome queued delivery", passed: false, detail: "Google Chrome.app not found")
    }

    let htmlURL = FileManager.default.temporaryDirectory.appendingPathComponent("foil-queued-chrome-target.html")
    let html = """
    <!doctype html>
    <html><head><title>Foil Queued Chrome Target</title></head><body>
    <textarea id="target" autofocus style="width:600px;height:240px;">Chrome queued target
    </textarea>
    <script>
    setTimeout(() => {
      const t = document.getElementById('target');
      t.focus();
      t.setSelectionRange(t.value.length, t.value.length);
    }, 300);
    </script>
    </body></html>
    """
    try? html.write(to: htmlURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: htmlURL) }

    NSWorkspace.shared.open(
        [htmlURL],
        withApplicationAt: chromeURL,
        configuration: NSWorkspace.OpenConfiguration()
    )
    Thread.sleep(forTimeInterval: 2.5)
    guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else {
        return SmokeResult(name: "Chrome queued delivery", passed: false, detail: "Chrome did not launch")
    }
    chrome.activate()
    Thread.sleep(forTimeInterval: 1.0)
    guard let window = windows(forBundleID: "com.google.Chrome").first else {
        return SmokeResult(name: "Chrome queued delivery", passed: false, detail: "Chrome window not found")
    }
    let title = windowTitle(window)
    activateWindow(window, app: chrome)
    guard enqueueAndDeliver(switchAwayBeforeDelivery: false) else {
        return SmokeResult(name: "Chrome queued delivery", passed: false, detail: "Queue enqueue/deliver notifications did not complete")
    }

    let pasted = waitUntil(timeout: 6) {
        activateWindow(window, app: chrome)
        return textValue(in: window).contains(queuedText)
    }
    let detail = "target=Google Chrome pid=\(chrome.processIdentifier) title=\(title)"
    return SmokeResult(name: "Chrome queued delivery", passed: pasted, detail: detail)
}

func testUnavailableTargetFallback() -> SmokeResult {
    run("/usr/bin/pkill", ["-x", "TextEdit"])
    Thread.sleep(forTimeInterval: 1.0)
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("FoilQueuedClosedTarget.txt")
    try? "Foil queued closed target\n".write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    NSWorkspace.shared.open(fileURL)
    Thread.sleep(forTimeInterval: 1.5)
    guard let textEdit = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first,
          let window = windows(forBundleID: "com.apple.TextEdit").first(where: { windowTitle($0).contains("FoilQueuedClosedTarget") }) else {
        return SmokeResult(name: "Unavailable target fallback", passed: false, detail: "TextEdit fallback target not found")
    }

    let title = windowTitle(window)
    activateWindow(window, app: textEdit)
    post(enqueueNotification)
    guard waitUntil(timeout: 5, poll: 0.25, {
        readDiagnosticLog().contains("automation queued smoke: enqueued")
            && readDiagnosticLog().contains("QueuedPaste.enqueue: status=pending")
    }) else {
        return SmokeResult(name: "Unavailable target fallback", passed: false, detail: "Could not enqueue fallback target")
    }

    run("/usr/bin/pkill", ["-x", "TextEdit"])
    Thread.sleep(forTimeInterval: 1.0)
    post(deliverNotification)
    let fallback = waitUntil(timeout: 8) {
        let log = readDiagnosticLog()
        return log.contains("clipboardFallback")
            || log.contains("QueuedPaste.deliver: fallback")
            || log.contains("Target unavailable; text copied to clipboard")
    }
    let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
    let passed = fallback && clipboard.contains(queuedText)
    let detail = "captured=TextEdit pid=\(textEdit.processIdentifier) title=\(title) clipboardFallback=\(clipboard.contains(queuedText))"
    return SmokeResult(name: "Unavailable target fallback", passed: passed, detail: detail)
}

print("=== Queued Paste Compatibility Smoke ===")
print()

guard AXIsProcessTrusted() else {
    print("ERROR: Accessibility permission is required.")
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(opts)
    exit(1)
}

guard FileManager.default.fileExists(atPath: appPath) else {
    print("ERROR: \(appPath) not found. Run `make install` first.")
    exit(1)
}

try? FileManager.default.createDirectory(
    at: diagnosticLogURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
diagnosticLogStartOffset = ((try? diagnosticLogURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init)) ?? 0

guard launchFoil() else {
    print("ERROR: Foil automation smoke did not launch.")
    exit(1)
}

let results = [
    testTextEdit(),
    testChrome(),
    testUnavailableTargetFallback()
]

print()
print("Results:")
var failed = false
for result in results {
    if result.passed {
        print("✅ \(result.name): \(result.detail)")
    } else {
        failed = true
        print("❌ \(result.name): \(result.detail)")
    }
}

run("/usr/bin/pkill", ["-x", "Foil"])
exit(failed ? 1 : 0)

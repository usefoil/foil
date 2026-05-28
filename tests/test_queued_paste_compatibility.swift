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
    let status: Status
    let detail: String

    enum Status {
        case passed
        case failed
        case skipped
    }

    static func passed(name: String, detail: String) -> SmokeResult {
        SmokeResult(name: name, status: .passed, detail: detail)
    }

    static func failed(name: String, detail: String) -> SmokeResult {
        SmokeResult(name: name, status: .failed, detail: detail)
    }

    static func skipped(name: String, detail: String) -> SmokeResult {
        SmokeResult(name: name, status: .skipped, detail: detail)
    }
}

struct BrowserSmokeTarget {
    let name: String
    let bundleID: String
    let appPath: String
    let pageTitle: String
    let initialText: String
    let htmlFileName: String
    let required: Bool
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

func axRole(_ element: AXUIElement) -> String {
    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    return roleRef as? String ?? ""
}

func axValue(_ element: AXUIElement) -> String {
    var valueRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
    return valueRef as? String ?? ""
}

func textValues(in element: AXUIElement) -> [String] {
    let role = axRole(element)
    var values: [String] = []
    if role == "AXTextArea" || role == "AXTextField" {
        let value = axValue(element)
        if !value.isEmpty {
            values.append(value)
        }
    }

    var childrenRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    guard let children = childrenRef as? [AXUIElement] else { return values }
    for child in children {
        values.append(contentsOf: textValues(in: child))
    }
    return values
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
        return .failed(name: "TextEdit queued delivery", detail: "TextEdit did not launch")
    }
    guard let window = windows(forBundleID: "com.apple.TextEdit").first(where: { windowTitle($0).contains("FoilQueuedTextEditTarget") }) else {
        return .failed(name: "TextEdit queued delivery", detail: "Target window not found")
    }

    let title = windowTitle(window)
    activateWindow(window, app: textEdit)
    guard enqueueAndDeliver(switchAwayBeforeDelivery: false) else {
        return .failed(name: "TextEdit queued delivery", detail: "Queue enqueue/deliver notifications did not complete")
    }

    let pasted = waitUntil(timeout: 6) {
        activateWindow(window, app: textEdit)
        return textValue(in: window).contains(queuedText)
    }
    let detail = "target=TextEdit pid=\(textEdit.processIdentifier) title=\(title)"
    if pasted {
        return .passed(name: "TextEdit queued delivery", detail: detail)
    }
    return .failed(name: "TextEdit queued delivery", detail: detail)
}

func testBrowser(_ target: BrowserSmokeTarget) -> SmokeResult {
    let appURL = URL(fileURLWithPath: target.appPath)
    guard FileManager.default.fileExists(atPath: appURL.path) else {
        let detail = "\(target.name).app not found"
        return target.required
            ? .failed(name: "\(target.name) queued delivery", detail: detail)
            : .skipped(name: "\(target.name) queued delivery", detail: detail)
    }

    let htmlURL = FileManager.default.temporaryDirectory.appendingPathComponent(target.htmlFileName)
    let html = """
    <!doctype html>
    <html><head><title>\(target.pageTitle)</title></head><body>
    <textarea id="target" autofocus style="width:600px;height:240px;">\(target.initialText)
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
        withApplicationAt: appURL,
        configuration: NSWorkspace.OpenConfiguration()
    )
    var browser: NSRunningApplication?
    var browserWindows: [AXUIElement] = []
    let exposedTargetWindow = waitUntil(timeout: 10, poll: 0.5) {
        browser = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first
        browser?.activate()
        if browser != nil {
            browserWindows = windows(forBundleID: target.bundleID)
        }
        return browserWindows.contains(where: { windowTitle($0).contains(target.pageTitle) })
    }
    guard let browser else {
        let detail = "\(target.name) did not launch"
        return target.required
            ? .failed(name: "\(target.name) queued delivery", detail: detail)
            : .skipped(name: "\(target.name) queued delivery", detail: detail)
    }
    Thread.sleep(forTimeInterval: 1.0)
    guard exposedTargetWindow,
          let window = browserWindows.first(where: { windowTitle($0).contains(target.pageTitle) }) else {
        let titles = browserWindows.map(windowTitle).filter { !$0.isEmpty }.joined(separator: " | ")
        let detail = "\(target.name) target page window not found titles=\(titles.isEmpty ? "none" : titles)"
        return target.required
            ? .failed(name: "\(target.name) queued delivery", detail: detail)
            : .skipped(name: "\(target.name) queued delivery", detail: detail)
    }
    let title = windowTitle(window)
    activateWindow(window, app: browser)
    guard enqueueAndDeliver(switchAwayBeforeDelivery: false) else {
        return .failed(name: "\(target.name) queued delivery", detail: "Queue enqueue/deliver notifications did not complete")
    }

    let pasted = waitUntil(timeout: 6) {
        activateWindow(window, app: browser)
        return textValues(in: window).contains(where: { $0.contains(queuedText) })
    }
    var detail = "target=\(target.name) pid=\(browser.processIdentifier) title=\(title) noTabClose=true"
    if !pasted {
        let observed = textValues(in: window)
            .map { $0.replacingOccurrences(of: "\n", with: "\\n") }
            .filter { !$0.isEmpty }
            .prefix(3)
            .joined(separator: " | ")
        detail += " observedTextControls=\(observed.isEmpty ? "none" : observed)"
    }
    if pasted {
        return .passed(name: "\(target.name) queued delivery", detail: detail)
    }
    return .failed(name: "\(target.name) queued delivery", detail: detail)
}

func testChrome() -> SmokeResult {
    testBrowser(BrowserSmokeTarget(
        name: "Google Chrome",
        bundleID: "com.google.Chrome",
        appPath: "/Applications/Google Chrome.app",
        pageTitle: "Foil Queued Chrome Target",
        initialText: "Chrome queued target",
        htmlFileName: "foil-queued-chrome-target.html",
        required: true
    ))
}

func testFirefox() -> SmokeResult {
    testBrowser(BrowserSmokeTarget(
        name: "Firefox",
        bundleID: "org.mozilla.firefox",
        appPath: "/Applications/Firefox.app",
        pageTitle: "Foil Queued Firefox Target",
        initialText: "Firefox queued target",
        htmlFileName: "foil-queued-firefox-target.html",
        required: false
    ))
}

func testSafari() -> SmokeResult {
    testBrowser(BrowserSmokeTarget(
        name: "Safari",
        bundleID: "com.apple.Safari",
        appPath: "/Applications/Safari.app",
        pageTitle: "Foil Queued Safari Target",
        initialText: "Safari queued target",
        htmlFileName: "foil-queued-safari-target.html",
        required: false
    ))
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
        return .failed(name: "Unavailable target fallback", detail: "TextEdit fallback target not found")
    }

    let title = windowTitle(window)
    activateWindow(window, app: textEdit)
    post(enqueueNotification)
    guard waitUntil(timeout: 5, poll: 0.25, {
        readDiagnosticLog().contains("automation queued smoke: enqueued")
            && readDiagnosticLog().contains("QueuedPaste.enqueue: status=pending")
    }) else {
        return .failed(name: "Unavailable target fallback", detail: "Could not enqueue fallback target")
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
    let detail = "captured=TextEdit pid=\(textEdit.processIdentifier) title=\(title) clipboardFallback=\(clipboard.contains(queuedText)) recovery=\"Target unavailable; text copied to clipboard\""
    if passed {
        return .passed(name: "Unavailable target fallback", detail: detail)
    }
    return .failed(name: "Unavailable target fallback", detail: detail)
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
    testFirefox(),
    testSafari(),
    testUnavailableTargetFallback()
]

print()
print("Results:")
var failed = false
for result in results {
    switch result.status {
    case .passed:
        print("✅ \(result.name): \(result.detail)")
    case .skipped:
        print("⚠️  \(result.name): \(result.detail)")
    case .failed:
        failed = true
        print("❌ \(result.name): \(result.detail)")
    }
}

run("/usr/bin/pkill", ["-x", "Foil"])
exit(failed ? 1 : 0)

#!/usr/bin/env swift
//
// Real-target queued paste compatibility smoke.
//
// This uses Foil's --automation-smoke enqueue hook against disposable TextEdit
// and browser targets, then triggers user-facing queued delivery through the
// global queued-paste hotkey. It is visible desktop automation, not a headless
// test.

import AppKit
import ApplicationServices
import Foundation
import Network

let appBundleID = "com.neonwatty.Foil"
let appPath = "/Applications/Foil.app"
let queuedText = "Mock queued paste automation smoke"
let enqueueNotification = Notification.Name("com.neonwatty.Foil.automation.queuedEnqueue")
let queuedPasteDeliveryShortcutName = "Control-Shift-V"
let queuedPasteDeliveryKeyCode = CGKeyCode(0x09) // ANSI V
let queuedPasteDeliveryFlags: CGEventFlags = [.maskControl, .maskShift]
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
    let executablePath: String?
    let launchArguments: [String]
    let pageTitle: String
    let initialText: String
    let htmlFileName: String
    let required: Bool
    let privateBrowsingRequested: Bool
}

final class LocalHTTPServer {
    private let root: URL
    private let listener: NWListener
    private let queue = DispatchQueue(label: "foil.queued-paste.local-http")
    private let ready = DispatchSemaphore(value: 0)
    private var startError: Error?

    init(root: URL) throws {
        self.root = root
        self.listener = try NWListener(using: .tcp, on: .any)
    }

    func start(timeout: TimeInterval = 2) -> UInt16? {
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.ready.signal()
            case .failed(let error):
                self?.startError = error
                self?.ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)

        let deadline = DispatchTime.now() + .milliseconds(Int(timeout * 1000))
        guard ready.wait(timeout: deadline) == .success,
              startError == nil,
              let port = listener.port?.rawValue else {
            return nil
        }
        return port
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let requestLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = requestLine.split(separator: " ")
            let rawPath = parts.count > 1 ? String(parts[1]) : "/"
            let pathWithoutQuery = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
            let decodedPath = pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery
            let fileName = URL(fileURLWithPath: decodedPath).lastPathComponent.isEmpty
                ? "index.html"
                : URL(fileURLWithPath: decodedPath).lastPathComponent
            let fileURL = self.root.appendingPathComponent(fileName, isDirectory: false)

            let statusLine: String
            let body: Data
            if let fileData = try? Data(contentsOf: fileURL) {
                statusLine = "HTTP/1.1 200 OK"
                body = fileData
            } else {
                statusLine = "HTTP/1.1 404 Not Found"
                body = Data("Not found".utf8)
            }

            let header = "\(statusLine)\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            var response = Data(header.utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
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

func launch(_ launchPath: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
}

func jsStringLiteral(_ value: String) -> String {
    var escaped = ""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\\":
            escaped += "\\\\"
        case "\"":
            escaped += "\\\""
        case "\n":
            escaped += "\\n"
        case "\r":
            escaped += "\\r"
        default:
            escaped.append(Character(scalar))
        }
    }
    return "\"\(escaped)\""
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

func postQueuedPasteDeliveryHotkey() {
    let source = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: queuedPasteDeliveryKeyCode, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: queuedPasteDeliveryKeyCode, keyDown: false)
    keyDown?.flags = queuedPasteDeliveryFlags
    keyUp?.flags = queuedPasteDeliveryFlags
    keyDown?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
    keyUp?.post(tap: .cghidEventTap)
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

func enqueueAndDeliver(switchAwayBeforeDelivery: Bool = true) -> (success: Bool, detail: String) {
    markDiagnosticLogStart()
    print("  Frontmost before enqueue: \(frontmostAppName())")
    post(enqueueNotification)
    let enqueued = waitUntil(timeout: 5) {
        let log = readDiagnosticLog()
        return log.contains("automation queued smoke: enqueued")
            && log.contains("QueuedPaste.enqueue: status=pending")
    }
    guard enqueued else {
        return (false, "enqueue notification was not observed")
    }
    if switchAwayBeforeDelivery {
        switchToFinder()
    }
    print("  Frontmost before deliver: \(frontmostAppName())")
    postQueuedPasteDeliveryHotkey()
    let hotkeyObserved = waitUntil(timeout: 4) {
        readDiagnosticLog().contains("QueuedPaste.hotkey: deliverNext shortcut=\(queuedPasteDeliveryShortcutName)")
    }
    guard hotkeyObserved else {
        print("  Frontmost after deliver: \(frontmostAppName())")
        return (false, "enqueued item, but queued-paste delivery hotkey was not observed")
    }
    let delivered = waitUntil(timeout: 8) {
        let log = readDiagnosticLog()
        return log.contains("QueuedPaste.deliver: pasted")
            || log.contains("QueuedPaste.deliver: fallback")
    }
    print("  Frontmost after deliver: \(frontmostAppName())")
    guard delivered else {
        return (false, "hotkey was observed, but queued delivery did not complete")
    }
    return (true, "enqueue, hotkey, and delivery notifications completed")
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
    let delivery = enqueueAndDeliver(switchAwayBeforeDelivery: false)
    guard delivery.success else {
        return .failed(name: "TextEdit queued delivery", detail: delivery.detail)
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

    let existingProcessID = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first?.processIdentifier
    let serverRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("foil-queued-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: serverRoot, withIntermediateDirectories: true)
    } catch {
        let detail = "Could not create localhost target directory: \(error)"
        return target.required
            ? .failed(name: "\(target.name) queued delivery", detail: detail)
            : .skipped(name: "\(target.name) queued delivery", detail: detail)
    }
    defer { try? FileManager.default.removeItem(at: serverRoot) }

    let htmlURL = serverRoot.appendingPathComponent(target.htmlFileName)
    let pastedTitle = "\(target.pageTitle) Pasted"
    let html = """
    <!doctype html>
    <html><head><title>\(target.pageTitle)</title></head><body>
    <textarea id="target" autofocus style="width:600px;height:240px;">\(target.initialText)
    </textarea>
    <script>
    const queuedText = \(jsStringLiteral(queuedText));
    const pastedTitle = \(jsStringLiteral(pastedTitle));
    function updateTitleIfPasted() {
      const t = document.getElementById('target');
      if (t.value.includes(queuedText)) {
        document.title = pastedTitle;
      }
    }
    setTimeout(() => {
      const t = document.getElementById('target');
      t.focus();
      t.setSelectionRange(t.value.length, t.value.length);
    }, 300);
    document.getElementById('target').addEventListener('input', updateTitleIfPasted);
    setInterval(updateTitleIfPasted, 250);
    </script>
    </body></html>
    """
    try? html.write(to: htmlURL, atomically: true, encoding: .utf8)

    let server: LocalHTTPServer
    do {
        server = try LocalHTTPServer(root: serverRoot)
    } catch {
        let detail = "Could not create localhost server: \(error)"
        return target.required
            ? .failed(name: "\(target.name) queued delivery", detail: detail)
            : .skipped(name: "\(target.name) queued delivery", detail: detail)
    }
    guard let port = server.start(),
          let pageURL = URL(string: "http://127.0.0.1:\(port)/\(target.htmlFileName)") else {
        let detail = "Could not start localhost target server"
        return target.required
            ? .failed(name: "\(target.name) queued delivery", detail: detail)
            : .skipped(name: "\(target.name) queued delivery", detail: detail)
    }
    defer { server.stop() }

    if let executablePath = target.executablePath,
       FileManager.default.fileExists(atPath: executablePath),
       !target.launchArguments.isEmpty {
        launch(executablePath, target.launchArguments + [pageURL.absoluteString])
    } else {
        NSWorkspace.shared.open(
            [pageURL],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
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
    let delivery = enqueueAndDeliver(switchAwayBeforeDelivery: false)
    guard delivery.success else {
        return .failed(name: "\(target.name) queued delivery", detail: delivery.detail)
    }

    let pasted = waitUntil(timeout: 6) {
        activateWindow(window, app: browser)
        return textValues(in: window).contains(where: { $0.contains(queuedText) })
            || windowTitle(window).contains(pastedTitle)
    }
    let reusedProcess = existingProcessID == browser.processIdentifier
    let privateMode = target.privateBrowsingRequested ? "requested" : "notRequested"
    var detail = "target=\(target.name) pid=\(browser.processIdentifier) title=\(title) transport=localhost privateMode=\(privateMode) reusedExistingProcess=\(reusedProcess) noTabClose=true noUserBrowserQuit=true"
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
        executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        launchArguments: ["--incognito", "--new-window"],
        pageTitle: "Foil Queued Chrome Target",
        initialText: "Chrome queued target",
        htmlFileName: "foil-queued-chrome-target.html",
        required: true,
        privateBrowsingRequested: true
    ))
}

func testFirefox() -> SmokeResult {
    testBrowser(BrowserSmokeTarget(
        name: "Firefox",
        bundleID: "org.mozilla.firefox",
        appPath: "/Applications/Firefox.app",
        executablePath: "/Applications/Firefox.app/Contents/MacOS/firefox",
        launchArguments: ["--private-window"],
        pageTitle: "Foil Queued Firefox Target",
        initialText: "Firefox queued target",
        htmlFileName: "foil-queued-firefox-target.html",
        required: false,
        privateBrowsingRequested: true
    ))
}

func testSafari() -> SmokeResult {
    testBrowser(BrowserSmokeTarget(
        name: "Safari",
        bundleID: "com.apple.Safari",
        appPath: "/Applications/Safari.app",
        executablePath: nil,
        launchArguments: [],
        pageTitle: "Foil Queued Safari Target",
        initialText: "Safari queued target",
        htmlFileName: "foil-queued-safari-target.html",
        required: false,
        privateBrowsingRequested: false
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
    postQueuedPasteDeliveryHotkey()
    let hotkeyObserved = waitUntil(timeout: 4) {
        readDiagnosticLog().contains("QueuedPaste.hotkey: deliverNext shortcut=\(queuedPasteDeliveryShortcutName)")
    }
    let fallback = hotkeyObserved && waitUntil(timeout: 8) {
        let log = readDiagnosticLog()
        return log.contains("clipboardFallback")
            || log.contains("QueuedPaste.deliver: fallback")
            || log.contains("Target unavailable; text copied to clipboard")
    }
    let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
    let passed = fallback && clipboard.contains(queuedText)
    let deliveryDetail = hotkeyObserved ? "hotkeyObserved=true" : "hotkeyObserved=false"
    let detail = "captured=TextEdit pid=\(textEdit.processIdentifier) title=\(title) \(deliveryDetail) clipboardFallback=\(clipboard.contains(queuedText)) recovery=\"Target unavailable; text copied to clipboard\""
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

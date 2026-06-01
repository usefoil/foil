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

func frontmostAppDescription() -> String {
    guard let app = NSWorkspace.shared.frontmostApplication else { return "nil" }
    let name = app.localizedName ?? "unknown"
    let bundle = app.bundleIdentifier ?? "unknown"
    return "\(name) bundle=\(bundle) pid=\(app.processIdentifier)"
}

func failIfSecurityAgentFrontmost(stage: String) -> SmokeResult? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    if app.localizedName == "SecurityAgent" || app.bundleIdentifier == "com.apple.SecurityAgent" {
        return .failed(
            name: "SecurityAgent prompt",
            detail: "SecurityAgent frontmost during \(stage); a macOS keychain/security prompt is blocking installed-app automation. Handle the prompt manually, quit Foil, and rerun. frontmost=\(frontmostAppDescription())"
        )
    }
    return nil
}

func requireFrontmost(bundleID expectedBundleID: String, stage: String) -> SmokeResult? {
    if let result = failIfSecurityAgentFrontmost(stage: stage) {
        return result
    }
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == expectedBundleID else {
        return .failed(
            name: "Frontmost target",
            detail: "Expected \(expectedBundleID) frontmost during \(stage), got \(frontmostAppDescription())"
        )
    }
    return nil
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

func osascript(_ source: String) {
    _ = run("/usr/bin/osascript", ["-e", source])
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

func runningFoilProcessSummary() -> String {
    let output = run("/bin/ps", ["-axo", "pid=,stat=,rss=,vsz=,command="])
    let lines = output
        .split(separator: "\n")
        .map(String.init)
        .filter { $0.contains("/Applications/Foil.app/Contents/MacOS/Foil") }
    return lines.isEmpty ? "none" : lines.joined(separator: "\n")
}

func appExtendedAttributesSummary() -> String {
    let output = run("/usr/bin/xattr", ["-l", appPath])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return output.isEmpty ? "none" : output
}

func printFoilLaunchDiagnosticFailure() {
    print("ERROR: Foil launched as a process but did not reach automation smoke mode.")
    print("Expected diagnostics after launch to contain `automation smoke: enabled`.")
    print("This usually means the installed /Applications bundle is blocked before app code runs, for example by Gatekeeper/quarantine/syspolicyd state.")
    print()
    print("Foil process summary:")
    print(runningFoilProcessSummary())
    print()
    print("Foil.app extended attributes:")
    print(appExtendedAttributesSummary())
    print()
    print("Check system policy logs with:")
    print("/usr/bin/log show --style compact --last 10m --predicate '(process CONTAINS[c] \"syspolicyd\") OR (eventMessage CONTAINS[c] \"Foil\")'")
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

func axPoint(_ element: AXUIElement, attribute: String) -> CGPoint? {
    var valueRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
          let value = valueRef else {
        return nil
    }
    var point = CGPoint.zero
    guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
    return point
}

func axSize(_ element: AXUIElement, attribute: String) -> CGSize? {
    var valueRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
          let value = valueRef else {
        return nil
    }
    var size = CGSize.zero
    guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
    return size
}

func clickScreenPoint(_ point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
    mouseDown?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
    mouseUp?.post(tap: .cghidEventTap)
}

func activateWindow(_ window: AXUIElement, app: NSRunningApplication) {
    app.activate(options: [.activateAllWindows])
    if let bundleID = app.bundleIdentifier {
        osascript("tell application id \"\(bundleID)\" to activate")
    }
    Thread.sleep(forTimeInterval: 0.2)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFTypeRef)
    AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)
    Thread.sleep(forTimeInterval: 0.5)
}

func focusBrowserTextArea(in window: AXUIElement, app: NSRunningApplication) {
    activateWindow(window, app: app)
    guard let origin = axPoint(window, attribute: kAXPositionAttribute as String),
          let size = axSize(window, attribute: kAXSizeAttribute as String) else {
        return
    }

    // The smoke page puts a large textarea at the top-left of the document.
    // Browser AX trees do not expose that textarea consistently, especially
    // Firefox, so click into the page content before capturing/delivering.
    let x = origin.x + min(140, max(40, size.width * 0.2))
    let y = origin.y + min(190, max(120, size.height * 0.25))
    clickScreenPoint(CGPoint(x: x, y: y))
    Thread.sleep(forTimeInterval: 0.4)
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
    let processStarted = waitUntil(timeout: 8) {
        if failIfSecurityAgentFrontmost(stage: "Foil launch") != nil {
            return false
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).first != nil
    }
    guard processStarted else {
        return false
    }
    return waitUntil(timeout: 8) {
        if failIfSecurityAgentFrontmost(stage: "Foil automation smoke startup") != nil {
            return false
        }
        return readDiagnosticLog().contains("automation smoke: enabled")
    }
}

func enqueueAndDeliver(switchAwayBeforeDelivery: Bool = true) -> (success: Bool, detail: String) {
    markDiagnosticLogStart()
    print("  Frontmost before enqueue: \(frontmostAppName())")
    if let result = failIfSecurityAgentFrontmost(stage: "before enqueue") {
        return (false, result.detail)
    }
    post(enqueueNotification)
    let enqueued = waitUntil(timeout: 5) {
        if failIfSecurityAgentFrontmost(stage: "waiting for enqueue") != nil {
            return false
        }
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
    if let result = failIfSecurityAgentFrontmost(stage: "before deliver") {
        return (false, result.detail)
    }
    postQueuedPasteDeliveryHotkey()
    let hotkeyObserved = waitUntil(timeout: 4) {
        if failIfSecurityAgentFrontmost(stage: "waiting for delivery hotkey") != nil {
            return false
        }
        return readDiagnosticLog().contains("QueuedPaste.hotkey: deliverNext shortcut=\(queuedPasteDeliveryShortcutName)")
    }
    guard hotkeyObserved else {
        print("  Frontmost after deliver: \(frontmostAppName())")
        return (false, "enqueued item, but queued-paste delivery hotkey was not observed")
    }
    let delivered = waitUntil(timeout: 8) {
        if failIfSecurityAgentFrontmost(stage: "waiting for delivery completion") != nil {
            return false
        }
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
    if let result = requireFrontmost(bundleID: "com.apple.TextEdit", stage: "TextEdit enqueue") {
        return result
    }
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

    var launchArguments = target.launchArguments
    var dedicatedBrowserProfile = false
    if target.bundleID == "org.mozilla.firefox" {
        let profileURL = serverRoot.appendingPathComponent("firefox-automation-profile", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
            let prefs = """
            user_pref("app.normandy.first_run", false);
            user_pref("browser.aboutwelcome.enabled", false);
            user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
            user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
            user_pref("browser.shell.checkDefaultBrowser", false);
            user_pref("browser.startup.firstrunSkipsHomepage", false);
            user_pref("browser.startup.homepage_override.mstone", "ignore");
            user_pref("browser.startup.homepage_welcome_url", "");
            user_pref("browser.startup.homepage_welcome_url.additional", "");
            user_pref("datareporting.policy.dataSubmissionPolicyAcceptedVersion", 2);
            user_pref("datareporting.healthreport.uploadEnabled", false);
            user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
            user_pref("datareporting.policy.dataSubmissionEnabled", false);
            user_pref("datareporting.policy.firstRunURL", "");
            user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
            user_pref("toolkit.telemetry.enabled", false);
            user_pref("toolkit.telemetry.unified", false);
            """
            try prefs.write(to: profileURL.appendingPathComponent("user.js"), atomically: true, encoding: .utf8)
            launchArguments = ["--no-remote", "--profile", profileURL.path] + target.launchArguments
            dedicatedBrowserProfile = true
        } catch {
            let detail = "Could not create Firefox automation profile: \(error)"
            return target.required
                ? .failed(name: "\(target.name) queued delivery", detail: detail)
                : .skipped(name: "\(target.name) queued delivery", detail: detail)
        }
    }

    if let executablePath = target.executablePath,
       FileManager.default.fileExists(atPath: executablePath),
       !launchArguments.isEmpty {
        launch(executablePath, launchArguments + [pageURL.absoluteString])
    } else {
        NSWorkspace.shared.open(
            [pageURL],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
    var browser: NSRunningApplication?
    defer {
        if dedicatedBrowserProfile {
            browser?.terminate()
        }
    }
    var browserWindows: [AXUIElement] = []
    let exposedTargetWindow = waitUntil(timeout: 10, poll: 0.5) {
        browser = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first
        if let browser {
            browser.activate(options: [.activateAllWindows])
            osascript("tell application id \"\(target.bundleID)\" to activate")
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
    focusBrowserTextArea(in: window, app: browser)
    if let result = requireFrontmost(bundleID: target.bundleID, stage: "\(target.name) enqueue") {
        return result
    }
    let delivery = enqueueAndDeliver(switchAwayBeforeDelivery: false)
    guard delivery.success else {
        return .failed(name: "\(target.name) queued delivery", detail: delivery.detail)
    }

    let pasted = waitUntil(timeout: 6) {
        focusBrowserTextArea(in: window, app: browser)
        return textValues(in: window).contains(where: { $0.contains(queuedText) })
            || windowTitle(window).contains(pastedTitle)
    }
    let reusedProcess = existingProcessID == browser.processIdentifier
    let privateMode = target.privateBrowsingRequested ? "requested" : "notRequested"
    let dedicatedProfile = dedicatedBrowserProfile ? "true" : "false"
    var detail = "target=\(target.name) pid=\(browser.processIdentifier) title=\(title) transport=localhost privateMode=\(privateMode) reusedExistingProcess=\(reusedProcess) dedicatedProfile=\(dedicatedProfile) noTabClose=true noUserBrowserQuit=true"
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
    if let result = requireFrontmost(bundleID: "com.apple.TextEdit", stage: "unavailable target enqueue") {
        return result
    }
    post(enqueueNotification)
    guard waitUntil(timeout: 5, poll: 0.25, {
        if failIfSecurityAgentFrontmost(stage: "waiting for unavailable-target enqueue") != nil {
            return false
        }
        return readDiagnosticLog().contains("automation queued smoke: enqueued")
            && readDiagnosticLog().contains("QueuedPaste.enqueue: status=pending")
    }) else {
        return .failed(name: "Unavailable target fallback", detail: "Could not enqueue fallback target")
    }

    run("/usr/bin/pkill", ["-x", "TextEdit"])
    Thread.sleep(forTimeInterval: 1.0)
    if let result = failIfSecurityAgentFrontmost(stage: "before unavailable-target deliver") {
        return result
    }
    postQueuedPasteDeliveryHotkey()
    let hotkeyObserved = waitUntil(timeout: 4) {
        if failIfSecurityAgentFrontmost(stage: "waiting for unavailable-target hotkey") != nil {
            return false
        }
        return readDiagnosticLog().contains("QueuedPaste.hotkey: deliverNext shortcut=\(queuedPasteDeliveryShortcutName)")
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
    if let result = failIfSecurityAgentFrontmost(stage: "Foil launch") {
        print("❌ \(result.name): \(result.detail)")
    } else if NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).first != nil {
        printFoilLaunchDiagnosticFailure()
    } else {
        print("ERROR: Foil automation smoke did not launch.")
    }
    exit(1)
}

if let result = failIfSecurityAgentFrontmost(stage: "after Foil launch") {
    print("❌ \(result.name): \(result.detail)")
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

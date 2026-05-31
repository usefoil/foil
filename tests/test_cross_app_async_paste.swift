#!/usr/bin/env swift
//
// Cross-app desktop automation for async paste mechanics.
//
// This is not headless: it drives the active macOS desktop session via
// Accessibility, pasteboard, and app automation.

import AppKit
import ApplicationServices
import Foundation
import Network

struct PasteTarget {
    let window: AXUIElement?
    let pid: pid_t
    let appName: String
}

struct TestResult {
    let name: String
    let status: Status
    let detail: String

    enum Status {
        case passed
        case failed
        case skipped
    }
}

final class LocalHTTPServer {
    private let root: URL
    private let listener: NWListener
    private let queue = DispatchQueue(label: "foil.cross-app.local-http")
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

        guard ready.wait(timeout: .now() + .milliseconds(Int(timeout * 1000))) == .success,
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

func osascript(_ source: String) -> String {
    run("/usr/bin/osascript", ["-e", source])
}

func activateApplication(bundleID: String) {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .first?
        .activate(options: [.activateAllWindows])
    _ = osascript("tell application id \"\(bundleID)\" to activate")
}

func launch(_ launchPath: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
}

func captureCurrentTarget() -> PasteTarget? {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
    let pid = frontApp.processIdentifier
    let appName = frontApp.localizedName ?? "Unknown"
    let appElement = AXUIElementCreateApplication(pid)
    var windowRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
        appElement,
        kAXFocusedWindowAttribute as CFString,
        &windowRef
    )
    let window = (result == .success && windowRef != nil) ? (windowRef as! AXUIElement) : nil
    return PasteTarget(window: window, pid: pid, appName: appName)
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
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    simulatePaste()
}

func activateAndRaise(_ target: PasteTarget) {
    if let window = target.window {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFTypeRef)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)
    }
    if let app = NSRunningApplication(processIdentifier: target.pid) {
        app.activate(options: [.activateAllWindows])
        if let bundleID = app.bundleIdentifier {
            activateApplication(bundleID: bundleID)
        }
    }
}

func switchToFinder() {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
    Thread.sleep(forTimeInterval: 0.8)
}

func pasteIntoCapturedTarget(_ target: PasteTarget, text: String) -> String? {
    let currentApp = NSWorkspace.shared.frontmostApplication
    activateAndRaise(target)
    Thread.sleep(forTimeInterval: 0.4)
    pasteText(text)
    Thread.sleep(forTimeInterval: 0.6)
    currentApp?.activate()
    Thread.sleep(forTimeInterval: 0.4)
    return NSWorkspace.shared.frontmostApplication?.localizedName
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

func windowTitle(_ element: AXUIElement) -> String {
    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    return titleRef as? String ?? ""
}

func testTerminal() -> TestResult {
    guard FileManager.default.fileExists(atPath: "/System/Applications/Utilities/Terminal.app") ||
            FileManager.default.fileExists(atPath: "/Applications/Terminal.app") else {
        return TestResult(name: "Terminal", status: .skipped, detail: "Terminal.app not found")
    }

    let text = "FOIL_TERMINAL_ASYNC_PASTE"
    _ = osascript("""
    tell application "Terminal"
      activate
      do script "printf 'Foil Terminal target\\\\n'; read pasted_value; printf '\\\\nPASTED:%s\\\\n' \\"$pasted_value\\"; sleep 3"
    end tell
    """)
    Thread.sleep(forTimeInterval: 1.5)

    guard let target = captureCurrentTarget(), target.appName == "Terminal" else {
        return TestResult(name: "Terminal", status: .failed, detail: "Could not capture Terminal target")
    }

    switchToFinder()
    let frontAfterPaste = pasteIntoCapturedTarget(target, text: text + "\n")
    Thread.sleep(forTimeInterval: 1.0)

    let contents = osascript("""
    tell application "Terminal"
      set outputText to contents of selected tab of front window
      try
        close front window
      end try
      return outputText
    end tell
    """)

    if contents.contains("PASTED:\(text)") {
        return TestResult(name: "Terminal", status: .passed, detail: "Text reached captured terminal; frontmost after paste: \(frontAfterPaste ?? "unknown")")
    }
    return TestResult(name: "Terminal", status: .failed, detail: "Pasted text not found in Terminal output")
}

func testChrome() -> TestResult {
    let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    guard FileManager.default.fileExists(atPath: chromeURL.path) else {
        return TestResult(name: "Chrome", status: .skipped, detail: "Google Chrome.app not found")
    }

    let text = "FOIL_CHROME_ASYNC_PASTE"
    let serverRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("foil-cross-app-chrome-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: serverRoot, withIntermediateDirectories: true)
    } catch {
        return TestResult(name: "Chrome", status: .failed, detail: "Could not create localhost target directory: \(error)")
    }
    defer { try? FileManager.default.removeItem(at: serverRoot) }

    let htmlURL = serverRoot.appendingPathComponent("foil-chrome-paste-test.html")
    let pastedTitle = "Foil Cross-App Chrome Target Pasted"
    let html = """
    <!doctype html>
    <html><head><title>Foil Cross-App Chrome Target</title></head><body>
    <textarea id="target" autofocus style="width:600px;height:240px;">Chrome target
    </textarea>
    <script>
    const pastedText = "\(text)";
    setTimeout(() => {
      const t = document.getElementById('target');
      t.focus();
      t.setSelectionRange(t.value.length, t.value.length);
    }, 300);
    function updateTitleIfPasted() {
      const t = document.getElementById('target');
      if (t.value.includes(pastedText)) {
        document.title = "\(pastedTitle)";
      }
    }
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
        return TestResult(name: "Chrome", status: .failed, detail: "Could not create localhost server: \(error)")
    }
    guard let port = server.start(),
          let pageURL = URL(string: "http://127.0.0.1:\(port)/foil-chrome-paste-test.html") else {
        return TestResult(name: "Chrome", status: .failed, detail: "Could not start localhost target server")
    }
    defer { server.stop() }

    let chromeExecutable = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if FileManager.default.fileExists(atPath: chromeExecutable) {
        launch(chromeExecutable, ["--incognito", "--new-window", pageURL.absoluteString])
    } else {
        NSWorkspace.shared.open(
            [pageURL],
            withApplicationAt: chromeURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
    Thread.sleep(forTimeInterval: 2.5)
    activateApplication(bundleID: "com.google.Chrome")
    Thread.sleep(forTimeInterval: 0.8)

    guard let target = captureCurrentTarget(), target.appName == "Google Chrome" else {
        return TestResult(name: "Chrome", status: .failed, detail: "Could not capture Chrome target")
    }

    switchToFinder()
    let frontAfterPaste = pasteIntoCapturedTarget(target, text: text)
    Thread.sleep(forTimeInterval: 0.8)

    guard let window = target.window else {
        return TestResult(name: "Chrome", status: .failed, detail: "Chrome target window was nil")
    }
    activateAndRaise(target)
    Thread.sleep(forTimeInterval: 0.5)
    let textArea = findAXElement(in: window, role: "AXTextArea")
        ?? findAXElement(in: window, role: "AXTextField")
    let value = textArea.map(axValue) ?? ""
    let title = windowTitle(window)

    if value.contains(text) || title.contains(pastedTitle) {
        return TestResult(name: "Chrome", status: .passed, detail: "Text reached captured textarea; frontmost after paste: \(frontAfterPaste ?? "unknown"); transport=localhost; privateMode=requested; no tab close; no browser quit")
    }
    return TestResult(name: "Chrome", status: .failed, detail: "Pasted text not found in Chrome AX value or page title")
}

func testVSCodePresence() -> TestResult {
    guard FileManager.default.fileExists(atPath: "/Applications/Visual Studio Code.app") else {
        return TestResult(name: "VS Code", status: .skipped, detail: "Visual Studio Code.app not installed")
    }
    return TestResult(name: "VS Code", status: .skipped, detail: "Installed, but editor automation is not implemented in this script yet")
}

func testNotesSafety() -> TestResult {
    TestResult(
        name: "Notes",
        status: .skipped,
        detail: "Skipped to avoid mutating persistent Notes data from automation"
    )
}

print("=== Cross-App Async Paste Automation ===")
print()

guard AXIsProcessTrusted() else {
    print("ERROR: Accessibility permission is required for this test.")
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(opts)
    exit(1)
}

let results = [
    testTerminal(),
    testChrome(),
    testVSCodePresence(),
    testNotesSafety()
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

exit(failed ? 1 : 0)

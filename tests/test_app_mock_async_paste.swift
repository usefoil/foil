#!/usr/bin/env swift
//
// Real-app smoke test for Foil's mock transcription + async paste path.
//
// This drives the installed menu bar app through an automation-only
// notification and intentionally avoids `--ui-testing`, so PasteQueue must use
// the production TextInserter.insertAsync path rather than the UI-test
// clipboard bypass. It is visible desktop automation, not a headless test.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

let appBundleID = "com.neonwatty.Foil"
let appPath = "/Applications/Foil.app"
let diagnosticLogURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Foil", isDirectory: true)
    .appendingPathComponent("Diagnostics", isDirectory: true)
    .appendingPathComponent("foil.log", isDirectory: false)
var diagnosticLogStartOffset: UInt64 = 0
let testTextPrefix = "Mock transcription automation smoke"
let textEditSmokeWindowMarker = "FoilAppSmokeTarget"

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

func windowTitle(_ element: AXUIElement) -> String {
    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    return titleRef as? String ?? ""
}

func findTextArea(in element: AXUIElement) -> AXUIElement? {
    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    if roleRef as? String == "AXTextArea" { return element }

    var childrenRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    guard let children = childrenRef as? [AXUIElement] else { return nil }
    for child in children {
        if let found = findTextArea(in: child) {
            return found
        }
    }
    return nil
}

func textValue(in window: AXUIElement) -> String {
    guard let textArea = findTextArea(in: window) else { return "" }
    var valueRef: CFTypeRef?
    AXUIElementCopyAttributeValue(textArea, kAXValueAttribute as CFString, &valueRef)
    return valueRef as? String ?? ""
}

func windowTitles(forBundleID bundleID: String) -> [String] {
    guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        return []
    }

    let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
    var windowsRef: CFTypeRef?
    AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
    guard let windows = windowsRef as? [AXUIElement] else { return [] }
    return windows.map(windowTitle)
}

func frontmostAppDescription() -> String {
    guard let app = NSWorkspace.shared.frontmostApplication else { return "nil" }
    let name = app.localizedName ?? "unknown"
    let bundle = app.bundleIdentifier ?? "unknown"
    return "\(name) bundle=\(bundle) pid=\(app.processIdentifier)"
}

func failIfSecurityAgentFrontmost(stage: String) {
    guard let app = NSWorkspace.shared.frontmostApplication else { return }
    if app.localizedName == "SecurityAgent" || app.bundleIdentifier == "com.apple.SecurityAgent" {
        print("ERROR: SecurityAgent is frontmost during \(stage). A macOS keychain/security prompt is blocking installed-app automation; handle the prompt manually, quit Foil, and rerun.")
        print("Frontmost: \(frontmostAppDescription())")
        finish(2)
    }
}

func closeTextEditWindows(containing _: String) {
    run("/usr/bin/pkill", ["-x", "TextEdit"])
}

func cleanup() {
    closeTextEditWindows(containing: textEditSmokeWindowMarker)
    try? FileManager.default.removeItem(
        at: FileManager.default.temporaryDirectory.appendingPathComponent("FoilAppSmokeTarget.txt")
    )
    run("/usr/bin/pkill", ["-x", "Foil"])
}

func finish(_ status: Int32) -> Never {
    cleanup()
    exit(status)
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

func failFoilLaunchDidNotReachAutomationSmoke() -> Never {
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
    finish(1)
}

func requireFrontmost(bundleID expectedBundleID: String, stage: String) {
    failIfSecurityAgentFrontmost(stage: stage)
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == expectedBundleID else {
        print("ERROR: Expected \(expectedBundleID) frontmost during \(stage), got \(frontmostAppDescription()).")
        finish(1)
    }
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

print("=== Foil Real-App Mock Async Paste Smoke Test ===")
print()

guard AXIsProcessTrusted() else {
    print("ERROR: Accessibility permission is required.")
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(opts)
    finish(1)
}

guard FileManager.default.fileExists(atPath: appPath) else {
    print("ERROR: \(appPath) not found. Run `make install` first.")
    finish(1)
}

try? FileManager.default.createDirectory(
    at: diagnosticLogURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
diagnosticLogStartOffset = ((try? diagnosticLogURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init)) ?? 0

run("/usr/bin/defaults", ["write", appBundleID, "mockTranscriptionEnabled", "-bool", "true"])
run("/usr/bin/defaults", ["write", appBundleID, "asyncPasteEnabled", "-bool", "true"])
run("/usr/bin/defaults", ["write", appBundleID, "keepOnClipboard", "-bool", "false"])
run("/usr/bin/defaults", ["write", appBundleID, "recordingMode", "hold"])
run("/usr/bin/defaults", ["write", appBundleID, "audioFormat", "m4a"])
run("/usr/bin/defaults", ["write", appBundleID, "transcriptProcessingMode", "raw"])
run("/usr/bin/defaults", ["write", appBundleID, "showFloatingStatus", "-bool", "false"])

run("/usr/bin/pkill", ["-x", "Foil"])
Thread.sleep(forTimeInterval: 1.0)
run("/usr/bin/open", ["-n", appPath, "--args", "--automation-smoke"])

let foilProcessStarted = waitUntil(timeout: 8, poll: 0.25, {
    failIfSecurityAgentFrontmost(stage: "Foil launch")
    return NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).first != nil
})
guard foilProcessStarted else {
    print("ERROR: Foil did not launch.")
    finish(1)
}

guard waitUntil(timeout: 8, poll: 0.25, {
    failIfSecurityAgentFrontmost(stage: "Foil automation smoke startup")
    return readDiagnosticLog().contains("automation smoke: enabled")
}) else {
    failFoilLaunchDidNotReachAutomationSmoke()
}
Thread.sleep(forTimeInterval: 1.5)
failIfSecurityAgentFrontmost(stage: "after Foil launch")

run("/usr/bin/pkill", ["-x", "TextEdit"])
Thread.sleep(forTimeInterval: 1.0)

let fileA = FileManager.default.temporaryDirectory.appendingPathComponent("FoilAppSmokeTarget.txt")
try "Foil app smoke target\n".write(to: fileA, atomically: true, encoding: .utf8)
defer {
    try? FileManager.default.removeItem(at: fileA)
}

NSWorkspace.shared.open(fileA)
Thread.sleep(forTimeInterval: 1.5)

guard let textEditApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else {
    print("ERROR: TextEdit did not launch.")
    finish(1)
}
let axTextEdit = AXUIElementCreateApplication(textEditApp.processIdentifier)
var windowsRef: CFTypeRef?
AXUIElementCopyAttributeValue(axTextEdit, kAXWindowsAttribute as CFString, &windowsRef)
guard let windows = windowsRef as? [AXUIElement] else {
    print("ERROR: Could not read TextEdit windows.")
    finish(1)
}

let targetWindow = windows.first { windowTitle($0).contains("FoilAppSmokeTarget") }
guard let targetWindow else {
    print("ERROR: Could not identify TextEdit smoke window.")
    finish(1)
}

AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, true as CFTypeRef)
AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, true as CFTypeRef)
_ = waitUntil(timeout: 3, poll: 0.25) {
    AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, true as CFTypeRef)
    AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, true as CFTypeRef)
    textEditApp.activate(options: [.activateAllWindows])
    return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit"
}
requireFrontmost(bundleID: "com.apple.TextEdit", stage: "TextEdit target capture")

print("Requesting automation mock transcription against TextEdit target...")
failIfSecurityAgentFrontmost(stage: "before automation mock notification")
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.neonwatty.Foil.automation.mockSuccess"),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
Thread.sleep(forTimeInterval: 0.8)
NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
Thread.sleep(forTimeInterval: 0.5)

let pasted = waitUntil(timeout: 9, poll: 0.5, {
    failIfSecurityAgentFrontmost(stage: "paste verification")
    AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
    textEditApp.activate()
    Thread.sleep(forTimeInterval: 0.1)
    return textValue(in: targetWindow).contains(testTextPrefix)
})

let targetText = textValue(in: targetWindow)
let log = readDiagnosticLog()
let groqTalkWindows = windowTitles(forBundleID: appBundleID)
let floatingStatusVisible = groqTalkWindows.contains { $0 == "Foil Floating Status" }

print()
print("Diagnostic checks:")
print(log.contains("automation smoke: requested") ? "✓ automation mock transcription requested" : "✗ automation request not observed")
print(log.contains("ASYNC PATH") ? "✓ async paste path used" : "✗ async paste path not observed")
print(log.contains("insertAsync:") ? "✓ production insertAsync path exercised" : "✗ production insertAsync path not observed")
print(!log.contains("UITest paste queue") ? "✓ UI-test paste bypass not used" : "✗ UI-test paste bypass was used")
print(log.contains("automation smoke: enabled") ? "✓ automation smoke mode enabled" : "✗ automation smoke mode missing")
print(!floatingStatusVisible ? "✓ floating status stayed off by default" : "✗ floating status appeared despite default-off preference")

if log.contains("UITest paste queue") {
    print("ERROR: Real paste smoke test used the UI-test paste bypass.")
    finish(1)
}

if !log.contains("insertAsync:") {
    print("ERROR: Real paste smoke test did not exercise TextInserter.insertAsync.")
    finish(1)
}

if log.contains("Microphone unavailable") {
    print("ERROR: Foil reported microphone unavailable.")
    finish(1)
}

if floatingStatusVisible {
    print("Foil windows: \(groqTalkWindows)")
    finish(1)
}

if pasted && targetText.contains(testTextPrefix) {
    print()
    print("✅ PASS: Installed Foil used mock transcription and pasted into the TextEdit target.")
    finish(0)
}

if log.contains("windowElement: nil") {
    print()
    print("⚠️  SKIP: Installed Foil entered the mock async path, but this desktop session did not expose the target AX window to the app process.")
    print("Grant or refresh Accessibility permission for /Applications/Foil.app, then rerun `make test-paste-real`.")
    if ProcessInfo.processInfo.environment["ALLOW_LOCAL_QA_SKIP"] == "1" {
        print("ALLOW_LOCAL_QA_SKIP=1 set; recording this as an explicit local skip.")
        finish(0)
    }
    print("Set ALLOW_LOCAL_QA_SKIP=1 only when this skip is recorded in the release QA log.")
    finish(2)
}

print()
print("❌ FAIL: Mock transcription text was not found in the TextEdit target.")
print("Target prefix: \(targetText.prefix(120))")
finish(1)

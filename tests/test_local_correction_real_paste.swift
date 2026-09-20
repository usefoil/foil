#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

private let environment = ProcessInfo.processInfo.environment
private let targetBundleID = environment["LOCAL_CORRECTION_TARGET_BUNDLE_ID"] ?? "com.apple.TextEdit"
private let otherTargetBundleID = environment["LOCAL_CORRECTION_OTHER_TARGET_BUNDLE_ID"]
private let agentBundleID = environment["LOCAL_CORRECTION_AGENT_BUNDLE_ID"] ?? "com.mitchellh.ghostty"
private let rawText = environment["LOCAL_CORRECTION_RAW_TEXT"] ?? "foil acceptance super base"
private let expectedText = environment["LOCAL_CORRECTION_EXPECTED_TEXT"] ?? rawText
private let source = environment["LOCAL_CORRECTION_SOURCE"] ?? "super base"
private let replacement = environment["LOCAL_CORRECTION_REPLACEMENT"] ?? "Supabase"
private let shouldConfigure = environment["LOCAL_CORRECTION_CONFIGURE"] == "1"
private let shouldDisable = environment["LOCAL_CORRECTION_DISABLE"] == "1"
private let shouldPrepareTextEdit = environment["LOCAL_CORRECTION_PREPARE_TEXTEDIT"] == "1"
private let receiptPath = environment["LOCAL_CORRECTION_RECEIPT_PATH"]
private let targetWindowTitleFragment = environment["LOCAL_CORRECTION_TARGET_WINDOW_TITLE_CONTAINS"]
private let useFocusedElement = environment["LOCAL_CORRECTION_USE_FOCUSED_ELEMENT"] == "1"

struct Receipt: Codable {
    let targetBundleIdentifier: String
    let targetProcessIdentifier: Int32
    let expectedText: String
    let expectedTextObserved: Bool
    let otherTargetBundleIdentifier: String?
    let otherTargetUnchanged: Bool?
    let configuredRule: Bool
    let disabledRule: Bool
    let targetValueUTF8CountBefore: Int
    let targetValueUTF8CountAfter: Int
    let targetElementRole: String
}

private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

private func firstTextArea(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    guard depth <= 12 else { return nil }
    if attribute(element, kAXRoleAttribute) as? String == kAXTextAreaRole as String {
        return element
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let found = firstTextArea(in: child, depth: depth + 1) {
            return found
        }
    }
    return nil
}

private func firstUsableWindow(
    for app: NSRunningApplication,
    titleFragment: String? = nil
) -> AXUIElement? {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    let windows = attribute(appElement, kAXWindowsAttribute) as? [AXUIElement] ?? []
    return windows.first { window in
        guard firstTextArea(in: window) != nil else { return false }
        guard let titleFragment else { return true }
        let title = attribute(window, kAXTitleAttribute) as? String ?? ""
        return title.localizedCaseInsensitiveContains(titleFragment)
    }
}

private func textValue(in window: AXUIElement) -> String {
    guard let textArea = firstTextArea(in: window) else { return "" }
    return attribute(textArea, kAXValueAttribute) as? String ?? ""
}

private func elementValue(_ element: AXUIElement) -> String {
    attribute(element, kAXValueAttribute) as? String ?? ""
}

private func focusedElement(forBundleIdentifier bundleID: String) -> AXUIElement? {
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return nil }
    let systemWide = AXUIElementCreateSystemWide()
    guard let element = attribute(systemWide, kAXFocusedUIElementAttribute) else { return nil }
    guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
    // Safe: the Core Foundation type ID is checked before the cast.
    // swiftlint:disable:next force_cast
    let axElement = element as! AXUIElement
    var pid: pid_t = 0
    guard AXUIElementGetPid(axElement, &pid) == .success,
          NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == bundleID,
          attribute(axElement, kAXValueAttribute) is String else {
        return nil
    }
    return axElement
}

private func firstWindow(for app: NSRunningApplication) -> AXUIElement? {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    return (attribute(appElement, kAXWindowsAttribute) as? [AXUIElement])?.first
}

private func focusAtEnd(
    window: AXUIElement,
    editableElement: AXUIElement? = nil,
    app: NSRunningApplication
) {
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFTypeRef)
    AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)
    if let textArea = editableElement ?? firstTextArea(in: window) {
        AXUIElementSetAttributeValue(textArea, kAXFocusedAttribute as CFString, true as CFTypeRef)
        var range = CFRange(location: elementValue(textArea).utf16.count, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(
                textArea,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
            )
        }
    }
    app.activate(options: [.activateAllWindows])
}

private func waitUntil(timeout: TimeInterval, poll: TimeInterval = 0.2, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        Thread.sleep(forTimeInterval: poll)
    }
    return condition()
}

private func fail(_ message: String) -> Never {
    fputs("ERROR: \(message)\n", stderr)
    exit(1)
}

guard AXIsProcessTrusted() else {
    fail("Accessibility permission is required by the real-paste acceptance harness.")
}

if shouldPrepareTextEdit {
    let marker = environment["LOCAL_CORRECTION_TEXTEDIT_MARKER"] ?? "FoilLocalCorrectionTarget"
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(marker).txt")
    try? FileManager.default.removeItem(at: fixtureURL)
    do {
        try "\(marker)\n".write(to: fixtureURL, atomically: true, encoding: .utf8)
    } catch {
        fail("Could not create TextEdit fixture: \(error.localizedDescription)")
    }
    NSWorkspace.shared.open(fixtureURL)
}

guard waitUntil(timeout: useFocusedElement ? 120 : 8, {
    if useFocusedElement {
        return focusedElement(forBundleIdentifier: targetBundleID) != nil
    }
    return NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID)
        .contains { firstUsableWindow(for: $0, titleFragment: targetWindowTitleFragment) != nil }
}) else {
    fail("No usable editable target appeared for \(targetBundleID).")
}

guard let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID)
    .first(where: {
        useFocusedElement || firstUsableWindow(for: $0, titleFragment: targetWindowTitleFragment) != nil
    }),
      let targetWindow = useFocusedElement
        ? firstWindow(for: targetApp)
        : firstUsableWindow(for: targetApp, titleFragment: targetWindowTitleFragment),
      let targetEditableElement = useFocusedElement
        ? focusedElement(forBundleIdentifier: targetBundleID)
        : firstTextArea(in: targetWindow) else {
    fail("Could not resolve the target window for \(targetBundleID).")
}

let otherTargetSnapshot: (bundleID: String, value: String)? = otherTargetBundleID.flatMap { bundleID in
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .first(where: { firstUsableWindow(for: $0) != nil }),
          let window = firstUsableWindow(for: app) else {
        return nil
    }
    return (bundleID, textValue(in: window))
}

focusAtEnd(window: targetWindow, editableElement: targetEditableElement, app: targetApp)
guard waitUntil(timeout: 3, { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundleID }) else {
    fail("\(targetBundleID) did not become frontmost for target capture.")
}

let targetBefore = elementValue(targetEditableElement)
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.neonwatty.Foil.automation.localCorrection"),
    object: nil,
    userInfo: [
        "rawText": rawText,
        "source": source,
        "replacement": replacement,
        "agentBundleIdentifier": agentBundleID,
        "configure": NSNumber(value: shouldConfigure),
        "disable": NSNumber(value: shouldDisable)
    ],
    deliverImmediately: true
)

Thread.sleep(forTimeInterval: 0.4)
NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()

let observed = waitUntil(timeout: 12) {
    elementValue(targetEditableElement).contains(expectedText)
}
let targetAfter = elementValue(targetEditableElement)
let otherUnchanged = otherTargetSnapshot.map { snapshot -> Bool in
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: snapshot.bundleID)
        .first(where: { firstUsableWindow(for: $0) != nil }),
          let window = firstUsableWindow(for: app) else {
        return false
    }
    return textValue(in: window) == snapshot.value
}

let receipt = Receipt(
    targetBundleIdentifier: targetBundleID,
    targetProcessIdentifier: targetApp.processIdentifier,
    expectedText: expectedText,
    expectedTextObserved: observed,
    otherTargetBundleIdentifier: otherTargetSnapshot?.bundleID,
    otherTargetUnchanged: otherUnchanged,
    configuredRule: shouldConfigure,
    disabledRule: shouldDisable,
    targetValueUTF8CountBefore: targetBefore.utf8.count,
    targetValueUTF8CountAfter: targetAfter.utf8.count,
    targetElementRole: attribute(targetEditableElement, kAXRoleAttribute) as? String ?? "unknown"
)
if let receiptPath {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        try encoder.encode(receipt).write(to: URL(fileURLWithPath: receiptPath), options: .atomic)
    } catch {
        fail("Could not write receipt: \(error.localizedDescription)")
    }
}

guard observed else {
    fail("Expected text was not observed in \(targetBundleID).")
}
if let otherUnchanged, !otherUnchanged {
    fail("The non-target app \(otherTargetSnapshot?.bundleID ?? "unknown") changed.")
}

print("PASS target=\(targetBundleID) pid=\(targetApp.processIdentifier) expected=\(expectedText)")
if let otherUnchanged {
    print("PASS otherTargetUnchanged=\(otherUnchanged)")
}

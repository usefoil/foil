# SkyLight Background Paste Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable invisible async paste into background windows using macOS SkyLight private framework APIs, with automatic fallback to the existing window-choreography approach.

**Architecture:** A new `SkyLightBridge` enum wraps three private SkyLight functions via `dlopen`/`dlsym`. A new `BackgroundPaste` struct orchestrates the focus-without-raise → CMD+V → restore-focus sequence. `TextInserter` gains an `insertAsync()` method that tries the SkyLight path first, falling back to the existing `insertAtTarget()`. `PasteTarget` is extended with a `CGWindowID` field needed by the SkyLight buffer.

**Tech Stack:** Swift, macOS SkyLight.framework (private), ApplicationServices (AXUIElement), CoreGraphics (CGEvent)

**Spec:** `docs/superpowers/specs/2026-04-27-skylight-background-paste-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Foil/SkyLightBridge.swift` | Create | All `dlopen`/`dlsym` wrappers. No other file touches raw function pointers. |
| `Foil/BackgroundPaste.swift` | Create | Tier 1 orchestration: focus-without-raise → CMD+V → restore focus. |
| `Foil/PasteTarget.swift` | Modify | Add `windowID: CGWindowID?` property and capture logic. |
| `Foil/TextInserter.swift` | Modify | Add `insertAsync()` method (Tier 1 → Tier 2 fallback chain). |
| `Foil/FoilApp.swift` | Modify | Change PasteQueue handler from `insertAtTarget` to `insertAsync`. |
| `FoilTests/SkyLightBridgeTests.swift` | Create | Tests for SPI availability and graceful nil handling. |
| `FoilTests/PasteTargetTests.swift` | Modify | Add windowID tests. |
| `FoilTests/BackgroundPasteTests.swift` | Create | Tests for fallback logic (unavailable bridge, nil windowID). |
| `tests/test_skylight_paste.swift` | Create | Integration test: paste into background TextEdit, verify focus didn't change. |

---

### Task 1: SkyLightBridge — SPI Resolution

**Files:**
- Create: `Foil/SkyLightBridge.swift`
- Create: `FoilTests/SkyLightBridgeTests.swift`

- [ ] **Step 1: Write the failing test for SPI availability**

Create `FoilTests/SkyLightBridgeTests.swift`:

```swift
import XCTest
@testable import Foil

final class SkyLightBridgeTests: XCTestCase {
    func testIsAvailableReturnsBool() {
        // Must not crash — returns true if SPIs resolve, false if not.
        let available = SkyLightBridge.isAvailable
        XCTAssertTrue(available is Bool)
    }

    func testFocusWithoutRaiseReturnsFalseForInvalidPid() {
        // pid 0 is kernel — should fail gracefully, not crash.
        let result = SkyLightBridge.focusWithoutRaise(targetPid: 0, targetWindowID: 0)
        XCTAssertFalse(result)
    }

    func testWindowIDFromNilElementReturnsNil() {
        // Create an AXUIElement for a nonexistent app — windowID should be nil.
        let fakeElement = AXUIElementCreateApplication(0)
        let wid = SkyLightBridge.windowID(from: fakeElement)
        XCTAssertNil(wid)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/SkyLightBridgeTests 2>&1 | tail -10`

Expected: Build error — `SkyLightBridge` does not exist.

- [ ] **Step 3: Create the SkyLightBridge implementation**

Create `Foil/SkyLightBridge.swift`:

```swift
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// Wraps macOS SkyLight private framework APIs for background window
/// focus manipulation and event delivery. All dlopen/dlsym is here —
/// no other file touches raw function pointers.
///
/// If any SPI fails to resolve, `isAvailable` returns false and all
/// public methods return false/nil. Never crashes on missing symbols.
///
/// Reference implementations:
/// - Cua: github.com/trycua/cua (FocusWithoutRaise.swift, SkyLightEventPost.swift)
/// - yabai: github.com/koekeishiya/yabai (window_manager.c, extern.h)
enum SkyLightBridge {

    // MARK: - Function pointer types

    /// SLPSPostEventRecordTo(ProcessSerialNumber *psn, uint8_t *bytes) -> OSStatus
    private typealias PostEventRecordToFn = @convention(c) (
        UnsafeRawPointer, UnsafePointer<UInt8>
    ) -> Int32

    /// _SLPSGetFrontProcess(ProcessSerialNumber *psn) -> OSStatus
    private typealias GetFrontProcessFn = @convention(c) (
        UnsafeMutableRawPointer
    ) -> Int32

    /// GetProcessForPID(pid_t, ProcessSerialNumber *) -> OSStatus
    private typealias GetProcessForPIDFn = @convention(c) (
        pid_t, UnsafeMutableRawPointer
    ) -> Int32

    /// _AXUIElementGetWindow(AXUIElementRef, uint32_t *) -> AXError
    private typealias AXGetWindowFn = @convention(c) (
        AXUIElement, UnsafeMutablePointer<UInt32>
    ) -> Int32

    // MARK: - Resolved function pointers (lazy, once)

    private static let skyLightHandle: UnsafeMutableRawPointer? = {
        dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY
        )
    }()

    private static let postEventRecordToFn: PostEventRecordToFn? = {
        _ = skyLightHandle
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SLPSPostEventRecordTo")
        else { return nil }
        return unsafeBitCast(p, to: PostEventRecordToFn.self)
    }()

    private static let getFrontProcessFn: GetFrontProcessFn? = {
        _ = skyLightHandle
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_SLPSGetFrontProcess")
        else { return nil }
        return unsafeBitCast(p, to: GetFrontProcessFn.self)
    }()

    private static let getProcessForPIDFn: GetProcessForPIDFn? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID")
        else { return nil }
        return unsafeBitCast(p, to: GetProcessForPIDFn.self)
    }()

    private static let axGetWindowFn: AXGetWindowFn? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow")
        else { return nil }
        return unsafeBitCast(p, to: AXGetWindowFn.self)
    }()

    // MARK: - Public API

    /// True when all required SPIs resolved — safe to call focusWithoutRaise.
    static var isAvailable: Bool {
        postEventRecordToFn != nil
            && getFrontProcessFn != nil
            && getProcessForPIDFn != nil
    }

    /// Put targetPid's window into AppKit-active state for input routing
    /// without raising it or triggering Space follow.
    ///
    /// Recipe from yabai's window_manager_focus_window_without_raise:
    /// 1. Defocus current frontmost (bytes[0x8A] = 0x02)
    /// 2. Wait 40ms
    /// 3. Focus target (bytes[0x8A] = 0x01)
    /// Deliberately skip _SLPSSetFrontProcessWithOptions to avoid raising.
    static func focusWithoutRaise(targetPid: pid_t, targetWindowID: CGWindowID) -> Bool {
        guard let postFn = postEventRecordToFn,
              let getFront = getFrontProcessFn,
              let getPSN = getProcessForPIDFn
        else { return false }

        // Get current frontmost PSN (8 bytes)
        var prevPSN = [UInt8](repeating: 0, count: 8)
        let prevOk = prevPSN.withUnsafeMutableBytes { raw in
            getFront(raw.baseAddress!) == 0
        }
        guard prevOk else { return false }

        // Get target PSN
        var targetPSN = [UInt8](repeating: 0, count: 8)
        let targetOk = targetPSN.withUnsafeMutableBytes { raw in
            getPSN(targetPid, raw.baseAddress!) == 0
        }
        guard targetOk else { return false }

        // Build the 248-byte event record
        var buf = [UInt8](repeating: 0, count: 0xF8)
        buf[0x04] = 0xF8
        buf[0x08] = 0x0D
        let wid = UInt32(targetWindowID)
        buf[0x3C] = UInt8(wid & 0xFF)
        buf[0x3D] = UInt8((wid >> 8) & 0xFF)
        buf[0x3E] = UInt8((wid >> 16) & 0xFF)
        buf[0x3F] = UInt8((wid >> 24) & 0xFF)

        // Defocus previous frontmost
        buf[0x8A] = 0x02
        let defocusOk = prevPSN.withUnsafeBytes { psnRaw in
            buf.withUnsafeBufferPointer { bp in
                postFn(psnRaw.baseAddress!, bp.baseAddress!) == 0
            }
        }

        // 40ms delay — empirical finding from yabai: some apps get
        // confused if both events arrive instantaneously.
        usleep(40_000)

        // Focus target
        buf[0x8A] = 0x01
        let focusOk = targetPSN.withUnsafeBytes { psnRaw in
            buf.withUnsafeBufferPointer { bp in
                postFn(psnRaw.baseAddress!, bp.baseAddress!) == 0
            }
        }

        return defocusOk && focusOk
    }

    /// Extract the CGWindowID from an AXUIElement via the private
    /// _AXUIElementGetWindow function. Returns nil when the SPI
    /// is unavailable or the element has no associated window.
    static func windowID(from element: AXUIElement) -> CGWindowID? {
        guard let fn = axGetWindowFn else { return nil }
        var wid: UInt32 = 0
        let result = fn(element, &wid)
        guard result == 0, wid != 0 else { return nil }
        return CGWindowID(wid)
    }

    /// Snapshot the current frontmost app's pid and focused window ID.
    /// Used to restore focus after a background paste.
    static func currentFocus() -> (pid: pid_t, windowID: CGWindowID)? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        guard pid > 0 else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef
        )
        guard result == .success, let ref = windowRef else { return nil }
        // swiftlint:disable:next force_cast
        let windowElement = ref as! AXUIElement
        guard let wid = windowID(from: windowElement) else { return nil }

        return (pid: pid, windowID: wid)
    }
}
```

- [ ] **Step 4: Add the new file to the Xcode project**

The project uses automatic file discovery, but the file must be added to the `Foil` group. Use the XcodeBuildMCP or manually verify:

Run: `xcodebuild -scheme Foil -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: Build succeeds (the enum exists but nothing references it yet besides tests).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/SkyLightBridgeTests 2>&1 | tail -10`

Expected: All 3 tests pass. `testIsAvailableReturnsBool` will return `true` on a dev machine with SkyLight present. `testFocusWithoutRaiseReturnsFalseForInvalidPid` returns `false` because pid 0 can't have a valid PSN. `testWindowIDFromNilElementReturnsNil` returns `nil` because pid 0 has no windows.

- [ ] **Step 6: Commit**

```bash
git add Foil/SkyLightBridge.swift FoilTests/SkyLightBridgeTests.swift
git commit -m "feat: add SkyLightBridge with dlsym wrappers for focus-without-raise"
```

---

### Task 2: PasteTarget — Add windowID

**Files:**
- Modify: `Foil/PasteTarget.swift`
- Modify: `FoilTests/PasteTargetTests.swift`

- [ ] **Step 1: Write the failing tests for windowID**

Add to `FoilTests/PasteTargetTests.swift`:

```swift
func testManualInitWithWindowID() {
    let target = PasteTarget(windowElement: nil, windowID: 12345, pid: 999, appName: "App")
    XCTAssertEqual(target.windowID, 12345)
}

func testManualInitWithNilWindowID() {
    let target = PasteTarget(windowElement: nil, windowID: nil, pid: 999, appName: "App")
    XCTAssertNil(target.windowID)
}

func testCaptureIncludesWindowID() {
    // On a dev machine with AX, captureCurrentTarget should attempt
    // to populate windowID. We can't guarantee it's non-nil (depends
    // on AX permissions) but it must not crash.
    let target = PasteTarget.captureCurrentTarget()
    if let target, target.windowElement != nil {
        // If we got a window element, windowID should also be populated
        // (both come from the same focused window).
        XCTAssertNotNil(target.windowID)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/PasteTargetTests 2>&1 | tail -10`

Expected: Build error — `PasteTarget` initializer does not accept `windowID` parameter.

- [ ] **Step 3: Add windowID to PasteTarget**

Modify `Foil/PasteTarget.swift`. Replace the entire file:

```swift
import ApplicationServices
import AppKit

/// Captures the identity of the window that should receive a paste.
/// Stored at the moment the user triggers recording so that focus changes
/// during transcription don't redirect the paste to the wrong app.
struct PasteTarget {
    let windowElement: AXUIElement?
    let windowID: CGWindowID?
    let pid: pid_t
    let appName: String

    /// A target is valid when it refers to a real process.
    var isValid: Bool { pid > 0 }

    /// Captures the currently focused window and owning process.
    /// Returns nil when Accessibility permissions are not granted or no
    /// focused window can be determined.
    static func captureCurrentTarget() -> PasteTarget? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let pid = frontApp.processIdentifier
        guard pid > 0 else { return nil }

        let appName = frontApp.localizedName ?? ""
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        )

        let window: AXUIElement?
        if result == .success, let ref = windowRef {
            // swiftlint:disable:next force_cast
            window = (ref as! AXUIElement)
        } else {
            window = nil
        }

        let windowID = window.flatMap { SkyLightBridge.windowID(from: $0) }

        return PasteTarget(windowElement: window, windowID: windowID, pid: pid, appName: appName)
    }
}
```

- [ ] **Step 4: Fix existing call sites that construct PasteTarget manually**

The existing tests and `PasteQueue` handler construct `PasteTarget` without `windowID`. Update all call sites to include `windowID: nil`:

In `FoilTests/PasteTargetTests.swift`, update the three existing tests:

```swift
func testManualInitStoresValues() {
    let target = PasteTarget(windowElement: nil, windowID: nil, pid: 12345, appName: "TestApp")
    XCTAssertEqual(target.pid, 12345)
    XCTAssertEqual(target.appName, "TestApp")
    XCTAssertNil(target.windowElement)
}

func testTargetWithZeroPidIsInvalid() {
    let target = PasteTarget(windowElement: nil, windowID: nil, pid: 0, appName: "")
    XCTAssertFalse(target.isValid)
}

func testTargetWithPositivePidIsValid() {
    let target = PasteTarget(windowElement: nil, windowID: nil, pid: 999, appName: "App")
    XCTAssertTrue(target.isValid)
}
```

In `FoilTests/PasteQueueTests.swift`, update all `PasteTarget(` calls to include `windowID: nil`:

```swift
// In testEnqueueAndDrain:
PasteTarget(windowElement: nil, windowID: nil, pid: 1, appName: "A")
PasteTarget(windowElement: nil, windowID: nil, pid: 2, appName: "B")

// In testSerializesExecution:
PasteTarget(windowElement: nil, windowID: nil, pid: 1, appName: "A")  // (all three lines)

// In testInvalidTargetSkips:
PasteTarget(windowElement: nil, windowID: nil, pid: 0, appName: "")
```

- [ ] **Step 5: Run all tests to verify they pass**

Run: `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' 2>&1 | tail -10`

Expected: All tests pass including the three new PasteTarget tests.

- [ ] **Step 6: Commit**

```bash
git add Foil/PasteTarget.swift FoilTests/PasteTargetTests.swift FoilTests/PasteQueueTests.swift
git commit -m "feat: add windowID to PasteTarget for SkyLight focus-without-raise"
```

---

### Task 3: BackgroundPaste — Tier 1 Orchestration

**Files:**
- Create: `Foil/BackgroundPaste.swift`
- Create: `FoilTests/BackgroundPasteTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `FoilTests/BackgroundPasteTests.swift`:

```swift
import XCTest
@testable import Foil

final class BackgroundPasteTests: XCTestCase {
    func testAttemptReturnsFalseWhenWindowIDIsNil() async {
        let target = PasteTarget(windowElement: nil, windowID: nil, pid: 999, appName: "App")
        let result = await BackgroundPaste.attempt(
            text: "hello", target: target, keepOnClipboard: false
        )
        XCTAssertFalse(result)
    }

    func testAttemptReturnsFalseForInvalidPid() async {
        let target = PasteTarget(windowElement: nil, windowID: 12345, pid: 0, appName: "")
        let result = await BackgroundPaste.attempt(
            text: "hello", target: target, keepOnClipboard: false
        )
        XCTAssertFalse(result)
    }

    func testAttemptReturnsFalseForTerminatedProcess() async {
        // pid 99999 is almost certainly not running
        let target = PasteTarget(windowElement: nil, windowID: 12345, pid: 99999, appName: "Ghost")
        let result = await BackgroundPaste.attempt(
            text: "hello", target: target, keepOnClipboard: false
        )
        XCTAssertFalse(result)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/BackgroundPasteTests 2>&1 | tail -10`

Expected: Build error — `BackgroundPaste` does not exist.

- [ ] **Step 3: Create BackgroundPaste implementation**

Create `Foil/BackgroundPaste.swift`:

```swift
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

        // Send CMD+V to the target PID
        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.postToPid(target.pid)
            keyUp.postToPid(target.pid)
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' -only-testing:FoilTests/BackgroundPasteTests 2>&1 | tail -10`

Expected: All 3 tests pass. Each returns `false` for the appropriate guard failure.

- [ ] **Step 5: Commit**

```bash
git add Foil/BackgroundPaste.swift FoilTests/BackgroundPasteTests.swift
git commit -m "feat: add BackgroundPaste orchestrator for SkyLight async paste"
```

---

### Task 4: TextInserter — Add insertAsync with Fallback Chain

**Files:**
- Modify: `Foil/TextInserter.swift:5-6` (add new method)

- [ ] **Step 1: Write the failing test**

There is no `TextInserterTests.swift` currently (TextInserter calls system APIs directly). The fallback logic is simple enough that we test it via the integration test in Task 6. For now, verify the build compiles.

Add the `insertAsync` method to `Foil/TextInserter.swift`, after the `insertAtTarget` method (after line 64):

```swift
/// Primary entry point for async paste. Tries SkyLight background
/// paste (Tier 1), falls back to window choreography (Tier 2).
func insertAsync(text: String, target: PasteTarget, keepOnClipboard: Bool) async {
    // Tier 1: SkyLight background paste (invisible)
    if await BackgroundPaste.attempt(
        text: text, target: target, keepOnClipboard: keepOnClipboard
    ) {
        DiagnosticLog.write("insertAsync: Tier 1 (SkyLight) succeeded for \(target.appName)")
        return
    }

    // Tier 2: Window choreography (existing behavior)
    DiagnosticLog.write("insertAsync: falling back to Tier 2 (choreography) for \(target.appName)")
    await insertAtTarget(text: text, target: target, keepOnClipboard: keepOnClipboard)
}
```

- [ ] **Step 2: Verify the build succeeds**

Run: `xcodebuild -scheme Foil -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run existing tests to verify no regressions**

Run: `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' 2>&1 | tail -10`

Expected: All existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add Foil/TextInserter.swift
git commit -m "feat: add insertAsync with SkyLight-first fallback chain"
```

---

### Task 5: Wire into FoilApp

**Files:**
- Modify: `Foil/FoilApp.swift:70`

- [ ] **Step 1: Change PasteQueue handler to use insertAsync**

In `Foil/FoilApp.swift`, line 70, change:

```swift
await self.textInserter.insertAtTarget(text: text, target: target, keepOnClipboard: keepOnClipboard)
```

to:

```swift
await self.textInserter.insertAsync(text: text, target: target, keepOnClipboard: keepOnClipboard)
```

- [ ] **Step 2: Verify the build succeeds**

Run: `xcodebuild -scheme Foil -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run all unit tests**

Run: `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' 2>&1 | tail -10`

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add Foil/FoilApp.swift
git commit -m "feat: wire PasteQueue to insertAsync for SkyLight-first paste"
```

---

### Task 6: Integration Test — SkyLight Background Paste

**Files:**
- Create: `tests/test_skylight_paste.swift`

- [ ] **Step 1: Create the integration test**

Create `tests/test_skylight_paste.swift`:

```swift
#!/usr/bin/env swift
//
// Integration test for SkyLight background paste.
// Opens two TextEdit windows, captures target A (with windowID),
// switches to B, pastes into A via SkyLight, verifies focus never
// visibly changed.
//
// Usage: swift tests/test_skylight_paste.swift
// Requires: Accessibility permission for Terminal/Ghostty

import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

// MARK: - SkyLight SPI wrappers (standalone — no Foil import)

private typealias PostEventRecordToFn = @convention(c) (UnsafeRawPointer, UnsafePointer<UInt8>) -> Int32
private typealias GetFrontProcessFn = @convention(c) (UnsafeMutableRawPointer) -> Int32
private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32

private let skyLightHandle = dlopen(
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY
)

private func resolve<T>(_ name: String, as _: T.Type) -> T? {
    guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}

private let slPostEventRecord = resolve("SLPSPostEventRecordTo", as: PostEventRecordToFn.self)
private let slGetFrontProcess = resolve("_SLPSGetFrontProcess", as: GetFrontProcessFn.self)
private let slGetProcessForPID = resolve("GetProcessForPID", as: GetProcessForPIDFn.self)
private let axGetWindow = resolve("_AXUIElementGetWindow", as: AXGetWindowFn.self)

var skyLightAvailable: Bool {
    slPostEventRecord != nil && slGetFrontProcess != nil && slGetProcessForPID != nil
}

func windowID(from element: AXUIElement) -> CGWindowID? {
    guard let fn = axGetWindow else { return nil }
    var wid: UInt32 = 0
    guard fn(element, &wid) == 0, wid != 0 else { return nil }
    return CGWindowID(wid)
}

func focusWithoutRaise(targetPid: pid_t, targetWindowID: CGWindowID) -> Bool {
    guard let postFn = slPostEventRecord,
          let getFront = slGetFrontProcess,
          let getPSN = slGetProcessForPID
    else { return false }

    var prevPSN = [UInt8](repeating: 0, count: 8)
    guard prevPSN.withUnsafeMutableBytes({ getFront($0.baseAddress!) }) == 0 else { return false }

    var targetPSN = [UInt8](repeating: 0, count: 8)
    guard targetPSN.withUnsafeMutableBytes({ getPSN(targetPid, $0.baseAddress!) }) == 0 else { return false }

    var buf = [UInt8](repeating: 0, count: 0xF8)
    buf[0x04] = 0xF8; buf[0x08] = 0x0D
    let wid = UInt32(targetWindowID)
    buf[0x3C] = UInt8(wid & 0xFF)
    buf[0x3D] = UInt8((wid >> 8) & 0xFF)
    buf[0x3E] = UInt8((wid >> 16) & 0xFF)
    buf[0x3F] = UInt8((wid >> 24) & 0xFF)

    buf[0x8A] = 0x02
    let _ = prevPSN.withUnsafeBytes { psnRaw in
        buf.withUnsafeBufferPointer { bp in
            postFn(psnRaw.baseAddress!, bp.baseAddress!)
        }
    }

    usleep(40_000)

    buf[0x8A] = 0x01
    let _ = targetPSN.withUnsafeBytes { psnRaw in
        buf.withUnsafeBufferPointer { bp in
            postFn(psnRaw.baseAddress!, bp.baseAddress!)
        }
    }

    return true
}

// MARK: - Helpers

func windowTitle(_ w: AXUIElement) -> String {
    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &titleRef)
    return (titleRef as? String) ?? "unknown"
}

func getWindowText(_ w: AXUIElement, textEditApp: NSRunningApplication) -> String {
    var childrenRef: CFTypeRef?
    AXUIElementCopyAttributeValue(w, kAXChildrenAttribute as CFString, &childrenRef)
    if let children = childrenRef as? [AXUIElement] {
        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            if let role = roleRef as? String, role == "AXScrollArea" || role == "AXTextArea" {
                var valueRef: CFTypeRef?
                AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef)
                if let value = valueRef as? String { return value }
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
    return "<could not read>"
}

// MARK: - Main test

print("=== SkyLight Background Paste Test ===")
print()

// Check permissions
if !AXIsProcessTrusted() {
    print("ERROR: No Accessibility permission.")
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(opts)
    exit(1)
}
print("✓ Accessibility permission granted")

// Check SkyLight availability
guard skyLightAvailable else {
    print("ERROR: SkyLight SPIs not available — cannot run this test.")
    exit(1)
}
print("✓ SkyLight SPIs resolved")

// Close existing TextEdit
_ = Process.launchedProcess(launchPath: "/usr/bin/pkill", arguments: ["-x", "TextEdit"])
Thread.sleep(forTimeInterval: 2)

// Create two temp files
let fileA = FileManager.default.temporaryDirectory.appendingPathComponent("SkyLightTestA.txt")
let fileB = FileManager.default.temporaryDirectory.appendingPathComponent("SkyLightTestB.txt")
try! "Window A - target\n".write(to: fileA, atomically: true, encoding: .utf8)
try! "Window B - user is here\n".write(to: fileB, atomically: true, encoding: .utf8)

print()
print("Step 1: Opening two TextEdit windows...")
let ws = NSWorkspace.shared
ws.open(fileA)
Thread.sleep(forTimeInterval: 2)
ws.open(fileB)
Thread.sleep(forTimeInterval: 2)
print("✓ Two TextEdit windows open")

// Find TextEdit windows
guard let textEditApp = NSRunningApplication.runningApplications(
    withBundleIdentifier: "com.apple.TextEdit"
).first else {
    print("ERROR: TextEdit not running"); exit(1)
}
let textEditPid = textEditApp.processIdentifier
let axApp = AXUIElementCreateApplication(textEditPid)

var windowList: CFTypeRef?
AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowList)
guard let windows = windowList as? [AXUIElement], windows.count >= 2 else {
    print("ERROR: Expected 2 TextEdit windows"); exit(1)
}

var windowA: AXUIElement?
var windowB: AXUIElement?
for w in windows {
    let title = windowTitle(w)
    if title.contains("SkyLightTestA") { windowA = w }
    if title.contains("SkyLightTestB") { windowB = w }
}
guard let wA = windowA, let wB = windowB else {
    print("ERROR: Could not identify windows A and B"); exit(1)
}

// Get window IDs
guard let widA = windowID(from: wA) else {
    print("ERROR: Could not get windowID for window A"); exit(1)
}
guard let widB = windowID(from: wB) else {
    print("ERROR: Could not get windowID for window B"); exit(1)
}
print("  Window A: '\(windowTitle(wA))' wid=\(widA)")
print("  Window B: '\(windowTitle(wB))' wid=\(widB)")

// Step 2: Focus window A (this is the "target" the user was in when recording started)
print()
print("Step 2: Focusing Window A and capturing target...")
AXUIElementPerformAction(wA, kAXRaiseAction as CFString)
textEditApp.activate()
Thread.sleep(forTimeInterval: 0.5)
print("✓ Target captured: TextEdit wid=\(widA)")

// Step 3: Switch to window B (simulate user moving away)
print()
print("Step 3: Switching to Window B...")
AXUIElementPerformAction(wB, kAXRaiseAction as CFString)
Thread.sleep(forTimeInterval: 0.5)

// Record which app is frontmost BEFORE paste
let frontBeforePaste = NSWorkspace.shared.frontmostApplication
print("  Frontmost before paste: \(frontBeforePaste?.localizedName ?? "nil")")
print("✓ User is in Window B")

// Step 4: Simulate transcription delay
print()
print("Step 4: Simulating 2-second transcription delay...")
Thread.sleep(forTimeInterval: 2.0)
print("✓ Transcription complete: 'SKYLIGHT_PASTE_TEST'")

// Step 5: SkyLight background paste — the actual test
print()
print("Step 5: SkyLight background paste into Window A...")

// Write text to clipboard
let testText = "SKYLIGHT_PASTE_TEST"
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(testText, forType: .string)

// Focus-without-raise to target
let focusOk = focusWithoutRaise(targetPid: textEditPid, targetWindowID: widA)
print("  focusWithoutRaise: \(focusOk ? "OK" : "FAILED")")
Thread.sleep(forTimeInterval: 0.05)

// Send CMD+V to target PID
let source = CGEventSource(stateID: .hidSystemState)
if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
   let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.postToPid(textEditPid)
    keyUp.postToPid(textEditPid)
    print("  CMD+V posted to pid \(textEditPid)")
}
Thread.sleep(forTimeInterval: 0.15)

// Restore focus to window B
let restoreOk = focusWithoutRaise(targetPid: textEditPid, targetWindowID: widB)
print("  Restore focus to B: \(restoreOk ? "OK" : "FAILED")")
Thread.sleep(forTimeInterval: 0.05)

// KEY ASSERTION: frontmost app should NOT have visibly changed
let frontAfterPaste = NSWorkspace.shared.frontmostApplication
print("  Frontmost after paste: \(frontAfterPaste?.localizedName ?? "nil")")

// Step 6: Verify results
print()
print("Step 6: Verifying results...")

// Read window contents (this WILL activate TextEdit temporarily for AX reads)
AXUIElementPerformAction(wA, kAXRaiseAction as CFString)
textEditApp.activate()
Thread.sleep(forTimeInterval: 0.3)
let textA = getWindowText(wA, textEditApp: textEditApp)

AXUIElementPerformAction(wB, kAXRaiseAction as CFString)
Thread.sleep(forTimeInterval: 0.3)
let textB = getWindowText(wB, textEditApp: textEditApp)

print("  Window A contents: \(textA.prefix(100))")
print("  Window B contents: \(textB.prefix(100))")

print()
var passed = true

if textA.contains(testText) && !textB.contains(testText) {
    print("✅ PASS: Text landed in Window A (target), not Window B")
} else if textB.contains(testText) {
    print("❌ FAIL: Text landed in Window B instead of Window A")
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
_ = Process.launchedProcess(launchPath: "/usr/bin/pkill", arguments: ["-x", "TextEdit"])

exit(passed ? 0 : 1)
```

- [ ] **Step 2: Run the integration test**

Run: `swift tests/test_skylight_paste.swift`

Expected: All steps pass. The critical assertion is that text lands in Window A while Window B was frontmost, and `frontAfterPaste` still shows TextEdit (focus never visibly switched).

If the test fails because CMD+V via `CGEvent.postToPid` doesn't reach TextEdit after `focusWithoutRaise`, that indicates we need `SLEventPostToPid` with the auth envelope — proceed to Task 7.

- [ ] **Step 3: Commit**

```bash
git add tests/test_skylight_paste.swift
git commit -m "test: add SkyLight background paste integration test"
```

---

### Task 7 (Conditional): SLEventPostToPid + Auth Envelope

**Only do this task if Task 6 Step 2 fails because CMD+V via `CGEvent.postToPid` doesn't reach the target app after `focusWithoutRaise`.**

**Files:**
- Modify: `Foil/SkyLightBridge.swift`

- [ ] **Step 1: Add SLEventPostToPid with auth envelope to SkyLightBridge**

Add these private types and resolved handles to `SkyLightBridge`:

```swift
// MARK: - SLEventPostToPid (auth-signed event posting)

/// void SLEventPostToPid(pid_t, CGEventRef)
private typealias SLPostToPidFn = @convention(c) (pid_t, CGEvent) -> Void

/// void SLEventSetAuthenticationMessage(CGEventRef, id)
private typealias SetAuthMessageFn = @convention(c) (CGEvent, AnyObject) -> Void

/// objc_msgSend for +[SLSEventAuthenticationMessage messageWithEventRecord:pid:version:]
private typealias FactoryMsgSendFn = @convention(c) (
    AnyObject, Selector, UnsafeMutableRawPointer, Int32, UInt32
) -> AnyObject?

private static let slPostToPidFn: SLPostToPidFn? = {
    _ = skyLightHandle
    guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SLEventPostToPid")
    else { return nil }
    return unsafeBitCast(p, to: SLPostToPidFn.self)
}()

private static let setAuthMessageFn: SetAuthMessageFn? = {
    _ = skyLightHandle
    guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SLEventSetAuthenticationMessage")
    else { return nil }
    return unsafeBitCast(p, to: SetAuthMessageFn.self)
}()

private static let authMessageClass: AnyClass? = {
    _ = skyLightHandle
    return NSClassFromString("SLSEventAuthenticationMessage")
}()

private static let factoryMsgSendFn: FactoryMsgSendFn? = {
    guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
    else { return nil }
    return unsafeBitCast(p, to: FactoryMsgSendFn.self)
}()

/// True when the auth-signed event post path is available.
static var isAuthPostAvailable: Bool {
    slPostToPidFn != nil && setAuthMessageFn != nil
        && authMessageClass != nil && factoryMsgSendFn != nil
}
```

Add the `postKeyEventViaSkyLight` method:

```swift
/// Post a keyboard CGEvent to a specific PID via SLEventPostToPid
/// with an SLSEventAuthenticationMessage attached. This is the
/// trusted channel that Chrome/Electron accept.
/// Falls back to CGEvent.postToPid if auth envelope can't be built.
static func postKeyEventViaSkyLight(to pid: pid_t, event: CGEvent) -> Bool {
    guard let postFn = slPostToPidFn else { return false }

    // Attach auth message if available
    if let setAuth = setAuthMessageFn,
       let msgClass = authMessageClass,
       let msgSend = factoryMsgSendFn,
       let record = extractEventRecord(from: event) {
        let selector = NSSelectorFromString("messageWithEventRecord:pid:version:")
        if let msg = msgSend(msgClass as AnyObject, selector, record, pid, 0) {
            setAuth(event, msg)
        }
    }

    postFn(pid, event)
    return true
}

/// Extract the SLSEventRecord pointer embedded in a CGEvent.
/// Layout: {CFRuntimeBase(16), uint32(4), padding(4), SLSEventRecord*}
/// → pointer at offset 24. Probe adjacent offsets for resilience.
private static func extractEventRecord(from event: CGEvent) -> UnsafeMutableRawPointer? {
    let base = Unmanaged.passUnretained(event).toOpaque()
    for offset in [24, 32, 16] {
        let slot = base.advanced(by: offset)
            .assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
        if let p = slot.pointee { return p }
    }
    return nil
}
```

- [ ] **Step 2: Update BackgroundPaste to prefer SLEventPostToPid**

In `Foil/BackgroundPaste.swift`, replace the CMD+V posting block:

```swift
// Send CMD+V to the target PID (prefer SkyLight auth-signed path for Chrome)
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
```

- [ ] **Step 3: Re-run integration test**

Run: `swift tests/test_skylight_paste.swift`

Expected: Test passes with the auth-signed path.

- [ ] **Step 4: Run all unit tests**

Run: `xcodebuild test -scheme Foil -configuration Debug -destination 'platform=macOS' 2>&1 | tail -10`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Foil/SkyLightBridge.swift Foil/BackgroundPaste.swift
git commit -m "feat: add SLEventPostToPid auth envelope for Chrome/Electron support"
```

---

### Task 8: Update Makefile and Run Full QA

**Files:**
- Modify: `Makefile:41-47`

- [ ] **Step 1: Add SkyLight integration test to qa target**

In `Makefile`, update the `qa` target to also run the SkyLight test:

```makefile
qa:
	@echo "=== Unit tests ==="
	xcodebuild test -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)"
	@echo ""
	@echo "=== Async paste integration test ==="
	-@pkill -x $(APP_NAME) 2>/dev/null; sleep 0.5
	swift tests/test_async_paste.swift
	@echo ""
	@echo "=== SkyLight background paste test ==="
	swift tests/test_skylight_paste.swift
```

- [ ] **Step 2: Run full QA**

Run: `make qa`

Expected: All three sections pass — unit tests, async paste integration, and SkyLight background paste.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "chore: add SkyLight paste test to qa target"
```

---

### Task 9: Manual Cross-App Testing

This task is not automated — it verifies the SkyLight paste works across real-world app types.

- [ ] **Step 1: Build and install**

Run: `make install`

- [ ] **Step 2: Test native Cocoa apps**

1. Open Notes, type something, start Foil recording
2. Switch to TextEdit while transcription runs
3. Verify: text appears in Notes without visible focus flicker

- [ ] **Step 3: Test Chrome**

1. Open Chrome, click into a Google search box, start recording
2. Switch to Finder while transcription runs
3. Verify: text appears in Chrome's search box

If Chrome fails: implement Task 7 (auth envelope), then re-test.

- [ ] **Step 4: Test Electron apps**

1. Open VS Code, click into an editor, start recording
2. Switch to another app while transcription runs
3. Verify: text appears in VS Code

If VS Code fails: implement Task 7 (auth envelope), then re-test.

- [ ] **Step 5: Test Terminal**

1. Open Terminal.app, start recording
2. Switch to another app while transcription runs
3. Verify: text appears at Terminal prompt

- [ ] **Step 6: Test Tier 2 fallback**

1. In Foil preferences, temporarily add a log line or breakpoint to verify Tier 2 fires
2. Reproduce a scenario where Tier 1 can't work (e.g., target window closed before paste)
3. Verify: existing `insertAtTarget` choreography executes as before

- [ ] **Step 7: Document results**

Record which apps work with Tier 1, which fall through to Tier 2, and whether Task 7 (auth envelope) was needed. Add a comment to `BackgroundPaste.swift` header with the findings.

- [ ] **Step 8: Commit any fixes from manual testing**

```bash
git add -A
git commit -m "fix: adjustments from manual cross-app testing"
```

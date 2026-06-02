# Recording Cue Acceptance Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automated acceptance coverage proving Foil uses the saved start cue in the real recording control path and delays microphone opening until after the start cue pre-roll.

**Architecture:** Keep normal CI hardware-free by using the existing `--ui-testing` app-command relay and a DEBUG-only audio stub. The UI test will launch Foil, set the recording start cue through app state/UserDefaults, replace the recording controller with an instrumented test controller, start recording through the same app command path used by the control center, and assert timestamped event order in the UI-test state snapshot.

**Tech Stack:** macOS Swift, XCTest/XCUITest, Xcode project, existing `DiagnosticLog`, existing `UITestingController` command-file relay, existing GitHub Actions focused UI smoke.

---

## File Structure

- Modify `Foil/UITestingController.swift`
  - Add DEBUG-only recording cue acceptance instrumentation.
  - Add timestamped recording event snapshots to the existing UI-test state JSON.
  - Add app commands for `prepareRecordingCueAcceptance`, `startRecording`, `stopRecording`, and `clearRecordingEvents`.

- Modify `FoilUITests/FoilUITests.swift`
  - Decode recording event snapshots.
  - Add `testSelectedStartCueIsUsedBeforeRecorderStarts`.
  - Add small helpers for event waiting and elapsed-time assertions.

- Modify `.github/workflows/ci.yml`
  - Add the new XCUITest to the `Focused UI Smoke` list so every PR checks the app-level recording cue path.

No new production feature file is needed. This is intentionally a narrow test seam inside the existing UI-test controller.

---

### Task 1: Add UI-Test Recording Event Snapshot Support

**Files:**
- Modify: `Foil/UITestingController.swift`
- Test: `FoilUITests/FoilUITests.swift`

- [ ] **Step 1: Write the failing UI-test decoder change**

In `FoilUITests/FoilUITests.swift`, extend `UITestStateSnapshot` near the top of the file:

```swift
private struct UITestRecordingEvent: Decodable, Equatable {
    let name: String
    let detail: String?
    let uptimeNanoseconds: UInt64
}

private struct UITestStateSnapshot: Decodable {
    let statusText: String
    let sessionTitle: String
    let sessionDetail: String
    let accessibilityText: String
    let accessibilityActionTitle: String?
    let microphoneText: String
    let microphoneActionTitle: String?
    let apiKeyText: String
    let apiKeyActionTitle: String?
    let canStartRecording: Bool
    let recordingEvents: [UITestRecordingEvent]
}
```

This should fail to decode until the app snapshot includes `recordingEvents`.

- [ ] **Step 2: Run the focused existing UI test to verify failure**

Run:

```bash
xcodebuild test \
  -scheme Foil \
  -configuration Debug \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-device-destinations 1 \
  -enableCodeCoverage NO \
  -only-testing:FoilUITests/FoilUITests/testControlCenterShowsSeededReadyState
```

Expected: FAIL because `UITestStateSnapshot` cannot decode the missing `recordingEvents` key.

- [ ] **Step 3: Add recording events to the app snapshot**

In `Foil/UITestingController.swift`, add this nested struct beside `StateSnapshot`:

```swift
private struct RecordingEventSnapshot: Encodable {
    let name: String
    let detail: String?
    let uptimeNanoseconds: UInt64
}
```

Add storage near the window/timer properties:

```swift
private var recordingEvents: [RecordingEventSnapshot] = []
```

Update `StateSnapshot` to include the events:

```swift
private struct StateSnapshot: Encodable {
    let statusText: String
    let sessionTitle: String
    let sessionDetail: String
    let accessibilityText: String
    let accessibilityActionTitle: String?
    let microphoneText: String
    let microphoneActionTitle: String?
    let apiKeyText: String
    let apiKeyActionTitle: String?
    let canStartRecording: Bool
    let recordingEvents: [RecordingEventSnapshot]
}
```

Update `writeStateSnapshot()` so the initializer passes the current events:

```swift
let snapshot = StateSnapshot(
    statusText: appState.statusText,
    sessionTitle: session.title,
    sessionDetail: session.detail,
    accessibilityText: permissionText(for: appState.accessibilityState),
    accessibilityActionTitle: actionTitle(for: appState.accessibilityState, readyTitle: nil, unknownTitle: "Open Settings", needsActionTitle: "Open Settings"),
    microphoneText: permissionText(for: appState.microphoneState),
    microphoneActionTitle: actionTitle(for: appState.microphoneState, readyTitle: nil, unknownTitle: "Check", needsActionTitle: "Open Settings"),
    apiKeyText: permissionText(for: appState.apiKeyState),
    apiKeyActionTitle: actionTitle(for: appState.apiKeyState, readyTitle: nil, unknownTitle: "Add Key", needsActionTitle: "Add Key"),
    canStartRecording: appState.canStartRecordingControl,
    recordingEvents: recordingEvents
)
```

Add helpers near `writeStateSnapshot()`:

```swift
private func appendRecordingEvent(_ name: String, detail: String? = nil) {
    recordingEvents.append(
        RecordingEventSnapshot(
            name: name,
            detail: detail,
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
    )
    writeStateSnapshot()
}

private func clearRecordingEvents() {
    recordingEvents.removeAll()
    writeStateSnapshot()
}
```

- [ ] **Step 4: Run the existing UI test to verify it passes again**

Run the same command from Step 2.

Expected: PASS. This proves the state snapshot remains backward-compatible for existing tests while carrying the new events array.

- [ ] **Step 5: Commit**

```bash
git add Foil/UITestingController.swift FoilUITests/FoilUITests.swift
git commit -m "test: expose recording events in UI test snapshots"
```

---

### Task 2: Add a DEBUG Recording Cue Acceptance Command

**Files:**
- Modify: `Foil/UITestingController.swift`
- Test: `FoilUITests/FoilUITests.swift`

- [ ] **Step 1: Write the failing app-level acceptance test**

In `FoilUITests/FoilUITests.swift`, add this test near `testRecordingSoundPickersShowBuiltInDefaults`:

```swift
func testSelectedStartCueIsUsedBeforeRecorderStarts() {
    relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-recording"])

    postUITestCommand(appCommandNotification, userInfo: ["command": "prepareRecordingCueAcceptance"])
    postUITestCommand(appCommandNotification, userInfo: ["command": "startRecording"])

    let state = waitForUITestStateSnapshot { snapshot in
        snapshot.recordingEvents.contains { $0.name == "audioRecorderStart" }
    }

    guard let events = state?.recordingEvents else {
        XCTFail("Expected recording events in UI-test state snapshot")
        return
    }

    let soundEvent = requireRecordingEvent(named: "startCue", in: events)
    let preRollEvent = requireRecordingEvent(named: "preRollScheduled", in: events)
    let recorderEvent = requireRecordingEvent(named: "audioRecorderStart", in: events)

    XCTAssertEqual(soundEvent.detail, "Submarine")
    XCTAssertLessThan(soundEvent.uptimeNanoseconds, preRollEvent.uptimeNanoseconds)
    XCTAssertLessThan(preRollEvent.uptimeNanoseconds, recorderEvent.uptimeNanoseconds)
    XCTAssertGreaterThanOrEqual(
        recorderEvent.uptimeNanoseconds - soundEvent.uptimeNanoseconds,
        250_000_000,
        "Recorder should not open until the selected start cue has time to play"
    )
}
```

Add this helper near the other private test helpers:

```swift
private func requireRecordingEvent(
    named name: String,
    in events: [UITestRecordingEvent],
    file: StaticString = #filePath,
    line: UInt = #line
) -> UITestRecordingEvent {
    guard let event = events.first(where: { $0.name == name }) else {
        XCTFail("Missing recording event \(name). Events: \(events)", file: file, line: line)
        return UITestRecordingEvent(name: name, detail: nil, uptimeNanoseconds: 0)
    }
    return event
}
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```bash
xcodebuild test \
  -scheme Foil \
  -configuration Debug \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-device-destinations 1 \
  -enableCodeCoverage NO \
  -only-testing:FoilUITests/FoilUITests/testSelectedStartCueIsUsedBeforeRecorderStarts
```

Expected: FAIL because `prepareRecordingCueAcceptance` and `startRecording` app commands do not exist yet.

- [ ] **Step 3: Add a DEBUG acceptance audio stub**

In `Foil/UITestingController.swift`, add this helper near the E2E transcription section:

```swift
#if DEBUG
private final class RecordingCueAcceptanceAudioStub: AudioRecording {
    private let onStartRecording: () -> Void

    init(onStartRecording: @escaping () -> Void) {
        self.onStartRecording = onStartRecording
    }

    func startRecording(deviceID: AudioDeviceID?) throws {
        onStartRecording()
    }

    func stopRecordingAsync(format: AudioFormat) async throws -> URL? {
        nil
    }

    func cancelRecording() {
    }
}
#endif
```

- [ ] **Step 4: Add the app commands**

In `handleAppCommandForUITest(_:)`, extend the `switch command`:

```swift
case "clearRecordingEvents":
    clearRecordingEvents()
case "prepareRecordingCueAcceptance":
    prepareRecordingCueAcceptance()
case "startRecording":
    onStartRecording()
case "stopRecording":
    onStopRecording()
```

Add this method in `UITestingController`:

```swift
private func prepareRecordingCueAcceptance() {
    #if DEBUG
    clearRecordingEvents()
    appState.soundEffectsEnabled = true
    appState.recordingStartSoundCue = .submarine
    appState.recordingEndSoundCue = .pop
    appState.updateAccessibilityState(isTrusted: true)
    appState.updateMicrophoneState(isReady: true)
    appState.apiKeyState = .ready
    appState.setStatus(.idle)

    let soundPlayer = SoundPlayer(defaults: .standard) { [weak self] systemSoundName in
        self?.appendRecordingEvent("startCue", detail: systemSoundName)
    }
    let audioStub = RecordingCueAcceptanceAudioStub { [weak self] in
        self?.appendRecordingEvent("audioRecorderStart")
    }
    let controller = RecordingController(
        audioRecorder: audioStub,
        appState: appState,
        playStartCueBeforeRecording: {
            let played = soundPlayer.playStartSound()
            if played {
                self.appendRecordingEvent("preRollScheduled")
            }
            return played
        },
        startCuePreRollNanoseconds: 300_000_000
    )
    onReplaceRecordingController(controller)
    writeStateSnapshot()
    DiagnosticLog.write("UITesting: recording cue acceptance prepared")
    #else
    DiagnosticLog.write("UITesting: recording cue acceptance skipped outside DEBUG")
    #endif
}
```

The `preRollScheduled` event is recorded inside the injected `playStartCueBeforeRecording` closure because that is the exact point where a real start cue was requested and `RecordingController` is about to schedule the pre-roll.

- [ ] **Step 5: Run the new test to verify it passes**

Run the command from Step 2.

Expected: PASS. The test should observe `startCue` with detail `Submarine`, then `preRollScheduled`, then `audioRecorderStart`, with at least 250ms between cue request and recorder start.

- [ ] **Step 6: Commit**

```bash
git add Foil/UITestingController.swift FoilUITests/FoilUITests.swift
git commit -m "test: cover selected start cue in recording path"
```

---

### Task 3: Add the Acceptance Test to CI Focused UI Smoke

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add the test to the focused UI smoke command**

In `.github/workflows/ci.yml`, add this line to the existing `Run focused UI smoke` `xcodebuild test` block:

```bash
            -only-testing:FoilUITests/FoilUITests/testSelectedStartCueIsUsedBeforeRecorderStarts \
```

Place it near the existing recording/settings tests, after:

```bash
            -only-testing:FoilUITests/FoilUITests/testCustomHotkeyRecorderIsAccessibleButton \
```

- [ ] **Step 2: Run the same UI test command CI will run**

Run:

```bash
xcodebuild test \
  -scheme Foil \
  -configuration Debug \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-device-destinations 1 \
  -enableCodeCoverage NO \
  -only-testing:FoilUITests/FoilUITests/testControlCenterShowsSeededReadyState \
  -only-testing:FoilUITests/FoilUITests/testSetupCheckCanBeRunInline \
  -only-testing:FoilUITests/FoilUITests/testMicrophoneUnknownShowsCheckAction \
  -only-testing:FoilUITests/FoilUITests/testMicrophoneDeniedShowsOpenSettingsAction \
  -only-testing:FoilUITests/FoilUITests/testSettingsButtonOpensSettingsWindow \
  -only-testing:FoilUITests/FoilUITests/testProviderQADefaultsToGroqPreset \
  -only-testing:FoilUITests/FoilUITests/testProviderQALocalWhisperPresetShowsExpectedSettings \
  -only-testing:FoilUITests/FoilUITests/testProviderQALocalWhisperSetupHelperShowsModelCommands \
  -only-testing:FoilUITests/FoilUITests/testSimulatedRecordingUsesCurrentAppPasteWhenAsyncIsOff \
  -only-testing:FoilUITests/FoilUITests/testSimulatedRecordingUsesAsyncPasteWhenEnabled \
  -only-testing:FoilUITests/FoilUITests/testSimulatedRecordingFailureKeepsRetryVisibleInHistory \
  -only-testing:FoilUITests/FoilUITests/testFloatingWarningShowsExpandedClipboardContext \
  -only-testing:FoilUITests/FoilUITests/testFloatingStatusAutoHidesAfterSuccessWhenEnabled \
  -only-testing:FoilUITests/FoilUITests/testFloatingStatusIsDisabledByDefault \
  -only-testing:FoilUITests/FoilUITests/testMovedPreferencesLiveInSettingsPanes \
  -only-testing:FoilUITests/FoilUITests/testCustomHotkeyRecorderIsAccessibleButton \
  -only-testing:FoilUITests/FoilUITests/testSelectedStartCueIsUsedBeforeRecorderStarts \
  -only-testing:FoilUITests/FoilUITests/testHelpButtonTargetsCanonicalTroubleshootingURL
```

Expected: PASS. If a pre-existing UI smoke test flakes, rerun once and record both results in the PR body.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: include recording cue acceptance smoke"
```

---

### Task 4: Keep the Hardware QA Boundary Explicit

**Files:**
- Modify: `docs/superpowers/plans/2026-05-14-e2e-transcription-testing.md` or create `docs/testing.md` if the repo does not already have a general testing guide.

- [ ] **Step 1: Add a short testing note**

Add this section:

```markdown
## Recording Cue Automation Boundary

The normal CI suite verifies that a saved start cue is used by the recording control path and that the recorder opens only after the start-cue pre-roll. This is hardware-free and runs on GitHub-hosted macOS runners.

Normal CI does not prove that a human can hear the cue through a specific Bluetooth output device. That requires a live Mac with known audio routing or a virtual audio capture setup. Keep that as optional release QA rather than a PR gate.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/2026-05-14-e2e-transcription-testing.md docs/testing.md
git commit -m "docs: document recording cue automation boundary"
```

If only one of those docs files exists or is created, stage only that file.

---

## Verification

Run these commands before opening the PR:

```bash
xcodebuild test \
  -project Foil.xcodeproj \
  -scheme Foil \
  -only-testing:FoilTests/RecordingControllerMockTests/testStartCuePlaysBeforeAudioRecorderStarts \
  -only-testing:FoilTests/RecordingControllerMockTests/testStartCuePreRollDelaysAudioRecorderStart \
  -only-testing:FoilTests/RecordingControllerMockTests/testStopDuringStartCuePreRollCancelsAudioRecorderStart
```

Expected: PASS.

```bash
xcodebuild test \
  -scheme Foil \
  -configuration Debug \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-device-destinations 1 \
  -enableCodeCoverage NO \
  -only-testing:FoilUITests/FoilUITests/testSelectedStartCueIsUsedBeforeRecorderStarts
```

Expected: PASS.

```bash
git diff --check
```

Expected: no output.

## Burden Of Proof

Strongest realistic failure mode: the settings preview and persistence work, but the push-to-talk/control recording path does not use the selected cue or opens the microphone before the cue can be heard.

Proof required in final handoff:

- The new UI test shows `startCue` detail `Submarine`.
- The same test shows `audioRecorderStart` after `startCue`.
- The elapsed monotonic time from `startCue` to `audioRecorderStart` is at least `250_000_000` ns.
- Focused UI smoke includes the new test in CI.

## Execution Choice

Plan complete and saved to `docs/superpowers/plans/2026-06-02-recording-cue-acceptance-tests.md`. Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using executing-plans, batch execution with checkpoints.


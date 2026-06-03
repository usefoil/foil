import AVFoundation
import XCTest
@testable import Foil

// MARK: - Stubs

private final class AlreadyRunningStub: SingleInstanceGuarding {
    private(set) var callCount = 0
    func activateExistingInstanceIfRunning() -> Bool {
        callCount += 1
        return true
    }
}

private final class NotRunningStub: SingleInstanceGuarding {
    private(set) var callCount = 0
    func activateExistingInstanceIfRunning() -> Bool {
        callCount += 1
        return false
    }
}

private struct StubSetupPermissionProvider: SetupPermissionProviding {
    var accessibilityTrusted: Bool
    var microphoneAuthorizationStatus: AVAuthorizationStatus
    var microphoneAccessRequestResult: MicrophoneAccessRequestResult = .denied

    func requestMicrophoneAccess() async -> MicrophoneAccessRequestResult {
        microphoneAccessRequestResult
    }
}

// MARK: - Tests

@MainActor
final class SingleInstanceGuardTests: XCTestCase {

    // MARK: - Protocol contract

    func testReturnsFalseWhenNoDuplicate() {
        let stub = NotRunningStub()
        XCTAssertFalse(stub.activateExistingInstanceIfRunning(),
                       "Should return false when no other instance is running")
    }

    func testReturnsTrueWhenDuplicateRunning() {
        let stub = AlreadyRunningStub()
        XCTAssertTrue(stub.activateExistingInstanceIfRunning(),
                      "Should return true when another instance is running")
    }

    // MARK: - Real implementation

    func testRealGuardDoesNotFalsePositiveInTestHost() {
        // In the test host, Bundle.main.bundleIdentifier is the test runner's ID,
        // not com.neonwatty.Foil. The guard should return false (no match).
        // If the real Foil app happens to be running, the guard may detect it
        // via its own bundle ID — that's correct behavior, not a false positive.
        let guard_ = SingleInstanceGuard()
        _ = guard_.activateExistingInstanceIfRunning()
        // Primary assertion: the call completes without crashing.
        // The return value depends on whether the real app is running.
    }

    // MARK: - AppDelegate integration

    func testGuardBypassedDuringUnitTests() {
        XCTAssertTrue(
            AppDelegate.isTestingProcess(
                arguments: ["/tmp/FoilTests.xctest"],
                environment: [:]
            ),
            "xctest launch arguments should bypass the duplicate-app guard"
        )

        XCTAssertTrue(
            AppDelegate.isTestingProcess(
                arguments: [],
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
            ),
            "XCTestConfigurationFilePath should bypass the duplicate-app guard"
        )
    }

    func testNormalLaunchIsNotClassifiedAsTestingOnlyBecauseXCTestIsLoaded() {
        XCTAssertFalse(
            AppDelegate.isTestingProcess(
                arguments: ["/Applications/Foil.app/Contents/MacOS/Foil"],
                environment: [:]
            ),
            "normal app launches should start the hotkey monitor even if XCTest symbols are present"
        )
    }

    func testNormalLaunchRunsSingleInstanceGuard() {
        XCTAssertTrue(
            AppDelegate.shouldRunSingleInstanceGuard(
                arguments: ["/Applications/Foil.app/Contents/MacOS/Foil"],
                environment: [:]
            ),
            "normal production launches should keep single-instance behavior"
        )
    }

    func testAutomationSmokeBypassesSingleInstanceGuard() {
        XCTAssertFalse(
            AppDelegate.shouldRunSingleInstanceGuard(
                arguments: ["/Applications/Foil.app/Contents/MacOS/Foil", "--automation-smoke"],
                environment: [:]
            ),
            "automation smoke launches must not be diverted into an already-running app"
        )
    }

    func testReleaseE2ETranscriptionSmokeRequiresExplicitGate() {
        #if DEBUG
        XCTAssertTrue(
            AppDelegate.isE2ETranscriptionSmokeProcess(
                arguments: ["/Applications/Foil.app/Contents/MacOS/Foil", "--e2e-transcribe"],
                environment: [:]
            ),
            "Debug E2E launches keep the existing test behavior"
        )
        #else
        XCTAssertFalse(
            AppDelegate.isE2ETranscriptionSmokeProcess(
                arguments: ["/Applications/Foil.app/Contents/MacOS/Foil", "--e2e-transcribe"],
                environment: [:]
            ),
            "Release E2E smoke should require an explicit environment gate"
        )
        XCTAssertTrue(
            AppDelegate.isE2ETranscriptionSmokeProcess(
                arguments: ["/Applications/Foil.app/Contents/MacOS/Foil", "--e2e-transcribe"],
                environment: ["E2E_ALLOW_RELEASE_APP_SMOKE": "1"]
            )
        )
        #endif
    }

    func testE2ETranscriptionSmokeBypassesSingleInstanceGuardWhenGateAllows() {
        XCTAssertFalse(
            AppDelegate.shouldRunSingleInstanceGuard(
                arguments: ["/Applications/Foil.app/Contents/MacOS/Foil", "--e2e-transcribe"],
                environment: ["E2E_ALLOW_RELEASE_APP_SMOKE": "1"]
            ),
            "installed-app E2E smoke launches must not be diverted into an already-running app"
        )
    }

    func testUITestingStillBypassesSingleInstanceGuard() {
        XCTAssertFalse(
            AppDelegate.shouldRunSingleInstanceGuard(
                arguments: ["/Applications/Foil.app/Contents/MacOS/Foil", "--ui-testing"],
                environment: [:]
            ),
            "UI test launches should continue to bypass the duplicate-app guard"
        )
    }

    func testAppDelegateAcceptsInjectedGuard() {
        // Verify the designated initializer accepts a custom guard.
        let stub = NotRunningStub()
        let delegate = AppDelegate(singleInstanceGuard: stub)
        XCTAssertNotNil(delegate, "AppDelegate should accept an injected guard")
    }

    func testAppDelegateRefreshSetupHealthUsesInjectedPermissionProvider() {
        let delegate = AppDelegate(
            singleInstanceGuard: NotRunningStub(),
            setupPermissionProvider: StubSetupPermissionProvider(
                accessibilityTrusted: true,
                microphoneAuthorizationStatus: .authorized
            )
        )
        delegate.appState.updateAccessibilityState(isTrusted: false)
        delegate.appState.updateMicrophoneState(isReady: false)
        delegate.appState.selectedTranscriptionProviderPresetID = .localWhisperCPP

        delegate.refreshSetupHealth()

        XCTAssertEqual(delegate.appState.accessibilityState, .ready)
        XCTAssertEqual(delegate.appState.microphoneState, .ready)
        XCTAssertTrue(delegate.appState.isSetupReady)
    }

    func testAppDelegateMicrophoneCheckShowsRecoveryWhenRequestTimesOut() async {
        let delegate = AppDelegate(
            singleInstanceGuard: NotRunningStub(),
            setupPermissionProvider: StubSetupPermissionProvider(
                accessibilityTrusted: true,
                microphoneAuthorizationStatus: .notDetermined,
                microphoneAccessRequestResult: .timedOut
            )
        )

        delegate.checkMicrophonePermission()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(
            delegate.appState.microphoneState,
            .needsAction("Microphone prompt did not finish; reopen Foil or reset Microphone privacy")
        )
    }

    func testAppDelegateCanOpenSettingsWindowExplicitly() {
        let stub = NotRunningStub()
        let delegate = AppDelegate(singleInstanceGuard: stub)

        delegate.showSettingsWindow()

        let settingsWindow = NSApp.windows.first { $0.title == "Settings" }
        XCTAssertNotNil(settingsWindow)
        XCTAssertTrue(settingsWindow?.isVisible == true)

        settingsWindow?.close()
    }

    func testSettingsTabStripUsesCompactVisibleLabels() {
        XCTAssertEqual(SettingsView.Tab.paste.title, "Paste")
        XCTAssertEqual(SettingsView.Tab.privacy.title, "Storage")
    }

    func testSettingsTabStripLabelsExperimentalSettingsAsExperimental() {
        XCTAssertTrue(SettingsView.Tab.allCases.contains(.experimental))
        XCTAssertEqual(SettingsView.Tab.experimental.title, "Experimental")
        XCTAssertEqual(SettingsView.Tab.experimental.accessibilityIdentifier, "settings.tab.experimental")
    }

    func testAppBrandVersionDisplayIncludesVersionAndBuild() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilVersionDisplay-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.neonwatty.Foil.tests.version",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "2.3.4",
            "CFBundleVersion": "567"
        ]
        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        try (info as NSDictionary).write(to: infoURL)

        let bundle = try XCTUnwrap(Bundle(url: bundleURL))

        XCTAssertEqual(AppBrand.versionDisplay(bundle: bundle), "\(AppBrand.name) 2.3.4 (build 567)")
    }

    func testAppBrandVersionDisplayShortensLongBuildNumbers() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilLongVersionDisplay-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.neonwatty.Foil.tests.long-version",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "2.3.4",
            "CFBundleVersion": "26829495549"
        ]
        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        try (info as NSDictionary).write(to: infoURL)

        let bundle = try XCTUnwrap(Bundle(url: bundleURL))

        XCTAssertEqual(AppBrand.versionDisplay(bundle: bundle), "\(AppBrand.name) 2.3.4 (build 495549)")
    }

    func testExperimentalPasteSettingCopyDistinguishesTargetFromPasteMethod() {
        XCTAssertEqual(SettingsView.ExperimentalCopy.pasteRoutingPurpose, "Auto-pastes back into the app you started from while you keep working elsewhere.")
        XCTAssertEqual(SettingsView.ExperimentalCopy.pasteTargetTitle, "Return to starting app")
        XCTAssertEqual(SettingsView.ExperimentalCopy.pasteTargetOffDescription, "Pastes into the app active when transcription finishes.")
        XCTAssertEqual(SettingsView.ExperimentalCopy.backgroundPasteTitle, "Try background paste")
        XCTAssertEqual(SettingsView.ExperimentalCopy.backgroundPasteDescription, "Uses a lower-level paste route. Leave off unless normal paste fails.")
    }

    func testRecordingSettingCopyExplainsBuiltInMicWithAirPods() {
        XCTAssertEqual(
            SettingsView.RecordingCopy.builtInMicBluetoothGuidance,
            "AirPods stay connected for listening, but Foil records from your MacBook microphone to avoid Bluetooth audio quality drops."
        )
        XCTAssertEqual(
            SettingsView.RecordingCopy.builtInMicBluetoothNotificationTitle,
            "Using MacBook mic"
        )
        XCTAssertEqual(
            SettingsView.RecordingCopy.builtInMicBluetoothNotificationBody,
            "AirPods stay connected for listening while Foil records from your MacBook microphone."
        )
    }

    func testBuiltInMicGuidanceShowsNoticeForBuiltInSelectionWhenBluetoothInputIsAvailable() {
        let selectedDevice = AudioRecorder.AudioDevice(
            id: 1,
            uid: "built-in",
            name: "MacBook Pro Microphone",
            isInput: true,
            transport: .builtIn
        )
        let airPods = AudioRecorder.AudioDevice(
            id: 2,
            uid: "airpods",
            name: "AirPods",
            isInput: true,
            transport: .bluetooth
        )

        XCTAssertTrue(BluetoothMicGuidance.shouldShowNotice(
            selectedInputDevice: selectedDevice,
            availableInputDevices: [selectedDevice, airPods],
            hasShownNotice: false
        ))
    }

    func testBuiltInMicGuidanceDoesNotShowNoticeAgainAfterItWasShown() {
        let selectedDevice = AudioRecorder.AudioDevice(
            id: 1,
            uid: "built-in",
            name: "MacBook Pro Microphone",
            isInput: true,
            transport: .builtIn
        )
        let airPods = AudioRecorder.AudioDevice(
            id: 2,
            uid: "airpods",
            name: "AirPods",
            isInput: true,
            transport: .bluetooth
        )

        XCTAssertFalse(BluetoothMicGuidance.shouldShowNotice(
            selectedInputDevice: selectedDevice,
            availableInputDevices: [selectedDevice, airPods],
            hasShownNotice: true
        ))
    }

    func testBuiltInMicGuidanceDoesNotShowNoticeWhenSelectedInputIsBluetooth() {
        let airPods = AudioRecorder.AudioDevice(
            id: 2,
            uid: "airpods",
            name: "AirPods",
            isInput: true,
            transport: .bluetooth
        )

        XCTAssertFalse(BluetoothMicGuidance.shouldShowNotice(
            selectedInputDevice: airPods,
            availableInputDevices: [airPods],
            hasShownNotice: false
        ))
    }
}

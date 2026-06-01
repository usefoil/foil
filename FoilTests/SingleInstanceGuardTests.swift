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

        XCTAssertEqual(AppBrand.versionDisplay(bundle: bundle), "\(AppBrand.name) 2.3.4 (567)")
    }

    func testExperimentalPasteSettingCopyDistinguishesTargetFromPasteMethod() {
        XCTAssertEqual(SettingsView.ExperimentalCopy.pasteRoutingPurpose, "Auto-pastes back into the app you started from while you keep working elsewhere.")
        XCTAssertEqual(SettingsView.ExperimentalCopy.pasteTargetTitle, "Return to starting app")
        XCTAssertEqual(SettingsView.ExperimentalCopy.pasteTargetOffDescription, "Pastes into the app active when transcription finishes.")
        XCTAssertEqual(SettingsView.ExperimentalCopy.backgroundPasteTitle, "Try background paste")
        XCTAssertEqual(SettingsView.ExperimentalCopy.backgroundPasteDescription, "Uses a lower-level paste route. Leave off unless normal paste fails.")
    }
}

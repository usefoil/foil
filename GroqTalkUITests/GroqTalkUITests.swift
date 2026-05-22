import XCTest

final class GroqTalkUITests: XCTestCase {
    private var app: XCUIApplication!
    private let openHistoryNotification = Notification.Name("com.neonwatty.GroqTalk.uiTests.openHistory")
    private let openSettingsNotification = Notification.Name("com.neonwatty.GroqTalk.uiTests.openSettings")
    private let openHelpNotification = Notification.Name("com.neonwatty.GroqTalk.uiTests.openHelp")
    private let runSetupCheckNotification = Notification.Name("com.neonwatty.GroqTalk.uiTests.runSetupCheck")
    private let stateSnapshotURL =
        URL(fileURLWithPath: "/tmp").appendingPathComponent("groqtalk-ui-tests-state-\(ProcessInfo.processInfo.processIdentifier).json")
    private let openedURLPath =
        URL(fileURLWithPath: "/tmp").appendingPathComponent("groqtalk-ui-tests-opened-url-\(ProcessInfo.processInfo.processIdentifier).txt")

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
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--seed-history"
        ]
        app.launchEnvironment["GROQTALK_UITEST_STATE_PATH"] = stateSnapshotURL.path
        app.launchEnvironment["GROQTALK_UITEST_OPENED_URL_PATH"] = openedURLPath.path
        removeUITestStateSnapshot()
        removeOpenedURLRecord()
        app.launch()
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testControlCenterShowsSeededReadyState() {
        let state = waitForUITestStateSnapshot { $0.sessionTitle == "Ready" }
        XCTAssertEqual(state?.statusText, "Ready")
        XCTAssertEqual(state?.sessionDetail, "Right Command · Paste target is the current app")
        XCTAssertEqual(state?.accessibilityText, "Ready")
        XCTAssertEqual(state?.microphoneText, "Ready")
        XCTAssertEqual(state?.apiKeyText, "Ready")
        XCTAssertNil(state?.accessibilityActionTitle)
        XCTAssertNil(state?.microphoneActionTitle)
        XCTAssertNil(state?.apiKeyActionTitle)
        XCTAssertEqual(state?.canStartRecording, true)
        XCTAssertFalse(elementExists(id: "menu.setup.panel", timeout: 1))
        XCTAssertFalse(app.checkBoxes["Return to starting app"].exists)
        XCTAssertFalse(app.checkBoxes["Show floating status"].exists)
        XCTAssertFalse(app.checkBoxes["Mock Transcription"].exists)
    }

    func testSetupCheckCanBeRunInline() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-setup-unknown"])
        postUITestCommand(runSetupCheckNotification)

        XCTAssertTrue(app.staticTexts["Setup Tested"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Ready to record"].exists)
    }

    func testSetupFailuresShowRecoveryDetails() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--seed-setup-failures"
        ]
        app.launch()

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testUnknownSetupStateDoesNotShowReadySession() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--seed-setup-unknown"
        ]
        app.launchEnvironment["GROQTALK_UITEST_STATE_PATH"] = stateSnapshotURL.path
        removeUITestStateSnapshot()
        app.launch()

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        let state = waitForUITestStateSnapshot { $0.sessionTitle == "Setup needed" }
        XCTAssertEqual(state?.sessionDetail, "Check Accessibility before recording")
        XCTAssertEqual(state?.accessibilityText, "Not checked")
        XCTAssertEqual(state?.accessibilityActionTitle, "Open Settings")
        XCTAssertTrue(app.staticTexts["Enable Accessibility before recording."].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Right Command · Pastes into current app"].exists)
    }

    func testMicrophoneUnknownShowsCheckAction() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--seed-microphone-unknown"
        ]
        app.launchEnvironment["GROQTALK_UITEST_STATE_PATH"] = stateSnapshotURL.path
        removeUITestStateSnapshot()
        app.launch()

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        let state = waitForUITestStateSnapshot { $0.microphoneText == "Not checked" }
        XCTAssertEqual(state?.accessibilityText, "Ready")
        XCTAssertEqual(state?.microphoneActionTitle, "Check")
        XCTAssertEqual(state?.sessionTitle, "Setup needed")
        XCTAssertTrue(app.staticTexts["Check microphone access before recording."].waitForExistence(timeout: 2), app.debugDescription)
    }

    func testMicrophoneDeniedShowsOpenSettingsAction() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--seed-microphone-denied"
        ]
        app.launchEnvironment["GROQTALK_UITEST_STATE_PATH"] = stateSnapshotURL.path
        removeUITestStateSnapshot()
        app.launch()

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        let state = waitForUITestStateSnapshot { $0.microphoneText == "Allow microphone access" }
        XCTAssertEqual(state?.accessibilityText, "Ready")
        XCTAssertEqual(state?.microphoneActionTitle, "Open Settings")
        XCTAssertEqual(state?.sessionTitle, "Setup needed")
        XCTAssertTrue(app.staticTexts["Allow microphone access before recording."].waitForExistence(timeout: 2), app.debugDescription)
    }

    func testOnboardingMicrophoneStepCanCheckPermission() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--show-onboarding",
            "--seed-microphone-unknown"
        ]
        app.launch()

        XCTAssertTrue(app.windows["Welcome to GroqTalk"].waitForExistence(timeout: 5), app.debugDescription)
        clickButton(id: "onboarding.nextButton", fallbackLabel: "Next")
        clickButton(id: "onboarding.nextButton", fallbackLabel: "Next")
        clickButton(id: "onboarding.nextButton", fallbackLabel: "Next")

        XCTAssertTrue(app.staticTexts["Microphone Access"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Checking status"].exists || app.staticTexts["Checking..."].exists)
        assertButtonExists(id: "onboarding.checkMicrophoneButton", fallbackLabel: "Check Microphone Access")

        clickButton(id: "onboarding.checkMicrophoneButton", fallbackLabel: "Check Microphone Access")
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 2), app.debugDescription)
    }

    func testOnboardingCompletionKeepsMenuBarAppRunning() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--show-onboarding",
            "--seed-setup-ready"
        ]
        app.launch()

        XCTAssertTrue(app.windows["Welcome to GroqTalk"].waitForExistence(timeout: 5), app.debugDescription)

        while button(id: "onboarding.nextButton", fallbackLabel: "Next").exists {
            clickButton(id: "onboarding.nextButton", fallbackLabel: "Next")
        }

        XCTAssertTrue(button(id: "onboarding.getStartedButton", fallbackLabel: "Get Started").waitForExistence(timeout: 2), app.debugDescription)
        clickButton(id: "onboarding.getStartedButton", fallbackLabel: "Get Started")

        XCTAssertFalse(app.windows["Welcome to GroqTalk"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
    }

    func testOnboardingLocalProviderDoesNotRequireAPIKey() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--show-onboarding",
            "--seed-setup-ready"
        ]
        app.launch()

        let onboardingWindow = app.windows["Welcome to GroqTalk"]
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 5), app.debugDescription)
        let providerPicker = app.popUpButtons["onboarding.providerPicker"].exists
            ? app.popUpButtons["onboarding.providerPicker"]
            : onboardingWindow.popUpButtons.firstMatch
        XCTAssertTrue(providerPicker.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(providerPicker)
        let localProvider = app.menuItems["Local whisper.cpp"].firstMatch
        XCTAssertTrue(localProvider.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(localProvider)

        XCTAssertTrue(staticTextLabelOrValueContaining("Audio stays on this Mac").waitForExistence(timeout: 2), app.debugDescription)
        clickButton(id: "onboarding.nextButton", fallbackLabel: "Next")

        XCTAssertTrue(app.staticTexts["Credentials Optional"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["No API key required"].exists || app.staticTexts["Ready"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["onboarding.addApiKeyButton"].exists || app.buttons["Add API Key"].exists)
        XCTAssertTrue(
            app.buttons["onboarding.openTranscriptionSettingsButton"].exists
                || app.buttons["Open Transcription Settings"].exists,
            app.debugDescription
        )
    }

    func testHistoryWindowOpensAndSearchesSeededRecords() {
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        let searchField = app.textFields["Search transcriptions..."]
        XCTAssertTrue(searchField.exists)
        replaceText(in: searchField, with: "Second searchable")

        XCTAssertTrue(app.staticTexts["Second searchable transcript."].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Seeded transcript for UI testing."].exists)

        replaceText(in: searchField, with: "no matching transcript")
        XCTAssertTrue(staticTextLabelOrValueContaining("No matches", in: historyPanel).waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertFalse(historyPanel.staticTexts["Second searchable transcript."].exists)
    }

    func testHistoryFilterShowsFailedRecords() {
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        XCTAssertTrue(app.buttons["All"].isEnabled)
        app.buttons["Failed"].click()
        XCTAssertTrue(app.buttons["Failed"].isEnabled)

        XCTAssertTrue(app.staticTexts["Seeded network failure"].waitForExistence(timeout: 2))
    }

    func testHistoryDeleteAndClearActions() {
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        XCTAssertTrue(app.staticTexts["Second searchable transcript."].exists)
        app.buttons["history.row.deleteButton"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Delete History Item?"].waitForExistence(timeout: 2))
        clickAlertButton("Cancel")
        XCTAssertTrue(app.staticTexts["Seeded network failure"].waitForExistence(timeout: 2))

        relaunchWithSeededHistory()
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        clickButton(id: "history.clearButton", fallbackLabel: "Clear")
        XCTAssertTrue(app.staticTexts["Clear History?"].waitForExistence(timeout: 2))
        clickAlertButton("Clear History")
        XCTAssertTrue(
            historyEmptyStateAppeared(timeout: 5),
            app.debugDescription
        )
    }

    func testHistoryDetailAllowsEditingAndExport() {
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))
        assertButtonExists(id: "history.exportButton", fallbackLabel: "Export")

        let detailsButtons = historyPanel.buttons.matching(NSPredicate(format: "label == %@", "Details"))
        XCTAssertGreaterThanOrEqual(detailsButtons.count, 2, app.debugDescription)
        detailsButtons.element(boundBy: 1).click()
        let editor = app.textViews["history.detail.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Copy"].exists)
        XCTAssertTrue(app.buttons["Paste"].exists)
        XCTAssertTrue(app.buttons["Delete"].exists)
        clickButton(id: "history.detail.doneButton", fallbackLabel: "Done")
    }

    func testSettingsButtonOpensSettingsWindow() {
        openSettingsPanel()
        XCTAssertTrue(waitForSettingsPanel(timeout: 4))
        XCTAssertTrue(providerPickerExists(timeout: 6) || elementExists(id: "settings.root", timeout: 4))
        XCTAssertTrue(app.staticTexts["Transcription"].exists || app.staticTexts["Provider"].exists)
    }

    func testProviderQADefaultsToGroqPreset() {
        launchForProviderQA()
        openTranscriptionSettingsPanel()

        assertProviderPickerExists()
        XCTAssertEqual(providerPicker.value as? String, "Groq")
        XCTAssertTrue(
            app.staticTexts["Large V3 Turbo"].exists
                || app.staticTexts["Whisper model"].exists
                || (app.popUpButtons["menu.settings.whisperModelPicker"].value as? String) == "Large V3 Turbo",
            app.debugDescription
        )
        XCTAssertTrue(staticTextLabelOrValueContaining("Audio is sent to Groq for transcription").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.buttons["settings.changeApiKeyButton"].exists || app.buttons["menu.settings.changeApiKeyButton"].exists || app.buttons["Change API Key"].exists || app.buttons["Change..."].exists)
        XCTAssertTrue(app.staticTexts["After transcription"].exists || app.staticTexts["Cleanup"].exists || app.staticTexts["Transcript cleanup"].exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Cleanup requires a Groq-compatible chat provider."].exists)
        XCTAssertFalse(app.staticTexts["Cleanup requires a Groq-compatible chat provider. Custom transcription currently uses raw transcripts."].exists)
    }

    func testProviderQALocalWhisperPresetShowsExpectedSettings() {
        launchForProviderQA(extraArguments: ["--seed-local-provider"])
        openTranscriptionSettingsPanel()

        assertProviderPickerExists()
        XCTAssertTrue((providerPicker.value as? String) == "Local whisper.cpp" || app.staticTexts["Local whisper.cpp"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["http://127.0.0.1:8080/v1"].exists || app.staticTexts["127.0.0.1:8080/v1"].exists, app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Audio stays on this Mac").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("API key is optional").exists
                      || staticTextLabelOrValueContaining("local OpenAI-compatible").exists
                      || elementExists(id: "settings.localProviderHelp", timeout: 1),
                      app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Start the local whisper-server first").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.buttons["Test connection"].exists || app.buttons["settings.testProviderConnectionButton"].exists || app.buttons["menu.settings.testProviderConnectionButton"].exists, app.debugDescription)
        XCTAssertTrue(
            app.staticTexts["Cleanup requires a Groq-compatible chat provider."].waitForExistence(timeout: 2)
                || app.staticTexts["Cleanup requires a Groq-compatible chat provider. Custom transcription currently uses raw transcripts."].waitForExistence(timeout: 2),
            app.debugDescription
        )
    }

    func testProviderQALocalWhisperCanBeSelectedFromDefaultSettings() {
        launchForProviderQA()
        openTranscriptionSettingsPanel()

        assertProviderPickerExists()
        XCTAssertEqual(providerPicker.value as? String, "Groq")

        selectProviderPreset("Local whisper.cpp")

        XCTAssertTrue((providerPicker.value as? String) == "Local whisper.cpp" || app.staticTexts["Local whisper.cpp"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["http://127.0.0.1:8080/v1"].waitForExistence(timeout: 2) || app.staticTexts["127.0.0.1:8080/v1"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["whisper-1"].exists || staticTextContaining("whisper-1").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Install whisper.cpp").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(providerConnectionButton().waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(
            app.staticTexts["Cleanup requires a Groq-compatible chat provider."].waitForExistence(timeout: 2)
                || app.staticTexts["Cleanup requires a Groq-compatible chat provider. Custom transcription currently uses raw transcripts."].waitForExistence(timeout: 2),
            app.debugDescription
        )
    }

    func testProviderQALocalWhisperSetupHelperShowsModelCommands() {
        launchForProviderQA(extraArguments: ["--seed-local-provider"])
        openTranscriptionSettingsPanel()

        XCTAssertTrue(elementExists(id: "settings.localWhisperSetupModelPicker", timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Recommended starter model").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("whisper-1").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("--model ggml-base.en.bin").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("mkdir -p ~/Developer").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git ~/Developer/whisper.cpp").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("cmake -B build -DWHISPER_BUILD_TESTS=OFF").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("download-ggml-model.sh base.en").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("--inference-path /v1/audio/transcriptions").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.localWhisperCloneCommand.copyButton", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.localWhisperBuildCommand.copyButton", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.localWhisperDownloadCommand.copyButton", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.localWhisperStartServerCommand.copyButton", timeout: 2), app.debugDescription)
    }

    func testProviderQALocalWhisperSelectionPersistsAcrossRelaunch() {
        launchForProviderQA()
        openTranscriptionSettingsPanel()

        selectProviderPreset("Local whisper.cpp")
        XCTAssertTrue((providerPicker.value as? String) == "Local whisper.cpp" || app.staticTexts["Local whisper.cpp"].exists, app.debugDescription)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--seed-history"
        ]
        app.launchEnvironment["GROQTALK_UITEST_STATE_PATH"] = stateSnapshotURL.path
        removeUITestStateSnapshot()
        app.launch()
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        openTranscriptionSettingsPanel()

        XCTAssertTrue((providerPicker.value as? String) == "Local whisper.cpp" || app.staticTexts["Local whisper.cpp"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["http://127.0.0.1:8080/v1"].waitForExistence(timeout: 2) || app.staticTexts["127.0.0.1:8080/v1"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["whisper-1"].exists || staticTextContaining("whisper-1").waitForExistence(timeout: 2), app.debugDescription)
    }

    func testProviderQAInvalidCustomBaseURLShowsValidationStatus() {
        launchForProviderQA(extraArguments: ["--seed-invalid-custom-provider"])
        openTranscriptionSettingsPanel()

        let testConnectionButton = providerConnectionButton()
        XCTAssertTrue(testConnectionButton.waitForExistence(timeout: 2), app.debugDescription)
        testConnectionButton.click()

        XCTAssertTrue(
            app.staticTexts["Invalid base URL. Use an http:// or https:// URL."].waitForExistence(timeout: 2),
            app.debugDescription
        )
    }

    func testProviderQACustomProviderPersistsAcrossRelaunch() {
        launchForProviderQA(extraArguments: ["--seed-custom-provider"])
        openTranscriptionSettingsPanel()

        XCTAssertTrue(staticTextLabelOrValueContaining("Audio is sent to the OpenAI-compatible endpoint").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Use Test connection after changing the base URL or model").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(customBaseURLField.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(customBaseURLField.value as? String, "http://127.0.0.1:9090/v1")
        XCTAssertEqual(customModelField.value as? String, "tiny-test-model")

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--seed-history"
        ]
        app.launch()
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        openTranscriptionSettingsPanel()

        XCTAssertTrue(customBaseURLField.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(customBaseURLField.value as? String, "http://127.0.0.1:9090/v1")
        XCTAssertEqual(customModelField.value as? String, "tiny-test-model")
    }

    func testMockTogglePersistsAcrossLaunches() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-experimental"])
        openSettingsPanel()

        let toggle = checkBox(id: "settings.mockToggle", fallbackLabel: "Mock transcription")
        XCTAssertTrue(toggle.exists)
        clickElement(toggle)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--seed-history",
            "--settings-tab-experimental"
        ]
        app.launch()

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5))
        openSettingsPanel()
        XCTAssertTrue(checkBox(id: "settings.mockToggle", fallbackLabel: "Mock transcription").exists)
    }

    func testSimulatedRecordingUsesCurrentAppPasteWhenAsyncIsOff() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--simulate-success-after-launch"])

        XCTAssertTrue(waitForSessionTitle("Transcribing", timeout: 2))
        XCTAssertTrue(waitForSessionTitle("Cleaning up", timeout: 2))
        XCTAssertTrue(waitForSessionTitle("Pasting", timeout: 2))
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["Done"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Mock async paste transcript"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Clipboard restored"].exists)
    }

    func testSimulatedRecordingUsesAsyncPasteWhenEnabled() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-async-paste-enabled", "--simulate-success-after-launch"])

        XCTAssertTrue(waitForSessionTitle("Transcribing", timeout: 2))
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Mock async paste transcript"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Pasted into the test target"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Target: GroqTalk UI Test"].exists)
    }

    func testSimulatedRecordingFailureKeepsRetryVisibleInHistory() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--simulate-failure-after-launch"])

        XCTAssertTrue(app.staticTexts["Simulated transcription failure"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Open History for details"].exists)

        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))
        XCTAssertTrue(app.staticTexts["Simulated transcription failure"].waitForExistence(timeout: 2))
    }

    func testTranscribingStateShowsCancelTranscriptionAction() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-transcribing"])

        XCTAssertTrue(waitForSessionTitle("Transcribing", timeout: 4), app.debugDescription)
        let cancelButton = app.buttons["menu.recording.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(cancelButton.label, "Cancel transcription")
        XCTAssertTrue(cancelButton.isEnabled)

        clickElement(cancelButton)

        XCTAssertTrue(waitForSessionTitle("Ready", timeout: 4), app.debugDescription)
        XCTAssertFalse(cancelButton.isEnabled)
    }

    func testFloatingStatusCanBeEnabled() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-floating-status-enabled", "--simulate-success-after-launch"])

        XCTAssertTrue(waitForSessionTitle("Transcribing", timeout: 2))
        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].waitForExistence(timeout: 6))
    }

    func testFloatingWarningShowsExpandedClipboardContext() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-floating-warning"])

        XCTAssertTrue(app.descendants(matching: .any)["floatingStatus.window"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["liveFeedback.hud"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["liveFeedback.title"].exists, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["liveFeedback.detail"].exists, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["liveFeedback.clipboard"].exists, app.debugDescription)
    }

    func testFloatingStatusAutoHidesAfterSuccessWhenEnabled() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-floating-status-enabled", "--simulate-success-after-launch"])

        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.descendants(matching: .any)["liveFeedback.hud"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Ready"].exists)
        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].exists)
    }

    func testFloatingStatusIsDisabledByDefault() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--simulate-success-after-launch"])

        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.windows["GroqTalk Floating Status"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].waitForExistence(timeout: 2))
    }

    func testMovedPreferencesLiveInSettingsPanes() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-paste"])
        openSettingsPanel()
        XCTAssertTrue(checkBox(id: "settings.keepClipboardToggle", fallbackLabel: "Keep final text on clipboard").exists)

        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-general"])
        openSettingsPanel()
        XCTAssertTrue(checkBox(id: "settings.floatingStatusToggle", fallbackLabel: "Show floating status").exists)

        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-experimental"])
        openSettingsPanel()
        XCTAssertTrue(checkBox(id: "settings.asyncPasteToggle", fallbackLabel: "Return to starting app").exists)
        XCTAssertTrue(checkBox(id: "settings.experimentalSkyLightPasteToggle", fallbackLabel: "Try background paste").exists)
        XCTAssertTrue(checkBox(id: "settings.mockToggle", fallbackLabel: "Mock transcription").exists)
    }

    func testCustomHotkeyRecorderIsAccessibleButton() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-recording", "--seed-custom-hotkey"])
        openSettingsPanel()

        let recorder = app.buttons["settings.customHotkeyRecorder"].exists
            ? app.buttons["settings.customHotkeyRecorder"]
            : app.buttons["Record shortcut"]
        XCTAssertTrue(recorder.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(recorder.isEnabled)
        XCTAssertTrue(recorder.label.contains("Custom keyboard shortcut") || recorder.label == "Record shortcut", app.debugDescription)
    }

    func testHelpButtonTargetsCanonicalTroubleshootingURL() throws {
        removeOpenedURLRecord()
        postUITestCommand(openHelpNotification)

        XCTAssertTrue(waitForOpenedURL(timeout: 5), app.debugDescription)
        let openedURL = try String(contentsOf: openedURLPath, encoding: .utf8)
        XCTAssertEqual(openedURL, "https://github.com/mean-weasel/groqtalk#troubleshooting")
    }

    func testOnboardingNotShownForReturningUser() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launch()
        // UI testing mode should skip onboarding
        XCTAssertFalse(app.windows["Welcome to GroqTalk"].exists)
    }

    func testLiveMicrophoneSmoke() throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_MICROPHONE_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_MICROPHONE_TESTS=1 to run live microphone QA.")
        }

        let resultPath = ProcessInfo.processInfo.environment["LIVE_MICROPHONE_RESULT_PATH"]
            ?? "/tmp/groqtalk-live-microphone-result.txt"
        try? FileManager.default.removeItem(atPath: resultPath)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--seed-setup-ready",
            "--live-microphone-smoke"
        ]
        app.launchEnvironment["LIVE_MICROPHONE_RESULT_PATH"] = resultPath
        if let signingIdentity = ProcessInfo.processInfo.environment["LIVE_MICROPHONE_SIGNING_IDENTITY"] {
            app.launchEnvironment["LIVE_MICROPHONE_SIGNING_IDENTITY"] = signingIdentity
        }
        if let duration = ProcessInfo.processInfo.environment["LIVE_MICROPHONE_DURATION_SECONDS"] {
            app.launchEnvironment["LIVE_MICROPHONE_DURATION_SECONDS"] = duration
        }
        app.launch()

        let deadline = Date().addingTimeInterval(20)
        var result = ""
        while Date() < deadline {
            result = (try? String(contentsOfFile: resultPath, encoding: .utf8)) ?? ""
            if result.contains("status=pass") || result.contains("status=fail") {
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        guard !result.isEmpty else {
            XCTFail("Live microphone smoke produced no result file. Check macOS Microphone permission for GroqTalk, selected input device, and any blocking TCC prompt.")
            return
        }

        XCTAssertFalse(result.contains("status=started"), "Live microphone smoke did not finish. Check microphone permission/TCC prompt or selected input device:\n\(result)")
        XCTAssertFalse(result.contains("status=recording"), "Live microphone smoke started but did not stop. Check input-device or recorder state:\n\(result)")
        XCTAssertTrue(result.contains("status=pass"), "Live microphone smoke failed:\n\(result)")
        XCTAssertFalse(result.contains("bytes=0"), "Live microphone smoke captured no audio:\n\(result)")
    }

    // MARK: - E2E Transcription (requires GROQ_API_KEY)

    func testE2ETranscription() throws {
        let env = ProcessInfo.processInfo.environment
        let isOpenAICompatibleE2E = env["E2E_TRANSCRIPTION_PROVIDER"] == "openai-compatible"
        let apiKey: String
        if isOpenAICompatibleE2E {
            apiKey = env["E2E_API_KEY"] ?? "local"
        } else if let envKey = env["GROQ_API_KEY"], !envKey.isEmpty {
            apiKey = envKey
        } else if env["RUN_LIVE_GROQ_TESTS"] != "1" {
            throw XCTSkip("Set RUN_LIVE_GROQ_TESTS=1 and GROQ_API_KEY to run live Groq E2E UI test")
        } else if let groqKey = readGroqKeyViaCLI() {
            apiKey = groqKey
        } else {
            throw XCTSkip("GROQ_API_KEY not in keychain — skipping E2E transcription test")
        }

        let resultPath = "/tmp/groqtalk-e2e-result.txt"
        try? FileManager.default.removeItem(atPath: resultPath)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--e2e-transcribe"
        ]
        app.launchEnvironment["E2E_API_KEY"] = apiKey
        if isOpenAICompatibleE2E {
            app.launchEnvironment["E2E_TRANSCRIPTION_PROVIDER"] = "openai-compatible"
            app.launchEnvironment["E2E_TRANSCRIPTION_BASE_URL"] = env["E2E_TRANSCRIPTION_BASE_URL"] ?? "http://127.0.0.1:8080/v1"
            app.launchEnvironment["E2E_TRANSCRIPTION_MODEL"] = env["E2E_TRANSCRIPTION_MODEL"] ?? "whisper-1"
        } else if let model = env["E2E_TRANSCRIPTION_MODEL"] {
            app.launchEnvironment["E2E_TRANSCRIPTION_MODEL"] = model
        }
        if let wavPath = env["E2E_WAV_PATH"], !wavPath.isEmpty {
            app.launchEnvironment["E2E_WAV_PATH"] = wavPath
        }
        app.launch()

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 10), "App should launch")

        let timeout = TimeInterval(env["E2E_TRANSCRIPTION_TIMEOUT_SECONDS"] ?? "") ?? 30
        let pasted = app.staticTexts["Paste command sent to the current app"]
        XCTAssertTrue(pasted.waitForExistence(timeout: timeout),
                      "E2E transcription should complete and paste within \(Int(timeout)) seconds")

        let transcript = (try? String(contentsOfFile: resultPath, encoding: .utf8)) ?? ""
        XCTAssertFalse(transcript.isEmpty, "E2E result file should contain the transcript")

        let expected = "the quick brown fox jumps over the lazy dog"
        let expectedWords = Set(expected.split(separator: " ").map { String($0) })
        let transcriptWords = Set(transcript.lowercased()
            .filter { $0.isLetter || $0.isWhitespace }
            .split(separator: " ")
            .map { String($0) })
        let missingWords = expectedWords.subtracting(transcriptWords)
        XCTAssertTrue(missingWords.count <= 1,
                      "Transcript '\(transcript)' missing words: \(missingWords.sorted()). Expected: '\(expected)'")
    }

    private func readGroqKeyViaCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", "com.neonwatty.GroqTalk",
            "-a", "groq-api-key",
            "-w"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let key = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return key?.isEmpty == false ? key : nil
        } catch {
            return nil
        }
    }

    private var controlCenter: XCUIElement {
        if uiTestControlCenterHost.exists {
            return uiTestControlCenterHost
        }
        if app.windows["GroqTalk UI Test"].exists {
            return app.windows["GroqTalk UI Test"]
        }
        return app.staticTexts["Ready"]
    }

    private var uiTestControlCenterHost: XCUIElement {
        app.descendants(matching: .any)["uiTest.controlCenter"]
    }

    private func launchForProviderQA(extraArguments: [String] = []) {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--seed-history"
        ] + extraArguments
        app.launchEnvironment["GROQTALK_UITEST_STATE_PATH"] = stateSnapshotURL.path
        app.launchEnvironment["GROQTALK_UITEST_OPENED_URL_PATH"] = openedURLPath.path
        removeUITestStateSnapshot()
        removeOpenedURLRecord()
        app.launch()
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
    }

    private func openSettingsPanel() {
        postUITestCommand(openSettingsNotification)
        if !waitForSettingsPanel(timeout: 6) {
            app.activate()
            postUITestCommand(openSettingsNotification)
        }
        XCTAssertTrue(waitForSettingsPanel(timeout: 8), app.debugDescription)
        let settingsHostExists = elementExists(id: "settings.testHost", timeout: 4)
        let settingsRootExists = elementExists(id: "settings.root", timeout: 4)
        let transcriptionTextExists = app.staticTexts["Transcription"].waitForExistence(timeout: 4)
        XCTAssertTrue(settingsHostExists || settingsRootExists || transcriptionTextExists, app.debugDescription)
    }

    private func openTranscriptionSettingsPanel() {
        openSettingsPanel()
        XCTAssertTrue(providerPickerExists(timeout: 6), app.debugDescription)
    }

    private func openHistoryWindow() {
        postUITestCommand(openHistoryNotification)
    }

    private func postUITestCommand(_ notification: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(
            notification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func removeUITestStateSnapshot() {
        try? FileManager.default.removeItem(at: stateSnapshotURL)
    }

    private func removeOpenedURLRecord() {
        try? FileManager.default.removeItem(at: openedURLPath)
    }

    private func waitForOpenedURL(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if FileManager.default.fileExists(atPath: openedURLPath.path) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return FileManager.default.fileExists(atPath: openedURLPath.path)
    }

    private func readUITestStateSnapshot() -> UITestStateSnapshot? {
        guard let data = try? Data(contentsOf: stateSnapshotURL) else {
            return nil
        }
        return try? JSONDecoder().decode(UITestStateSnapshot.self, from: data)
    }

    private func waitForUITestStateSnapshot(
        timeout: TimeInterval = 5,
        matching predicate: (UITestStateSnapshot) -> Bool
    ) -> UITestStateSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let snapshot = readUITestStateSnapshot(), predicate(snapshot) {
                return snapshot
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return readUITestStateSnapshot()
    }

    private var historyPanel: XCUIElement {
        app.windows["History"].exists ? app.windows["History"] : app
    }

    private func waitForHistoryPanel(timeout: TimeInterval) -> Bool {
        app.windows["History"].waitForExistence(timeout: timeout)
            || elementExists(id: "history.testHost", timeout: timeout)
            || elementExists(id: "history.root", timeout: timeout)
    }

    private func historyEmptyStateAppeared(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if staticTextLabelOrValueContaining("No transcriptions", in: historyPanel).exists
                || staticTextLabelOrValueContaining("No failed transcriptions", in: historyPanel).exists
                || elementExists(id: "history.emptyState", timeout: 0.1) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return false
    }

    private func waitForSettingsPanel(timeout: TimeInterval) -> Bool {
        app.windows["Settings"].waitForExistence(timeout: timeout)
            || elementExists(id: "settings.testHost", timeout: timeout)
            || elementExists(id: "settings.root", timeout: timeout)
    }

    private func button(id: String, fallbackLabel: String) -> XCUIElement {
        if id.hasPrefix("menu."), uiTestControlCenterHost.exists {
            let identified = uiTestControlCenterHost.descendants(matching: .button)[id]
            if identified.exists {
                return identified
            }
            let genericIdentified = uiTestControlCenterHost.descendants(matching: .any)[id]
            if genericIdentified.exists {
                return genericIdentified
            }
            return uiTestControlCenterHost.descendants(matching: .button)[fallbackLabel]
        }

        let identified = app.buttons[id]
        return identified.exists ? identified : app.buttons[fallbackLabel]
    }

    private func checkBox(id: String, fallbackLabel: String) -> XCUIElement {
        let genericIdentified = app.descendants(matching: .any)[id]
        if genericIdentified.exists {
            return genericIdentified
        }
        let identified = app.checkBoxes[id]
        if identified.exists {
            return identified
        }
        let genericFallback = app.descendants(matching: .any)[fallbackLabel]
        return genericFallback.exists ? genericFallback : app.checkBoxes[fallbackLabel]
    }

    private func assertButtonExists(id: String, fallbackLabel: String) {
        XCTAssertTrue(button(id: id, fallbackLabel: fallbackLabel).waitForExistence(timeout: 4), app.debugDescription)
    }

    private func clickButton(id: String, fallbackLabel: String) {
        let target = button(id: id, fallbackLabel: fallbackLabel)
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        clickElement(target)
    }

    private func clickElement(_ element: XCUIElement) {
        if element.isHittable {
            element.click()
            return
        }

        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if element.isHittable {
            element.click()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
    }

    private func waitForSessionTitle(_ title: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let identifiedTitle = app.staticTexts["menu.status.title"]
        repeat {
            if identifiedTitle.exists && identifiedTitle.label == title {
                return true
            }
            if app.staticTexts[title].exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return false
    }

    private func staticTextContaining(_ text: String, in root: XCUIElement? = nil) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return (root ?? app).staticTexts.matching(predicate).firstMatch
    }

    private func staticTextLabelOrValueContaining(_ text: String, in root: XCUIElement? = nil) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        return (root ?? app).staticTexts.matching(predicate).firstMatch
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        clickElement(element)
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        element.typeText(text)
    }

    private func elementExists(id: String, timeout: TimeInterval = 2) -> Bool {
        app.descendants(matching: .any)[id].waitForExistence(timeout: timeout)
    }

    private func providerPickerExists(timeout: TimeInterval) -> Bool {
        let settingsPicker = app.descendants(matching: .any)["settings.transcriptionProviderPicker"]
        if settingsPicker.waitForExistence(timeout: timeout) {
            return true
        }
        let menuPicker = app.descendants(matching: .any)["menu.settings.transcriptionProviderPicker"]
        return menuPicker.waitForExistence(timeout: timeout)
    }

    private func assertProviderPickerExists() {
        XCTAssertTrue(providerPickerExists(timeout: 6), app.debugDescription)
    }

    private var providerPicker: XCUIElement {
        app.popUpButtons["settings.transcriptionProviderPicker"].exists
            ? app.popUpButtons["settings.transcriptionProviderPicker"]
            : app.popUpButtons["menu.settings.transcriptionProviderPicker"]
    }

    private func selectProviderPreset(_ name: String) {
        let picker = providerPicker
        XCTAssertTrue(picker.waitForExistence(timeout: 4), app.debugDescription)
        clickElement(picker)

        let menuItem = app.menuItems[name].firstMatch
        if menuItem.waitForExistence(timeout: 2) {
            clickElement(menuItem)
            return
        }

        let matchingElement = app.descendants(matching: .any)[name].firstMatch
        XCTAssertTrue(matchingElement.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(matchingElement)
    }

    private var customBaseURLField: XCUIElement {
        app.textFields["settings.customTranscriptionBaseURL"].exists
            ? app.textFields["settings.customTranscriptionBaseURL"]
            : app.textFields["menu.settings.customTranscriptionBaseURL"]
    }

    private var customModelField: XCUIElement {
        app.textFields["settings.customTranscriptionModel"].exists
            ? app.textFields["settings.customTranscriptionModel"]
            : app.textFields["menu.settings.customTranscriptionModel"]
    }

    private func providerConnectionButton() -> XCUIElement {
        if app.buttons["settings.testProviderConnectionButton"].exists {
            return app.buttons["settings.testProviderConnectionButton"]
        }
        if app.buttons["menu.settings.testProviderConnectionButton"].exists {
            return app.buttons["menu.settings.testProviderConnectionButton"]
        }
        return app.buttons["Test connection"]
    }

    private func clickAlertButton(_ title: String) {
        let sheetsButton = app.sheets.firstMatch.buttons[title]
        if sheetsButton.waitForExistence(timeout: 1) {
            sheetsButton.click()
            return
        }

        let dialogsButton = app.dialogs.firstMatch.buttons[title]
        if dialogsButton.waitForExistence(timeout: 1) {
            dialogsButton.click()
            return
        }

        let button = app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 2), app.debugDescription)
        button.click()
    }

    private func relaunchWithSeededHistory() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history"
        ])
    }

    private func relaunchWithArguments(_ arguments: [String]) {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["GROQTALK_UITEST_STATE_PATH"] = stateSnapshotURL.path
        app.launchEnvironment["GROQTALK_UITEST_OPENED_URL_PATH"] = openedURLPath.path
        removeUITestStateSnapshot()
        removeOpenedURLRecord()
        app.launch()
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
    }
}

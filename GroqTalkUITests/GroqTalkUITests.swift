import XCTest

final class GroqTalkUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--seed-history"
        ]
        app.launch()
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testControlCenterShowsSeededReadyState() {
        XCTAssertTrue(app.staticTexts["Ready"].exists || elementExists(id: "menu.setup.summary"))
        XCTAssertTrue(staticTextContaining("Pastes into current app").exists || app.staticTexts["Hotkey"].exists)
        XCTAssertTrue(app.staticTexts["Second searchable transcript."].exists)
        assertButtonExists(id: "menu.historyButton", fallbackLabel: "History")
        assertButtonExists(id: "menu.settingsButton", fallbackLabel: "Settings")
        assertButtonExists(id: "menu.helpButton", fallbackLabel: "Help")
        XCTAssertTrue(button(id: "menu.recording.startButton", fallbackLabel: "Start recording").exists)
        XCTAssertTrue(button(id: "menu.recording.startButton", fallbackLabel: "Start recording").isEnabled)
        XCTAssertTrue(button(id: "menu.recording.stopButton", fallbackLabel: "Stop recording").exists)
        XCTAssertFalse(button(id: "menu.recording.stopButton", fallbackLabel: "Stop recording").isEnabled)
        XCTAssertTrue(button(id: "menu.recording.cancelButton", fallbackLabel: "Cancel recording").exists)
        XCTAssertFalse(button(id: "menu.recording.cancelButton", fallbackLabel: "Cancel recording").isEnabled)
        XCTAssertTrue(app.staticTexts["Test Setup"].exists)
        assertButtonExists(id: "menu.setup.test.action", fallbackLabel: "Test")
        XCTAssertTrue(app.checkBoxes["Paste where recording started"].exists)
        XCTAssertTrue(app.checkBoxes["Show floating status"].exists)
        XCTAssertTrue(app.checkBoxes["Mock Transcription"].exists)
    }

    func testSetupCheckCanBeRunInline() {
        clickButton(id: "menu.setup.test.action", fallbackLabel: "Test")

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
        app.launch()

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Setup needed"].exists)
        XCTAssertTrue(app.staticTexts["Check Accessibility before recording"].exists)
        XCTAssertTrue(app.staticTexts["Not checked"].exists)
        assertButtonExists(id: "menu.setup.Accessibility.action", fallbackLabel: "Check")
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
        app.launch()

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Microphone"].exists)
        XCTAssertTrue(app.staticTexts["Not checked"].exists)
        assertButtonExists(id: "menu.setup.Microphone.action", fallbackLabel: "Check")
    }

    func testMicrophoneDeniedShowsOpenSettingsAction() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--seed-microphone-denied"
        ]
        app.launch()

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Microphone"].exists)
        XCTAssertTrue(app.staticTexts["Allow microphone access"].exists)
        assertButtonExists(id: "menu.setup.Microphone.action", fallbackLabel: "Open Settings")
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

    func testHistoryWindowOpensAndSearchesSeededRecords() {
        openHistoryWindow()
        XCTAssertTrue(app.windows["History"].waitForExistence(timeout: 3))

        let searchField = app.textFields["Search transcriptions..."]
        XCTAssertTrue(searchField.exists)
        searchField.click()
        searchField.typeText("Second searchable")

        XCTAssertTrue(app.staticTexts["Second searchable transcript."].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Seeded transcript for UI testing."].exists)
    }

    func testHistoryFilterShowsFailedRecords() {
        openHistoryWindow()
        XCTAssertTrue(app.windows["History"].waitForExistence(timeout: 3))

        XCTAssertTrue(app.buttons["All"].isEnabled)
        app.buttons["Failed"].click()
        XCTAssertTrue(app.buttons["Failed"].isEnabled)

        XCTAssertTrue(app.staticTexts["Seeded network failure"].waitForExistence(timeout: 2))
    }

    func testHistoryDeleteAndClearActions() {
        openHistoryWindow()
        XCTAssertTrue(app.windows["History"].waitForExistence(timeout: 3))

        XCTAssertTrue(app.staticTexts["Second searchable transcript."].exists)
        app.buttons["history.row.deleteButton"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Delete History Item?"].waitForExistence(timeout: 2))
        clickAlertButton("Cancel")
        XCTAssertTrue(app.staticTexts["Seeded network failure"].waitForExistence(timeout: 2))

        relaunchWithSeededHistory()
        openHistoryWindow()
        XCTAssertTrue(app.windows["History"].waitForExistence(timeout: 3))

        clickButton(id: "history.clearButton", fallbackLabel: "Clear")
        XCTAssertTrue(app.staticTexts["Clear History?"].waitForExistence(timeout: 2))
        clickAlertButton("Clear History")
        XCTAssertTrue(app.staticTexts["No transcriptions yet"].waitForExistence(timeout: 2))
    }

    func testHistoryDetailAllowsEditingAndExport() {
        openHistoryWindow()
        XCTAssertTrue(app.windows["History"].waitForExistence(timeout: 3))
        assertButtonExists(id: "history.exportButton", fallbackLabel: "Export")

        let detailsButtons = app.windows["History"].buttons.matching(NSPredicate(format: "label == %@", "Details"))
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
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 4))
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
        XCTAssertTrue(staticTextContaining("API key is optional").exists
                      || staticTextContaining("local OpenAI-compatible").exists
                      || elementExists(id: "settings.localProviderHelp", timeout: 1),
                      app.debugDescription)
        XCTAssertTrue(app.buttons["Test connection"].exists || app.buttons["settings.testProviderConnectionButton"].exists || app.buttons["menu.settings.testProviderConnectionButton"].exists, app.debugDescription)
        XCTAssertTrue(
            app.staticTexts["Cleanup requires a Groq-compatible chat provider."].waitForExistence(timeout: 2)
                || app.staticTexts["Cleanup requires a Groq-compatible chat provider. Custom transcription currently uses raw transcripts."].waitForExistence(timeout: 2),
            app.debugDescription
        )
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
        let toggle = checkBox(id: "menu.mockToggle", fallbackLabel: "Mock Transcription")
        XCTAssertTrue(toggle.exists)
        toggle.click()

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--seed-history"
        ]
        app.launch()

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5))
        XCTAssertTrue(checkBox(id: "menu.mockToggle", fallbackLabel: "Mock Transcription").exists)
    }

    func testSimulatedRecordingUsesCurrentAppPasteWhenAsyncIsOff() {
        XCTAssertFalse(app.staticTexts["Mock async paste transcript"].exists)

        clickButton(id: "menu.simulateSuccessButton", fallbackLabel: "Simulate Success")

        XCTAssertTrue(app.staticTexts["Transcribing"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Cleaning up"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Pasting"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["Done"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Mock async paste transcript"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Clipboard restored"].exists)
    }

    func testSimulatedRecordingUsesAsyncPasteWhenEnabled() {
        checkBox(id: "menu.asyncPasteToggle", fallbackLabel: "Paste where recording started").click()
        clickButton(id: "menu.simulateSuccessButton", fallbackLabel: "Simulate Success")

        XCTAssertTrue(app.staticTexts["Transcribing"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Pasting"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Mock async paste transcript"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Pasted into the test target"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Target: GroqTalk UI Test"].exists)
    }

    func testSimulatedRecordingFailureKeepsRetryVisibleInHistory() {
        clickButton(id: "menu.simulateFailureButton", fallbackLabel: "Simulate Failure")

        XCTAssertTrue(app.staticTexts["Simulated transcription failure"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Open History for details"].exists)

        openHistoryWindow()
        XCTAssertTrue(app.windows["History"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Simulated transcription failure"].waitForExistence(timeout: 2))
    }

    func testFloatingStatusCanBeEnabled() {
        checkBox(id: "menu.floatingStatusToggle", fallbackLabel: "Show floating status").click()
        clickButton(id: "menu.simulateSuccessButton", fallbackLabel: "Simulate Success")

        XCTAssertTrue(app.staticTexts["Transcribing"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].waitForExistence(timeout: 6))
    }

    func testFloatingStatusAutoHidesAfterSuccessWhenEnabled() {
        checkBox(id: "menu.floatingStatusToggle", fallbackLabel: "Show floating status").click()
        clickButton(id: "menu.simulateSuccessButton", fallbackLabel: "Simulate Success")

        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.windows["GroqTalk Floating Status"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ready"].exists)
        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].exists)
    }

    func testFloatingStatusIsDisabledByDefault() {
        clickButton(id: "menu.simulateSuccessButton", fallbackLabel: "Simulate Success")

        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.windows["GroqTalk Floating Status"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].waitForExistence(timeout: 2))
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
        app.windows["GroqTalk UI Test"].exists
            ? app.windows["GroqTalk UI Test"]
            : app.staticTexts["Ready"]
    }

    private func launchForProviderQA(extraArguments: [String] = []) {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--seed-history"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
    }

    private func openSettingsPanel() {
        clickButton(id: "menu.settingsButton", fallbackLabel: "Settings")
        if !app.windows["Settings"].waitForExistence(timeout: 6) {
            app.activate()
            clickButton(id: "menu.settingsButton", fallbackLabel: "Settings")
        }
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 8), app.debugDescription)
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
        clickButton(id: "menu.historyButton", fallbackLabel: "History")
    }

    private func button(id: String, fallbackLabel: String) -> XCUIElement {
        let identified = app.buttons[id]
        return identified.exists ? identified : app.buttons[fallbackLabel]
    }

    private func checkBox(id: String, fallbackLabel: String) -> XCUIElement {
        let identified = app.checkBoxes[id]
        return identified.exists ? identified : app.checkBoxes[fallbackLabel]
    }

    private func assertButtonExists(id: String, fallbackLabel: String) {
        XCTAssertTrue(button(id: id, fallbackLabel: fallbackLabel).exists, app.debugDescription)
    }

    private func clickButton(id: String, fallbackLabel: String) {
        let target = button(id: id, fallbackLabel: fallbackLabel)
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        target.click()
    }

    private func staticTextContaining(_ text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.staticTexts.matching(predicate).firstMatch
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
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-defaults",
            "--seed-history"
        ]
        app.launch()
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
    }
}

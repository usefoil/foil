import XCTest

final class ManagedLocalSetupUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testUnansweredLanguageDoesNotRecommendOrDownload() {
        launch(languageArgument: "--seed-managed-language-unanswered")
        openConfigurationStep()

        XCTAssertTrue(app.staticTexts["managedLocal.languagePrompt"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(app.buttons["managedLocal.installRecommended"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Terminal")).firstMatch.exists)
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
    }

    func testEnglishLanguageShowsPinnedBaseEnglishSizesWithoutStartingDownload() {
        launch(languageArgument: "--seed-managed-language-english")
        openConfigurationStep()

        XCTAssertTrue(app.staticTexts["managedLocal.recommendation"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(text(app.staticTexts["managedLocal.recommendation"]).contains("Base English"))
        let sizes = app.staticTexts["managedLocal.modelSizes"]
        XCTAssertTrue(sizes.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(text(sizes).contains("148 MB"), text(sizes))
        XCTAssertTrue(text(sizes).contains("67 MB temporary"), text(sizes))
        XCTAssertTrue(text(sizes).contains("215 MB total"), text(sizes))
        XCTAssertTrue(app.buttons["managedLocal.installRecommended"].isEnabled)
        XCTAssertFalse(app.progressIndicators["managedLocal.downloadProgress"].exists)
        attachScreenshot(name: "managed-local-onboarding-light-english")
    }

    func testMultilingualIntentRecommendsBaseMultilingual() {
        launch(languageArgument: "--seed-managed-language-multilingual")
        openConfigurationStep()

        let recommendation = app.staticTexts["managedLocal.recommendation"]
        XCTAssertTrue(recommendation.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(text(recommendation).contains("Base Multilingual"), text(recommendation))
        XCTAssertTrue(text(app.staticTexts["managedLocal.serviceAddress"]).contains("transcribe.foil.localhost"))
        XCTAssertFalse(text(app.staticTexts["managedLocal.serviceAddress"]).localizedCaseInsensitiveContains("token"))
        attachScreenshot(name: "managed-local-onboarding-dark-multilingual")
    }

    func testSettingsUsesTheSameManagedIntentAndAccessibleControls() {
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--reset-defaults", "--seed-setup-ready",
            "--seed-managed-local", "--seed-managed-language-english", "--show-app-shell"
        ]
        app.launch()
        let transcriptionTab = app.descendants(matching: .any)["appShell.nav.settings.transcription"]
        XCTAssertTrue(transcriptionTab.waitForExistence(timeout: 6), app.debugDescription)
        transcriptionTab.click()

        XCTAssertTrue(app.popUpButtons["settings.transcriptionProviderPicker"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.popUpButtons["managedLocal.languagePicker"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["managedLocal.installRecommended"].isEnabled)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] %@", "CMake")).firstMatch.exists)
        attachScreenshot(name: "managed-local-settings-english")
    }

    func testSettingsModelChoiceUpdatesInstallActionWithoutDownloading() {
        launchSettings()
        chooseModel("Tiny English")
        XCTAssertTrue(text(app.buttons["managedLocal.installRecommended"]).contains("Install and use Tiny English"))
        XCTAssertTrue(text(app.staticTexts["managedLocal.modelSizes"]).contains("78 MB"))
        XCTAssertFalse(app.progressIndicators["managedLocal.downloadProgress"].exists)
        chooseModel("Large V3")
        XCTAssertTrue(text(app.buttons["managedLocal.installRecommended"]).contains("Install and use Large V3"))
        XCTAssertTrue(text(app.staticTexts["managedLocal.modelSizes"]).contains("3095 MB"))
        XCTAssertTrue(text(app.staticTexts["managedLocal.modelGuidance"]).contains("highest memory"))
        XCTAssertFalse(app.progressIndicators["managedLocal.downloadProgress"].exists)
        attachScreenshot(name: "managed-local-settings-model-sizes")
    }

    func testMultilingualSettingsOnlyOffersMultilingualModels() {
        launchSettings(language: "--seed-managed-language-multilingual")
        let picker = app.popUpButtons["managedLocal.modelPicker"]
        picker.click()
        XCTAssertFalse(app.menuItems["Tiny English"].exists)
        XCTAssertFalse(app.menuItems["Medium English"].exists)
        XCTAssertTrue(app.menuItems["Tiny Multilingual"].exists)
        app.menuItems["Tiny Multilingual"].click()
        XCTAssertTrue(text(app.buttons["managedLocal.installRecommended"]).contains("Tiny Multilingual"))
        XCTAssertFalse(app.progressIndicators["managedLocal.downloadProgress"].exists)
    }

    func testLiveSettingsInstallSwitchAndRestore() throws {
        guard ProcessInfo.processInfo.environment["FOIL_RUN_MODEL_SWITCH_ACCEPTANCE"] == "1" else {
            throw XCTSkip("Opt in with TEST_RUNNER_FOIL_RUN_MODEL_SWITCH_ACCEPTANCE=1; downloads Tiny English and Base English")
        }
        let sessionID = "model-switch-\(UUID().uuidString)"
        launchSettings(sessionID: sessionID)
        chooseModel("Tiny English")
        app.buttons["managedLocal.installRecommended"].click()
        XCTAssertTrue(waitForText("Active: Tiny English", in: app.staticTexts["managedLocal.statusDetail"], timeout: 180), app.debugDescription)
        XCTAssertFalse(app.buttons["managedLocal.installRecommended"].isEnabled)
        attachScreenshot(name: "live-tiny-installed-ready")

        chooseModel("Base English")
        app.buttons["managedLocal.installRecommended"].click()
        XCTAssertTrue(waitForText("Active: Base English", in: app.staticTexts["managedLocal.statusDetail"], timeout: 180), app.debugDescription)
        attachScreenshot(name: "live-base-switched-ready")

        chooseModel("Tiny English")
        XCTAssertTrue(text(app.buttons["managedLocal.installRecommended"]).contains("Use Tiny English"))
        app.buttons["managedLocal.installRecommended"].click()
        XCTAssertTrue(waitForText("Selected: Tiny English · Active: Tiny English", in: app.staticTexts["managedLocal.statusDetail"], timeout: 40), app.debugDescription)
        app.terminate()
        launchSettings(sessionID: sessionID, reset: false)
        // UI testing suppresses automatic startup restoration. Reenter managed
        // mode to reconstruct the saved inventory, then exercise explicit Restore.
        let mode = app.popUpButtons["settings.transcriptionProviderPicker"]
        mode.click()
        app.menuItems["Groq"].click()
        mode.click()
        app.menuItems["On this Mac — managed"].click()
        let restore = app.buttons["managedLocal.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5), app.debugDescription)
        restore.click()
        XCTAssertTrue(waitForText("Selected: Tiny English · Active: Tiny English", in: app.staticTexts["managedLocal.statusDetail"], timeout: 40), app.debugDescription)
        XCTAssertTrue(text(app.popUpButtons["managedLocal.modelPicker"]).contains("Tiny English"))
        attachScreenshot(name: "live-tiny-restored-after-relaunch")
    }

    private func launchSettings(language: String = "--seed-managed-language-english",
                                sessionID: String = UUID().uuidString, reset: Bool = true) {
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-setup-ready", "--seed-managed-local",
                               language, "--show-app-shell"]
        if reset { app.launchArguments.append("--reset-defaults") }
        app.launchEnvironment["FOIL_UITEST_SESSION_ID"] = sessionID
        app.launch()
        let tab = app.descendants(matching: .any)["appShell.nav.settings.transcription"]
        XCTAssertTrue(tab.waitForExistence(timeout: 6), app.debugDescription)
        tab.click()
        XCTAssertTrue(app.popUpButtons["managedLocal.modelPicker"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func chooseModel(_ name: String) {
        let picker = app.popUpButtons["managedLocal.modelPicker"]
        XCTAssertTrue(picker.isEnabled)
        picker.click()
        app.menuItems[name].click()
    }

    func testDownloadingFixtureCancelsThroughProductionBindingAndExposesRetry() {
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--reset-defaults", "--seed-setup-ready",
            "--seed-managed-local", "--seed-managed-language-english",
            "--seed-managed-downloading", "--show-app-shell"
        ]
        app.launch()
        let transcriptionTab = app.descendants(matching: .any)["appShell.nav.settings.transcription"]
        XCTAssertTrue(transcriptionTab.waitForExistence(timeout: 6), app.debugDescription)
        transcriptionTab.click()

        let progress = app.progressIndicators["managedLocal.downloadProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 3), app.debugDescription)
        let detail = app.staticTexts["managedLocal.statusDetail"]
        XCTAssertTrue(waitForText("74 MB of 148 MB", in: detail, timeout: 2), text(detail))
        let cancel = app.buttons["managedLocal.cancel"]
        XCTAssertTrue(cancel.isEnabled)
        cancel.click()

        let statusTitle = app.staticTexts["managedLocal.statusTitle"]
        XCTAssertTrue(waitForText("cancelled", in: statusTitle, timeout: 2), text(statusTitle))
        XCTAssertTrue(app.buttons["managedLocal.retry"].isEnabled)
        XCTAssertFalse(progress.exists)
    }

    private func launch(languageArgument: String) {
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--reset-defaults", "--show-onboarding",
            "--seed-setup-ready", "--seed-managed-local", languageArgument
        ]
        if languageArgument == "--seed-managed-language-multilingual" {
            app.launchEnvironment["AppleInterfaceStyle"] = "Dark"
        }
        app.launch()
        XCTAssertTrue(app.windows["Welcome to Foil"].waitForExistence(timeout: 6), app.debugDescription)
    }

    private func openConfigurationStep() {
        let identified = app.buttons["onboarding.nextButton"]
        let next = identified.exists ? identified : app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(next.isEnabled)
        next.click()
        XCTAssertTrue(app.popUpButtons["managedLocal.languagePicker"].waitForExistence(timeout: 3)
            || app.popUpButtons.matching(NSPredicate(format: "value CONTAINS[c] %@", "English")).firstMatch.exists,
            app.debugDescription)
    }

    private func text(_ element: XCUIElement) -> String {
        let value = element.value as? String ?? ""
        return element.label + " " + value
    }

    private func waitForText(_ expected: String, in element: XCUIElement,
                             timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { [weak self] object, _ in
            guard let self, let element = object as? XCUIElement else { return false }
            return self.text(element).localizedCaseInsensitiveContains(expected)
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }

    private func attachScreenshot(name: String) {
        let onboarding = app.windows["Welcome to Foil"]
        let window = onboarding.exists ? onboarding : app.windows["Foil"]
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

import AppKit
import CoreGraphics
import XCTest

final class FoilUITests: XCTestCase {
    private var app: XCUIApplication!
    private let openHistoryNotification = Notification.Name("com.neonwatty.Foil.uiTests.openHistory")
    private let openHelpNotification = Notification.Name("com.neonwatty.Foil.uiTests.openHelp")
    private let runSetupCheckNotification = Notification.Name("com.neonwatty.Foil.uiTests.runSetupCheck")
    private let historyCommandNotification = Notification.Name("com.neonwatty.Foil.uiTests.historyCommand")
    private let onboardingCommandNotification = Notification.Name("com.neonwatty.Foil.uiTests.onboardingCommand")
    private let appCommandNotification = Notification.Name("com.neonwatty.Foil.uiTests.appCommand")
    private let microphonePromptTimedOutMessage = "Open Microphone privacy and allow Foil"
    private let stateSnapshotURL =
        URL(fileURLWithPath: "/tmp").appendingPathComponent("foil-ui-tests-state-\(ProcessInfo.processInfo.processIdentifier).json")
    private let commandInboxURL =
        FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-ui-tests-command-\(ProcessInfo.processInfo.processIdentifier).json")
    private let openedURLPath =
        URL(fileURLWithPath: "/tmp").appendingPathComponent("foil-ui-tests-opened-url-\(ProcessInfo.processInfo.processIdentifier).txt")

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

    override func setUpWithError() throws {
        continueAfterFailure = false
        installSystemInterruptionMonitor()
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--seed-history"
        ])
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

    func testAppShellOpensHomeWithSidebar() {
        let openFoilButton = button(id: "menu.openFoilButton", fallbackLabel: "Open Foil")
        XCTAssertTrue(openFoilButton.waitForExistence(timeout: 2), app.debugDescription)
        openFoilButton.click()

        XCTAssertTrue(elementExists(id: "appShell.root", timeout: 4), app.debugDescription)
        XCTAssertTrue(elementExists(id: "appShell.sidebar", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "appShell.home", timeout: 2), app.debugDescription)

        let homeNavItem = app.descendants(matching: .any)["appShell.nav.home"]
        XCTAssertTrue(homeNavItem.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(homeNavItem.value as? String, "Selected")
        XCTAssertTrue(elementExists(id: "appShell.nav.history", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "appShell.nav.insights", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "appShell.nav.settings.general", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "appShell.nav.settings.recording", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "appShell.nav.settings.transcription", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "appShell.nav.settings.cleanup", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "appShell.nav.settings.paste", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "appShell.nav.settings.storage", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "appShell.nav.settings.experimental", timeout: 2), app.debugDescription)

        XCTAssertTrue(elementExists(id: "appShell.home.setupHealth", timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Ready"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Accessibility Ready"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Microphone Ready"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["API Key Ready"].exists, app.debugDescription)

        XCTAssertTrue(elementExists(id: "appShell.home.recentTranscripts", timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Second searchable transcript."].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Seeded transcript for UI testing."].exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Seeded network failure"].exists, app.debugDescription)
    }

    func testUsageInsightsShowsPopulatedMetricsFromUsageEventStore() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-usage-events"
        ])
        openAppShellInsights()

        XCTAssertTrue(elementExists(id: "appShell.insights", timeout: 4), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Total words").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("240").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Sessions").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("3").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("6 min").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Daily Trend").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Top Apps").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Terminal").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Mail").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(staticTextLabelOrValueContaining("recommend", in: app).exists, app.debugDescription)
        add(XCTAttachment(screenshot: app.screenshot()))
    }

    func testUsageInsightsShowsEmptyDisabledAndDeleteStates() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-usage-empty"
        ])
        openAppShellInsights()

        XCTAssertTrue(elementExists(id: "usageInsights.emptyState", timeout: 4), app.debugDescription)
        XCTAssertTrue(app.staticTexts["No usage metrics yet"].exists, app.debugDescription)

        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-usage-disabled"
        ])
        openAppShellInsights()

        XCTAssertTrue(elementExists(id: "usageInsights.disabledState", timeout: 4), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("240").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Future usage metrics are paused").waitForExistence(timeout: 2), app.debugDescription)
        add(XCTAttachment(screenshot: app.screenshot()))

        clickElement(app.buttons["usageInsights.deleteButton"])
        XCTAssertTrue(elementExists(id: "usageInsights.emptyState", timeout: 4), app.debugDescription)
        XCTAssertTrue(app.staticTexts["No usage metrics yet"].exists, app.debugDescription)
        XCTAssertTrue(elementExists(id: "usageInsights.disabledState", timeout: 2), app.debugDescription)

        let storageNavItem = app.descendants(matching: .any)["appShell.nav.settings.storage"]
        XCTAssertTrue(storageNavItem.waitForExistence(timeout: 4), app.debugDescription)
        clickElement(storageNavItem)
        XCTAssertTrue(elementExists(id: "settings.usageMetricsToggle", timeout: 4), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.deleteUsageMetricsButton", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.historyRetentionPicker", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.clearHistoryButton", timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Retained usage sessions"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Stored records"].exists, app.debugDescription)
        add(XCTAttachment(screenshot: app.screenshot()))
    }

    func testUsageMetricsSettingsDeleteRefreshesRetainedCount() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-usage-events",
            "--settings-tab-privacy"
        ])
        openSettingsPanel()

        let retainedSessions = app.descendants(matching: .any)["settings.usageMetricsRetainedSessions"]
        XCTAssertTrue(retainedSessions.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(elementLabelOrValueContains(retainedSessions, "3"), app.debugDescription)

        clickElement(app.buttons["settings.deleteUsageMetricsButton"])

        XCTAssertTrue(
            waitForElementLabelOrValue(retainedSessions, containing: "0", timeout: 4),
            app.debugDescription
        )
        XCTAssertFalse(app.buttons["settings.deleteUsageMetricsButton"].isEnabled, app.debugDescription)
    }

    func testCleanupGroupAppPickerShowsRecentlyUsedAppsFromUsageEvents() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-usage-events",
            "--settings-tab-cleanup"
        ])
        openSettingsPanel()

        clickElement(button(id: "settings.cleanupGroups.addGroupButton", fallbackLabel: "Add cleanup group"))

        XCTAssertTrue(staticTextLabelOrValueContaining("Recently used apps").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Mail").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("com.apple.mail").waitForExistence(timeout: 2), app.debugDescription)

        let mailAddButton = app.buttons["settings.cleanupGroups.recentAppAddButton.bundle:com.apple.mail"]
        XCTAssertTrue(mailAddButton.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(mailAddButton.isEnabled, app.debugDescription)
        clickElement(mailAddButton)
        XCTAssertFalse(mailAddButton.isEnabled, app.debugDescription)

        relaunchWithArguments([
            "--ui-testing",
            "--seed-usage-events",
            "--settings-tab-cleanup"
        ])
        openSettingsPanel()

        let persistedGroupPredicate = NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@",
            "New group",
            "1 apps"
        )
        let persistedGroupRow = app.buttons.matching(persistedGroupPredicate).firstMatch
        XCTAssertTrue(persistedGroupRow.waitForExistence(timeout: 4), app.debugDescription)
    }

    func testAppShellOpensHistoryWithSeededRecords() {
        let openFoilButton = button(id: "menu.openFoilButton", fallbackLabel: "Open Foil")
        XCTAssertTrue(openFoilButton.waitForExistence(timeout: 2), app.debugDescription)
        openFoilButton.click()

        let historyNavItem = app.descendants(matching: .any)["appShell.nav.history"]
        XCTAssertTrue(historyNavItem.waitForExistence(timeout: 4), app.debugDescription)
        historyNavItem.click()

        XCTAssertTrue(elementExists(id: "appShell.history", timeout: 4), app.debugDescription)
        XCTAssertTrue(elementExists(id: "history.root", timeout: 2), app.debugDescription)
        XCTAssertEqual(historyNavItem.value as? String, "Selected")
        XCTAssertTrue(app.textFields["Search transcriptions..."].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.buttons["Clear"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Second searchable transcript."].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Seeded transcript for UI testing."].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Seeded network failure"].exists, app.debugDescription)
        XCTAssertGreaterThanOrEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Details")).count, 3, app.debugDescription)
    }

    func testAppShellHistorySearchesAndFiltersSeededRecords() {
        openAppShellHistory()

        postUITestCommand(historyCommandNotification, userInfo: ["command": "search", "query": "Second searchable"])
        XCTAssertTrue(app.staticTexts["Second searchable transcript."].waitForExistence(timeout: 2), app.debugDescription)

        postUITestCommand(historyCommandNotification, userInfo: ["command": "search", "query": "no matching transcript"])
        XCTAssertTrue(staticTextLabelOrValueContaining("No matches", in: app).waitForExistence(timeout: 4), app.debugDescription)

        postUITestCommand(historyCommandNotification, userInfo: ["command": "search", "query": ""])
        postUITestCommand(historyCommandNotification, userInfo: ["command": "filter", "filter": "Failed"])
        XCTAssertTrue(app.staticTexts["Seeded network failure"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.windows["History"].exists, app.debugDescription)
    }

    func testAppShellHistorySavesSelectedTextAsPreferredTerm() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--settings-tab-cleanup",
            "--seed-cleanup-formatting-enabled"
        ])
        openAppShellHistory()

        selectAppShellHistoryVocabularyToken("Second")
        selectAppShellHistoryVocabularyToken("searchable")
        clickElement(app.buttons["history.vocabulary.addSelectionButton"])

        let preferredTermModeButton = app.buttons["history.vocabulary.mode.preferredTerm"]
        XCTAssertTrue(preferredTermModeButton.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(preferredTermModeButton)

        let termField = app.textFields["history.vocabulary.termField"]
        XCTAssertTrue(termField.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(termField.value as? String, "Second searchable")
        clickElement(app.buttons["history.vocabulary.saveButton"])

        let cleanupNavItem = app.descendants(matching: .any)["appShell.nav.settings.cleanup"]
        XCTAssertTrue(cleanupNavItem.waitForExistence(timeout: 4), app.debugDescription)
        clickElement(cleanupNavItem)

        XCTAssertTrue(elementExists(id: "appShell.preferences", timeout: 4), app.debugDescription)
        let preferredTermsEditor = app.textViews["settings.preferredTermsEditor"]
        XCTAssertTrue(preferredTermsEditor.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertEqual(preferredTermsEditor.value as? String, "Second searchable")
        XCTAssertFalse(app.windows["History"].exists, app.debugDescription)
    }

    func testAppShellHistorySaveAndRecleanVocabularySelection() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--seed-history-reclean-enabled"
        ])
        openAppShellHistory()

        selectAppShellHistoryVocabularyToken("Second")
        clickElement(app.buttons["history.vocabulary.addSelectionButton"])

        let correctVersionField = app.textFields["history.vocabulary.correctVersionField"]
        XCTAssertTrue(correctVersionField.waitForExistence(timeout: 2), app.debugDescription)
        correctVersionField.click()
        correctVersionField.typeText("Supabase")

        let saveAndRecleanButton = app.buttons["history.vocabulary.saveAndRecleanButton"]
        XCTAssertTrue(saveAndRecleanButton.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(saveAndRecleanButton)

        XCTAssertTrue(app.descendants(matching: .any)["Select Re-cleaned for Vocabulary"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["Select Supabase for Vocabulary"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["Select Second for Vocabulary"].exists, app.debugDescription)
        XCTAssertFalse(app.windows["History"].exists, app.debugDescription)
    }

    func testAppShellHistoryTransformsTranscriptAsSeparateRecord() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--seed-history-transform-enabled"
        ])
        openAppShellHistory()

        XCTAssertTrue(app.descendants(matching: .any)["Transform"].waitForExistence(timeout: 2), app.debugDescription)
        postUITestCommand(historyCommandNotification, userInfo: ["command": "filter", "filter": "Successful"])
        postUITestCommand(historyCommandNotification, userInfo: [
            "command": "transform",
            "index": 0,
            "transformKind": "polish"
        ])

        XCTAssertTrue(app.descendants(matching: .any)["Select Polish for Vocabulary"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["Select Second for Vocabulary"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.windows["History"].exists, app.debugDescription)
    }

    func testAppShellHistoryBulletizeTransformPreservesBulletFormatInDetail() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--seed-history-transform-enabled"
        ])
        openAppShellHistory()

        postUITestCommand(historyCommandNotification, userInfo: ["command": "filter", "filter": "Successful"])
        postUITestCommand(historyCommandNotification, userInfo: [
            "command": "transform",
            "index": 0,
            "transformKind": "bulletize"
        ])

        XCTAssertTrue(app.descendants(matching: .any)["Select Alpha for Vocabulary"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["Select Beta for Vocabulary"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["Select Second for Vocabulary"].waitForExistence(timeout: 2), app.debugDescription)
        writeHistoryTransformScreenshot(name: "history-bulletize-row")

        postUITestCommand(historyCommandNotification, userInfo: ["command": "selectDetail", "index": 0])
        let editor = app.textViews["history.detail.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2), app.debugDescription)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        writeHistoryTransformScreenshot(name: "history-bulletize-detail")
        NSPasteboard.general.clearContents()
        clickElement(app.buttons["history.detail.copyButton"])
        let detailText = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertTrue(detailText.contains("- Alpha action from Second searchable transcript."), detailText)
        XCTAssertTrue(detailText.contains("- Beta action preserves the original transcript context."), detailText)
        XCTAssertFalse(app.windows["History"].exists, app.debugDescription)
    }

    func testAppShellShowsGeneralPreferences() {
        let openFoilButton = button(id: "menu.openFoilButton", fallbackLabel: "Open Foil")
        XCTAssertTrue(openFoilButton.waitForExistence(timeout: 2), app.debugDescription)
        openFoilButton.click()

        let generalNavItem = app.descendants(matching: .any)["appShell.nav.settings.general"]
        XCTAssertTrue(generalNavItem.waitForExistence(timeout: 4), app.debugDescription)
        generalNavItem.click()

        XCTAssertTrue(elementExists(id: "appShell.preferences", timeout: 4), app.debugDescription)
        XCTAssertEqual(generalNavItem.value as? String, "Selected")
        XCTAssertTrue(elementExists(id: "settings.general.versionRow", timeout: 2), app.debugDescription)
        XCTAssertTrue(checkBox(id: "settings.launchAtLoginToggle", fallbackLabel: "Launch at Login").exists, app.debugDescription)
        XCTAssertTrue(checkBox(id: "settings.soundEffectsToggle", fallbackLabel: "Sound effects").exists, app.debugDescription)
        XCTAssertTrue(checkBox(id: "settings.floatingStatusToggle", fallbackLabel: "Show floating status").exists, app.debugDescription)
        XCTAssertFalse(elementExists(id: "settings.tab.general", timeout: 1), app.debugDescription)
    }

    func testAppShellShowsAllSettingsSidebarPanes() {
        let openFoilButton = button(id: "menu.openFoilButton", fallbackLabel: "Open Foil")
        XCTAssertTrue(openFoilButton.waitForExistence(timeout: 2), app.debugDescription)
        openFoilButton.click()
        XCTAssertTrue(elementExists(id: "appShell.root", timeout: 4), app.debugDescription)

        assertAppShellSettingsPane(
            navID: "appShell.nav.settings.recording",
            requiredID: "settings.hotkeyPicker"
        )
        assertAppShellSettingsPane(
            navID: "appShell.nav.settings.transcription",
            requiredID: "settings.transcriptionProviderPicker"
        )
        assertAppShellSettingsPane(
            navID: "appShell.nav.settings.cleanup",
            requiredID: "settings.cleanupGroups.root"
        )
        assertAppShellSettingsPane(
            navID: "appShell.nav.settings.paste",
            requiredID: "settings.keepClipboardToggle"
        )
        assertAppShellSettingsPane(
            navID: "appShell.nav.settings.storage",
            requiredID: "settings.historyRetentionPicker"
        )
        assertAppShellSettingsPane(
            navID: "appShell.nav.settings.whatsNew",
            requiredID: "settings.whatsNew.versionText"
        )
        assertAppShellSettingsPane(
            navID: "appShell.nav.settings.experimental",
            requiredID: "settings.asyncPasteToggle"
        )
    }

    func testMenuHistoryButtonRoutesToAppShellHistory() {
        let historyButton = button(id: "menu.historyButton", fallbackLabel: "History")
        XCTAssertTrue(historyButton.waitForExistence(timeout: 2), app.debugDescription)
        historyButton.click()

        let historyNavItem = app.descendants(matching: .any)["appShell.nav.history"]
        XCTAssertTrue(historyNavItem.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertEqual(historyNavItem.value as? String, "Selected")
        XCTAssertTrue(elementExists(id: "appShell.history", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "history.root", timeout: 2), app.debugDescription)
        XCTAssertFalse(app.windows["History"].exists, app.debugDescription)
    }

    func testMenuSettingsButtonRoutesToAppShellGeneralPreferences() {
        let settingsButton = button(id: "menu.settingsButton", fallbackLabel: "Settings")
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2), app.debugDescription)
        settingsButton.click()

        let generalNavItem = app.descendants(matching: .any)["appShell.nav.settings.general"]
        XCTAssertTrue(generalNavItem.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertEqual(generalNavItem.value as? String, "Selected")
        XCTAssertTrue(elementExists(id: "appShell.preferences", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.general.versionRow", timeout: 2), app.debugDescription)
        XCTAssertFalse(app.windows["Settings"].exists, app.debugDescription)
    }

    func testCommandCommaRoutesToAppShellGeneralPreferences() {
        app.typeKey(",", modifierFlags: .command)

        let generalNavItem = app.descendants(matching: .any)["appShell.nav.settings.general"]
        XCTAssertTrue(generalNavItem.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertEqual(generalNavItem.value as? String, "Selected")
        XCTAssertTrue(elementExists(id: "appShell.preferences", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.general.versionRow", timeout: 2), app.debugDescription)
        XCTAssertFalse(app.windows["Settings"].exists, app.debugDescription)
    }

    func testControlCenterShowsRecentSuccessfulTranscriptions() {
        XCTAssertTrue(app.staticTexts["Recent Transcriptions"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Second searchable transcript."].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Seeded transcript for UI testing."].exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Seeded network failure"].exists)
        let copyButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Copy"))
        XCTAssertGreaterThanOrEqual(copyButtons.count, 2, app.debugDescription)
        XCTAssertTrue(app.buttons["Paste Again"].exists, app.debugDescription)
    }

    func testSetupCheckCanBeRunInline() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-setup-unknown"])
        postUITestCommand(runSetupCheckNotification)

        XCTAssertTrue(app.staticTexts["Setup Tested"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Ready to record"].exists)
    }

    func testSetupFailuresShowRecoveryDetails() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--seed-setup-failures"
        ])

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        let state = waitForUITestStateSnapshot { $0.sessionTitle == "Setup needed" }
        XCTAssertEqual(state?.accessibilityText, "Enable Accessibility")
        XCTAssertEqual(state?.microphoneText, "Allow microphone access")
        XCTAssertTrue(app.staticTexts["Enable Accessibility before recording."].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Open Microphone privacy").waitForExistence(timeout: 2), app.debugDescription)
    }

    func testUnknownSetupStateDoesNotShowReadySession() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--seed-setup-unknown"
        ])

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        let state = waitForUITestStateSnapshot { $0.sessionTitle == "Setup needed" }
        XCTAssertEqual(state?.sessionDetail, "Check Accessibility before recording")
        XCTAssertEqual(state?.accessibilityText, "Not checked")
        XCTAssertEqual(state?.accessibilityActionTitle, "Open Settings")
        XCTAssertTrue(app.staticTexts["Enable Accessibility before recording."].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Right Command · Pastes into current app"].exists)
    }

    func testNoAudioCapturedShowsWarningInSessionStrip() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--seed-no-audio-captured"
        ])

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        let state = waitForUITestStateSnapshot { $0.sessionTitle == "No audio captured" }
        XCTAssertEqual(state?.sessionDetail, "Try a longer recording or check your microphone input")
        XCTAssertTrue(app.staticTexts["No audio captured"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Try a longer recording or check your microphone input"].exists, app.debugDescription)
    }

    func testMicrophoneUnknownShowsCheckAction() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--seed-microphone-unknown"
        ])

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        let state = waitForUITestStateSnapshot { $0.microphoneText == "Not checked" }
        XCTAssertEqual(state?.accessibilityText, "Ready")
        XCTAssertEqual(state?.microphoneActionTitle, "Check")
        XCTAssertEqual(state?.sessionTitle, "Setup needed")
        XCTAssertTrue(app.staticTexts["Check microphone access before recording."].waitForExistence(timeout: 2), app.debugDescription)
    }

    func testMicrophoneDeniedShowsOpenSettingsAction() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--seed-microphone-denied"
        ])

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        let state = waitForUITestStateSnapshot { $0.microphoneText == "Allow microphone access" }
        XCTAssertEqual(state?.accessibilityText, "Ready")
        XCTAssertEqual(state?.microphoneActionTitle, "Open Settings")
        XCTAssertEqual(state?.sessionTitle, "Setup needed")
        XCTAssertTrue(app.staticTexts["Allow microphone access before recording."].waitForExistence(timeout: 2), app.debugDescription)
    }

    func testMicrophoneTimeoutShowsManualPrivacyRecovery() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--seed-microphone-timeout"
        ])

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
        let state = waitForUITestStateSnapshot { $0.microphoneText == microphonePromptTimedOutMessage }
        XCTAssertEqual(state?.accessibilityText, "Ready")
        XCTAssertEqual(state?.microphoneActionTitle, "Open Settings")
        XCTAssertEqual(state?.sessionTitle, "Setup needed")
        XCTAssertTrue(
            app.staticTexts["\(microphonePromptTimedOutMessage) before recording."].waitForExistence(timeout: 2),
            app.debugDescription
        )
    }

    func testOnboardingMicrophoneStepCanCheckPermission() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--show-onboarding",
            "--seed-microphone-unknown"
        ], requireControlCenter: false)

        XCTAssertTrue(app.windows["Welcome to Foil"].waitForExistence(timeout: 5), app.debugDescription)
        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "goToMicrophone"])

        XCTAssertTrue(app.staticTexts["Microphone Access"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Checking status"].exists || app.staticTexts["Checking..."].exists)
        assertButtonExists(id: "onboarding.checkMicrophoneButton", fallbackLabel: "Check Microphone Access")

        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "checkMicrophone"])
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 2), app.debugDescription)

        let getStartedButton = button(id: "onboarding.getStartedButton", fallbackLabel: "Get Started")
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(getStartedButton.isEnabled)
    }

    func testOnboardingAccessibilityStepShowsAlreadyGrantedPermission() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--show-onboarding",
            "--seed-setup-ready"
        ], requireControlCenter: false)

        let onboardingWindow = app.windows["Welcome to Foil"]
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 5), app.debugDescription)
        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "goToAccessibility"])

        XCTAssertTrue(onboardingWindow.staticTexts["Accessibility Permission"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(onboardingWindow.staticTexts["Ready"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(staticTextLabelOrValueContaining("Enable Accessibility", in: onboardingWindow).exists, app.debugDescription)
    }

    func testOnboardingAccessibilityStepUpdatesWhenPermissionBecomesReady() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--show-onboarding",
            "--seed-setup-failures"
        ], requireControlCenter: false)

        let onboardingWindow = app.windows["Welcome to Foil"]
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 5), app.debugDescription)
        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "goToAccessibility"])

        XCTAssertTrue(onboardingWindow.staticTexts["Accessibility Permission"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Enable Accessibility", in: onboardingWindow).waitForExistence(timeout: 2), app.debugDescription)

        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "grantAccessibility"])

        XCTAssertTrue(onboardingWindow.staticTexts["Ready"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(staticTextLabelOrValueContaining("Enable Accessibility", in: onboardingWindow).exists, app.debugDescription)
    }

    func testOnboardingMicrophoneStepUpdatesWhenPermissionBecomesReady() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--show-onboarding",
            "--seed-local-provider",
            "--seed-microphone-denied"
        ], requireControlCenter: false)

        let onboardingWindow = app.windows["Welcome to Foil"]
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 5), app.debugDescription)
        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "goToMicrophone"])

        XCTAssertTrue(onboardingWindow.staticTexts["Microphone Access"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Allow microphone access", in: onboardingWindow).waitForExistence(timeout: 2), app.debugDescription)
        let getStartedButton = button(id: "onboarding.getStartedButton", fallbackLabel: "Get Started")
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(getStartedButton.isEnabled)

        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "grantMicrophone"])

        XCTAssertTrue(onboardingWindow.staticTexts["Ready"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(getStartedButton.isEnabled)
    }

    func testOnboardingCanCompleteWhenPermissionsReadyAndApiKeyMissing() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--show-onboarding",
            "--seed-permissions-ready-api-missing"
        ], requireControlCenter: false)

        let onboardingWindow = app.windows["Welcome to Foil"]
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 5), app.debugDescription)
        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "goToMicrophone"])

        XCTAssertTrue(onboardingWindow.staticTexts["Microphone Access"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(onboardingWindow.staticTexts["Ready"].waitForExistence(timeout: 2), app.debugDescription)

        let getStartedButton = button(id: "onboarding.getStartedButton", fallbackLabel: "Get Started")
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(getStartedButton.isEnabled)

        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "complete"])
        XCTAssertFalse(onboardingWindow.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
    }

    func testOnboardingCompletionKeepsMenuBarAppRunning() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--show-onboarding",
            "--seed-setup-ready"
        ], requireControlCenter: false)

        XCTAssertTrue(app.windows["Welcome to Foil"].waitForExistence(timeout: 5), app.debugDescription)

        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "goToFinal"])

        XCTAssertTrue(button(id: "onboarding.getStartedButton", fallbackLabel: "Get Started").waitForExistence(timeout: 2), app.debugDescription)
        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "complete"])

        XCTAssertFalse(app.windows["Welcome to Foil"].waitForExistence(timeout: 2))
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5), app.debugDescription)
    }

    func testOnboardingLocalProviderDoesNotRequireAPIKey() {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--show-onboarding",
            "--seed-setup-ready"
        ], requireControlCenter: false)

        let onboardingWindow = app.windows["Welcome to Foil"]
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 5), app.debugDescription)
        let providerPicker = app.popUpButtons["onboarding.providerPicker"].exists
            ? app.popUpButtons["onboarding.providerPicker"]
            : onboardingWindow.popUpButtons.firstMatch
        XCTAssertTrue(providerPicker.waitForExistence(timeout: 2), app.debugDescription)
        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "selectLocalProvider"])

        XCTAssertTrue(staticTextLabelOrValueContaining("Audio stays on this Mac").waitForExistence(timeout: 2), app.debugDescription)
        postUITestCommand(onboardingCommandNotification, userInfo: ["command": "goToCredentials"])

        XCTAssertTrue(app.staticTexts["Credentials Optional"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["No API key required"].exists || app.staticTexts["Ready"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["onboarding.addApiKeyButton"].exists || app.buttons["Add API Key"].exists)
        XCTAssertTrue(
            app.buttons["onboarding.openTranscriptionSettingsButton"].exists
                || app.buttons["Open Transcription Settings"].exists,
            app.debugDescription
        )
    }

    func testHistoryComponentHostSearchesSeededRecords() {
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        let searchField = app.textFields["Search transcriptions..."]
        XCTAssertTrue(searchField.exists)
        postUITestCommand(historyCommandNotification, userInfo: ["command": "search", "query": "Second searchable"])

        XCTAssertTrue(app.descendants(matching: .any)["Select Second for Vocabulary"].waitForExistence(timeout: 2))

        postUITestCommand(historyCommandNotification, userInfo: ["command": "search", "query": "no matching transcript"])
        XCTAssertTrue(staticTextLabelOrValueContaining("No matches", in: historyPanel).waitForExistence(timeout: 4), app.debugDescription)
    }

    func testHistoryComponentHostFiltersBySourceApp() {
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        XCTAssertTrue(app.buttons["All apps"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.buttons["Messages"].waitForExistence(timeout: 2), app.debugDescription)
        clickElement(app.buttons["Mail"])

        XCTAssertTrue(app.descendants(matching: .any)["Select Second for Vocabulary"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["Select Seeded for Vocabulary"].exists, app.debugDescription)
        XCTAssertEqual(app.buttons["Mail"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["All apps"].value as? String, "Not selected")
    }

    func testHistoryComponentHostFiltersFailedRecords() {
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        XCTAssertTrue(app.buttons["All"].isEnabled)
        clickElement(app.buttons["Failed"])
        XCTAssertTrue(app.buttons["Failed"].isEnabled)

        XCTAssertTrue(app.staticTexts["Seeded network failure"].waitForExistence(timeout: 2))
    }

    func testHistoryComponentHostDeleteAndClearActions() {
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        XCTAssertTrue(app.descendants(matching: .any)["Select Second for Vocabulary"].exists)
        postUITestCommand(historyCommandNotification, userInfo: ["command": "showDeleteFirst"])
        XCTAssertTrue(app.staticTexts["Delete History Item?"].waitForExistence(timeout: 2))
        postUITestCommand(historyCommandNotification, userInfo: ["command": "cancelDeleteFirst"])
        XCTAssertTrue(app.staticTexts["Seeded network failure"].waitForExistence(timeout: 2))

        let detailsButtons = historyPanel.buttons.matching(NSPredicate(format: "label == %@", "Details"))
        XCTAssertGreaterThanOrEqual(detailsButtons.count, 2, app.debugDescription)
        postUITestCommand(historyCommandNotification, userInfo: ["command": "selectDetail", "index": 1])
        let editor = app.textViews["history.detail.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2), app.debugDescription)
        postUITestCommand(historyCommandNotification, userInfo: ["command": "showDetailDelete"])
        XCTAssertTrue(app.staticTexts["Delete this history item?"].waitForExistence(timeout: 2))
        postUITestCommand(historyCommandNotification, userInfo: ["command": "cancelDetailDelete"])
        XCTAssertTrue(editor.waitForExistence(timeout: 2), app.debugDescription)
        postUITestCommand(historyCommandNotification, userInfo: ["command": "dismissDetail"])
        XCTAssertFalse(editor.waitForExistence(timeout: 2), app.debugDescription)

        postUITestCommand(historyCommandNotification, userInfo: ["command": "showDeleteFiltered"])
        XCTAssertTrue(app.staticTexts["Delete Filtered History?"].waitForExistence(timeout: 2))
        postUITestCommand(historyCommandNotification, userInfo: ["command": "cancelDeleteFiltered"])
        XCTAssertTrue(app.staticTexts["Seeded network failure"].waitForExistence(timeout: 2))

        relaunchWithSeededHistory()
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        postUITestCommand(historyCommandNotification, userInfo: ["command": "showClear"])
        XCTAssertTrue(app.staticTexts["Clear History?"].waitForExistence(timeout: 2))
        postUITestCommand(historyCommandNotification, userInfo: ["command": "clear"])
        XCTAssertTrue(
            historyEmptyStateAppeared(timeout: 5),
            app.debugDescription
        )
    }

    func testHistoryComponentHostDetailAllowsEditingAndExport() {
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))
        assertButtonExists(id: "history.exportButton", fallbackLabel: "Export")

        let detailsButtons = historyPanel.buttons.matching(NSPredicate(format: "label == %@", "Details"))
        XCTAssertGreaterThanOrEqual(detailsButtons.count, 2, app.debugDescription)
        let firstVocabularyToken = app.descendants(matching: .any)["Select Second for Vocabulary"]
        XCTAssertTrue(firstVocabularyToken.waitForExistence(timeout: 2), app.debugDescription)
        firstVocabularyToken.click()
        let secondVocabularyToken = app.descendants(matching: .any)["Select searchable for Vocabulary"]
        XCTAssertTrue(secondVocabularyToken.waitForExistence(timeout: 2), app.debugDescription)
        secondVocabularyToken.click()
        let selectedVocabularyText = app.staticTexts["history.vocabulary.selectedText"]
        XCTAssertTrue(selectedVocabularyText.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(selectedVocabularyText.value as? String, "Second searchable")
        app.buttons["history.vocabulary.addSelectionButton"].click()
        let vocabularyWrittenAsField = app.textFields["history.vocabulary.writtenAsField"]
        XCTAssertTrue(vocabularyWrittenAsField.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(vocabularyWrittenAsField.value as? String, "Second searchable")
        XCTAssertTrue(elementExists(id: "history.vocabulary.correctVersionField", timeout: 2), app.debugDescription)
        app.buttons["history.vocabulary.cancelButton"].click()

        postUITestCommand(historyCommandNotification, userInfo: ["command": "selectDetail", "index": 1])
        let editor = app.textViews["history.detail.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Copy"].exists)
        XCTAssertTrue(app.buttons["Paste"].exists)
        XCTAssertTrue(app.buttons["Delete"].exists)
        postUITestCommand(historyCommandNotification, userInfo: ["command": "dismissDetail"])
    }

    func testHistoryComponentHostSavesSelectedTextAsPreferredTerm() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--settings-tab-cleanup",
            "--seed-cleanup-formatting-enabled"
        ])
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        let firstVocabularyToken = app.descendants(matching: .any)["Select Second for Vocabulary"]
        XCTAssertTrue(firstVocabularyToken.waitForExistence(timeout: 2), app.debugDescription)
        firstVocabularyToken.click()
        let secondVocabularyToken = app.descendants(matching: .any)["Select searchable for Vocabulary"]
        XCTAssertTrue(secondVocabularyToken.waitForExistence(timeout: 2), app.debugDescription)
        secondVocabularyToken.click()
        app.buttons["history.vocabulary.addSelectionButton"].click()

        let preferredTermModeButton = app.buttons["history.vocabulary.mode.preferredTerm"]
        XCTAssertTrue(preferredTermModeButton.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(preferredTermModeButton)

        let termField = app.textFields["history.vocabulary.termField"]
        XCTAssertTrue(termField.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(termField.value as? String, "Second searchable")
        clickElement(app.buttons["history.vocabulary.saveButton"])

        openSettingsPanel()
        let preferredTermsEditor = app.textViews["settings.preferredTermsEditor"]
        XCTAssertTrue(preferredTermsEditor.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertEqual(preferredTermsEditor.value as? String, "Second searchable")
    }

    func testHistoryComponentHostSaveAndRecleanVocabularySelection() {
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        let defaultToken = app.descendants(matching: .any)["Select Second for Vocabulary"]
        XCTAssertTrue(defaultToken.waitForExistence(timeout: 2), app.debugDescription)
        defaultToken.click()
        app.buttons["history.vocabulary.addSelectionButton"].click()
        let defaultWrittenAsField = app.textFields["history.vocabulary.writtenAsField"]
        XCTAssertTrue(defaultWrittenAsField.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(defaultWrittenAsField.value as? String, "Second")
        XCTAssertFalse(elementExists(id: "history.vocabulary.saveAndRecleanButton", timeout: 1), app.debugDescription)
        app.buttons["history.vocabulary.cancelButton"].click()

        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--seed-history-reclean-enabled"
        ])
        openHistoryWindow()
        XCTAssertTrue(waitForHistoryPanel(timeout: 3))

        let token = app.descendants(matching: .any)["Select Second for Vocabulary"]
        XCTAssertTrue(token.waitForExistence(timeout: 2), app.debugDescription)
        token.click()
        app.buttons["history.vocabulary.addSelectionButton"].click()

        let correctVersionField = app.textFields["history.vocabulary.correctVersionField"]
        XCTAssertTrue(correctVersionField.waitForExistence(timeout: 2), app.debugDescription)
        correctVersionField.click()
        correctVersionField.typeText("Supabase")

        let saveAndRecleanButton = app.buttons["history.vocabulary.saveAndRecleanButton"]
        XCTAssertTrue(saveAndRecleanButton.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(saveAndRecleanButton)

        XCTAssertTrue(app.descendants(matching: .any)["Select Re-cleaned for Vocabulary"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["Select Supabase for Vocabulary"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["Select Second for Vocabulary"].exists, app.debugDescription)
    }

    func testSettingsComponentHostOpensForDetailedPaneCoverage() {
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
    }

    func testTranscriptCleanupFormattingSettingsAreHiddenUntilEnabled() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-cleanup"])
        openSettingsPanel()

        XCTAssertTrue(app.buttons["Cleanup"].exists, app.debugDescription)
        XCTAssertEqual(app.buttons["Cleanup"].value as? String, "Selected")
        XCTAssertTrue(cleanupGroupModePicker.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(cleanupGroupModePickerValueContains("Raw transcript"), app.debugDescription)
        XCTAssertFalse(elementExists(id: "settings.cleanupGroups.providerPicker", timeout: 1), app.debugDescription)
        XCTAssertFalse(staticTextLabelOrValueContaining("Prompt").exists, app.debugDescription)
        XCTAssertFalse(cleanupPromptEditorValueContains("Clean up the transcript"), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Vocabulary").waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Preferred terms").waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("applied when you choose Cleanup profile").waitForExistence(timeout: 2), app.debugDescription)

        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-cleanup", "--seed-cleanup-formatting-enabled"])
        openSettingsPanel()

        XCTAssertTrue(cleanupGroupModePicker.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(cleanupGroupModePickerValueContains("Cleanup profile"), app.debugDescription)

        XCTAssertTrue(cleanupGroupProviderPicker.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(cleanupGroupGroqModelPickerValueContains("Llama 3.1 8B Instant"), app.debugDescription)
        XCTAssertTrue(cleanupPromptEditor.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(cleanupGroupResetPromptButton.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Vocabulary").waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(app.textFields["Foil wrote"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(app.textFields["Use this instead"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(app.buttons["Add correction"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Preferred terms").waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Fix punctuation, capitalization, filler, stutters").waitForExistence(timeout: 2), app.debugDescription)
    }

    func testActiveCleanupModeSelectorPersistsAndScreenshotsResult() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-cleanup"])
        openAppShellCleanupSettings()

        XCTAssertTrue(cleanupGroupModePicker.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(cleanupGroupModePickerValueContains("Raw transcript"), app.debugDescription)
        writeActiveModeScreenshot(name: "selector-raw")

        selectActiveCleanupMode("Cleanup profile")
        XCTAssertTrue(cleanupGroupModePickerValueContains("Cleanup profile"), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Fix punctuation, capitalization, filler, stutters").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(cleanupGroupProviderPicker.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(cleanupPromptEditor.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(cleanupPromptEditorValueContains("Clean up the transcript"), app.debugDescription)
        writeActiveModeScreenshot(name: "selector-cleanup-profile")

        relaunchWithArguments(["--ui-testing", "--seed-history", "--settings-tab-cleanup"])
        openAppShellCleanupSettings()
        XCTAssertTrue(cleanupGroupModePicker.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(cleanupGroupModePickerValueContains("Cleanup profile"), app.debugDescription)

        relaunchWithArguments(["--ui-testing", "--seed-history", "--simulate-success-after-launch"])
        XCTAssertTrue(staticTextLabelOrValueContaining("Mock async paste transcript").waitForExistence(timeout: 6), app.debugDescription)
        writeActiveModeScreenshot(name: "cleanup-profile-result")
    }

    func testHomeShowsCleanupGroupStatusWithoutGlobalModeSelector() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history"])
        openAppShellHome()

        assertDefaultCleanupGroupStatusVisible()
        XCTAssertFalse(elementExists(id: "appShell.home.activeCleanupModePicker", timeout: 1), app.debugDescription)
    }

    func testHomeCleanupGroupStatusShowsUnavailableCleanupFallback() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--seed-cleanup-formatting-enabled",
            "--seed-cleanup-provider-none"
        ])
        openAppShellHome()

        XCTAssertTrue(
            staticTextLabelOrValueContaining("cleanup is unavailable").waitForExistence(timeout: 2),
            app.debugDescription
        )
        XCTAssertTrue(
            staticTextLabelOrValueContaining("paste raw transcripts").waitForExistence(timeout: 2),
            app.debugDescription
        )
    }

    func testMenuBarShowsCleanupGroupStatusWithoutGlobalModeSelector() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history"])

        assertDefaultCleanupGroupStatusVisible()
        XCTAssertFalse(elementExists(id: "menu.recording.activeCleanupModePicker", timeout: 1), app.debugDescription)
    }

    func testActiveCleanupPromptEditorPersistsAndResetsCustomPrompt() {
        let customPrompt = """
        Return exactly two lines.
        First line must start with CUSTOM-1: and include the launch checklist.
        Second line must start with CUSTOM-2: and include Chrome, Terminal, TextEdit, and the Foil demo.
        Do not add any other lines.
        """

        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-cleanup"])
        openAppShellCleanupSettings()

        selectActiveCleanupMode("Cleanup profile")
        XCTAssertTrue(cleanupPromptEditorValueContains("Clean up the transcript"), app.debugDescription)

        postUITestCommand(appCommandNotification, userInfo: [
            "command": "setDefaultCleanupPrompt",
            "prompt": customPrompt
        ])
        XCTAssertTrue(waitForCleanupPromptEditorValueContaining("CUSTOM-1:"), app.debugDescription)
        XCTAssertFalse(cleanupPromptEditorValueContains("Clean up the transcript"), app.debugDescription)
        writeActiveModeScreenshot(name: "selector-custom-prompt")

        relaunchWithArguments(["--ui-testing", "--seed-history", "--settings-tab-cleanup"])
        openAppShellCleanupSettings()
        XCTAssertTrue(cleanupGroupModePickerValueContains("Cleanup profile"), app.debugDescription)
        XCTAssertTrue(cleanupPromptEditorValueContains("CUSTOM-1:"), app.debugDescription)
        XCTAssertFalse(cleanupPromptEditorValueContains("Clean up the transcript"), app.debugDescription)

        postUITestCommand(appCommandNotification, userInfo: ["command": "resetDefaultCleanupPrompt"])
        XCTAssertTrue(waitForCleanupPromptEditorValueContaining("Clean up the transcript"), app.debugDescription)
        XCTAssertFalse(cleanupPromptEditorValueContains("CUSTOM-1:"), app.debugDescription)

        relaunchWithArguments(["--ui-testing", "--seed-history", "--settings-tab-cleanup"])
        openAppShellCleanupSettings()
        XCTAssertTrue(cleanupPromptEditorValueContains("Clean up the transcript"), app.debugDescription)
        XCTAssertFalse(cleanupPromptEditorValueContains("CUSTOM-1:"), app.debugDescription)
    }

    func testCleanupTabShowsOpenAICloudCleanupControls() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--settings-tab-cleanup",
            "--seed-cleanup-formatting-enabled",
            "--seed-openai-cleanup-provider"
        ])
        openSettingsPanel()

        XCTAssertTrue(app.buttons["Cleanup"].exists, app.debugDescription)
        XCTAssertEqual(app.buttons["Cleanup"].value as? String, "Selected")

        XCTAssertTrue(cleanupGroupModePicker.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(cleanupGroupModePickerValueContains("Cleanup profile"), app.debugDescription)

        XCTAssertTrue(cleanupGroupProviderPicker.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(
            cleanupGroupOpenAIModelPickerValueContains("GPT-5.4 mini")
                || app.staticTexts["GPT-5.4 mini"].exists,
            app.debugDescription
        )
        XCTAssertTrue(elementExists(id: "settings.cleanupGroups.openAIAPIKey", timeout: 4), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.cleanupGroups.saveOpenAIAPIKeyButton", timeout: 4), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.cleanupGroups.deleteOpenAIAPIKeyButton", timeout: 4), app.debugDescription)
    }

    func testProviderQAOpenAIWhisperPresetShowsCloudSettings() {
        launchForProviderQA(extraArguments: ["--seed-openai-provider"])
        openTranscriptionSettingsPanel()

        assertProviderPickerExists()
        XCTAssertTrue((providerPicker.value as? String) == "OpenAI Whisper" || app.staticTexts["OpenAI Whisper"].exists, app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Audio is sent to OpenAI for Whisper transcription").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("OpenAI Whisper API key").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["https://api.openai.com/v1"].exists || staticTextContaining("api.openai.com/v1").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["whisper-1"].exists || staticTextContaining("whisper-1").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Audio is sent to OpenAI's cloud transcription endpoint").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(customBaseURLField.exists)
        XCTAssertFalse(providerConnectionButton().exists)
    }

    func testSettingsWhatsNewShowsCurrentVersionAndUpdateControl() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-whats-new"])
        openSettingsPanel()

        XCTAssertTrue(app.buttons["What's New"].exists, app.debugDescription)
        XCTAssertEqual(app.buttons["What's New"].value as? String, "Selected")
        let versionPredicate = NSPredicate(
            format: "identifier == %@ AND value MATCHES %@",
            "settings.whatsNew.versionText",
            #"^\d+\.\d+\.\d+ \(\d+\)$"#
        )
        let versionValue = app.staticTexts.matching(versionPredicate).firstMatch
        XCTAssertTrue(versionValue.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(button(id: "settings.whatsNew.checkForUpdatesButton", fallbackLabel: "Check for Updates…").exists)
        XCTAssertTrue(staticTextLabelOrValueContaining("1.13.7").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Added a macOS CI eligibility check").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Release notes are bundled with Foil").waitForExistence(timeout: 2), app.debugDescription)
    }

    func testProviderQALocalWhisperPresetShowsExpectedSettings() {
        launchForProviderQA(extraArguments: ["--seed-local-provider"])
        openTranscriptionSettingsPanel()

        assertProviderPickerExists()
        XCTAssertTrue((providerPicker.value as? String) == "Local whisper.cpp" || app.staticTexts["Local whisper.cpp"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["http://127.0.0.1:8080/v1"].exists || app.staticTexts["127.0.0.1:8080/v1"].exists, app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Audio stays on this Mac").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Local Server"].exists || staticTextLabelOrValueContaining("Local Server").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(staticTextLabelOrValueContaining("Local whisper.cpp API key").exists, app.debugDescription)
        XCTAssertFalse(elementExists(id: "settings.changeApiKeyButton", timeout: 1), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("without credentials").exists
                      || elementExists(id: "settings.localProviderHelp", timeout: 1),
                      app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Start the local whisper-server first").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.localWhisperStartServerButton", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.localWhisperServerStatus", timeout: 2), app.debugDescription)
        XCTAssertTrue(app.buttons["Test connection"].exists || app.buttons["settings.testProviderConnectionButton"].exists || app.buttons["menu.settings.testProviderConnectionButton"].exists, app.debugDescription)
    }

    func testProviderQALocalWhisperCanBeSelectedFromDefaultSettings() {
        launchForProviderQA()
        openTranscriptionSettingsPanel()

        assertProviderPickerExists()
        XCTAssertEqual(providerPicker.value as? String, "Groq")

        postUITestCommand(appCommandNotification, userInfo: ["command": "selectLocalProvider"])

        XCTAssertTrue((providerPicker.value as? String) == "Local whisper.cpp" || app.staticTexts["Local whisper.cpp"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["http://127.0.0.1:8080/v1"].waitForExistence(timeout: 2) || app.staticTexts["127.0.0.1:8080/v1"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["whisper-1"].exists || staticTextContaining("whisper-1").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Install whisper.cpp").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Local Server"].exists || staticTextLabelOrValueContaining("Local Server").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(staticTextLabelOrValueContaining("Local whisper.cpp API key").exists, app.debugDescription)
        XCTAssertFalse(elementExists(id: "settings.changeApiKeyButton", timeout: 1), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.localWhisperStartServerButton", timeout: 2), app.debugDescription)
        XCTAssertTrue(providerConnectionButton().waitForExistence(timeout: 2), app.debugDescription)
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
        XCTAssertTrue(staticTextLabelOrValueContaining("will not install, build, clone, or download files automatically").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("--inference-path /v1/audio/transcriptions").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.localWhisperCloneCommand.copyButton", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.localWhisperBuildCommand.copyButton", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.localWhisperDownloadCommand.copyButton", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.localWhisperStartServerCommand.copyButton", timeout: 2), app.debugDescription)
    }

    func testProviderQALocalWhisperSelectionPersistsAcrossRelaunch() {
        launchForProviderQA()
        openTranscriptionSettingsPanel()

        postUITestCommand(appCommandNotification, userInfo: ["command": "selectLocalProvider"])
        XCTAssertTrue((providerPicker.value as? String) == "Local whisper.cpp" || app.staticTexts["Local whisper.cpp"].exists, app.debugDescription)

        launchApp(arguments: [
            "--ui-testing",
            "--seed-history"
        ])
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
        postUITestCommand(appCommandNotification, userInfo: ["command": "testProviderConnection"])

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

        launchApp(arguments: [
            "--ui-testing",
            "--seed-history"
        ])
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

        launchApp(arguments: [
            "--ui-testing",
            "--seed-history",
            "--settings-tab-experimental"
        ])

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5))
        openSettingsPanel()
        XCTAssertTrue(checkBox(id: "settings.mockToggle", fallbackLabel: "Mock transcription").exists)
    }

    func testQueuedPasteSettingsPersistAcrossLaunches() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-experimental"])
        openSettingsPanel()

        let toggle = checkBox(id: "settings.queuedPasteToggle", fallbackLabel: "Queue transcriptions for later paste")
        XCTAssertTrue(toggle.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(toggle)
        XCTAssertTrue(elementExists(id: "settings.queuedPasteModePicker", timeout: 2), app.debugDescription)
        XCTAssertTrue(elementExists(id: "settings.queuedPasteDeliveryShortcut", timeout: 2), app.debugDescription)

        launchApp(arguments: [
            "--ui-testing",
            "--seed-history",
            "--settings-tab-experimental"
        ])

        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5))
        openSettingsPanel()
        XCTAssertTrue(elementExists(id: "settings.queuedPasteModePicker", timeout: 2), app.debugDescription)
    }

    func testSimulatedRecordingUsesCurrentAppPasteWhenAsyncIsOff() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--simulate-success-after-launch"])

        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["Done"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Mock async paste transcript"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Clipboard restored"].exists)
    }

    func testSimulatedRecordingUsesAsyncPasteWhenEnabled() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-async-paste-enabled", "--simulate-success-after-launch"])

        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Mock async paste transcript"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Pasted into the test target"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Target: Foil UI Test"].exists)
    }

    func testQueuedPasteShowsCountAndPastesNextItem() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--seed-queued-paste-enabled",
            "--simulate-success-after-launch"
        ])

        XCTAssertTrue(app.staticTexts["Transcript queued"].waitForExistence(timeout: 6), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Paste Queue"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["1 queued"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Pending"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Mock async paste transcript"].waitForExistence(timeout: 2), app.debugDescription)

        let pasteNextButton = app.buttons
            .matching(NSPredicate(format: "label == %@", "Paste Next"))
            .firstMatch
        XCTAssertTrue(pasteNextButton.waitForExistence(timeout: 5), app.debugDescription)
        clickElement(pasteNextButton)

        XCTAssertTrue(app.staticTexts["Pasted into the test target"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(app.staticTexts["0 queued"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Pending"].waitForExistence(timeout: 1))
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

        postUITestCommand(appCommandNotification, userInfo: ["command": "cancelTranscription"])

        XCTAssertTrue(waitForSessionTitle("Ready", timeout: 4), app.debugDescription)
        XCTAssertFalse(cancelButton.isEnabled)
    }

    func testFloatingStatusCanBeEnabled() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-floating-status-enabled", "--simulate-success-after-launch"])

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

    func testCleanupFallbackWarningIsVisible() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-floating-status-enabled"])
        postUITestCommand(appCommandNotification, userInfo: ["command": "seedCleanupFallbackWarning"])

        XCTAssertTrue(staticTextLabelOrValueContaining("Cleanup failed; pasted raw transcript.").waitForExistence(timeout: 2), app.debugDescription)
    }

    func testFloatingStatusShowsRecordingByDefault() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-recording"])

        XCTAssertTrue(app.descendants(matching: .any)["floatingStatus.window"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["liveFeedback.hud"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["liveFeedback.title"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Recording").waitForExistence(timeout: 2), app.debugDescription)
    }

    func testFloatingStatusShowsActiveCleanupModeWhileRecording() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-cleanup-formatting-enabled", "--seed-recording"])

        XCTAssertTrue(app.descendants(matching: .any)["floatingStatus.window"].waitForExistence(timeout: 4), app.debugDescription)
        let liveFeedback = app.descendants(matching: .any)["liveFeedback.hud"]
        XCTAssertTrue(liveFeedback.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Cleanup profile", in: liveFeedback).waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Release Right Command", in: liveFeedback).exists, app.debugDescription)
    }

    func testLiveAudioSignifierShowsIdleAndRecordingStates() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history"])

        var signifier = app.descendants(matching: .any)["liveAudioSignifier.capsule"]
        XCTAssertTrue(app.descendants(matching: .any)["liveAudioSignifier.window"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(signifier.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(signifier.label, "Ready")

        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-recording"])

        signifier = app.descendants(matching: .any)["liveAudioSignifier.capsule"]
        XCTAssertTrue(app.descendants(matching: .any)["liveAudioSignifier.window"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(signifier.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(signifier.label, "Recording audio level, Raw transcript")
    }

    func testLiveAudioSignifierIncludesActiveCleanupModeWhileRecording() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--seed-cleanup-formatting-enabled", "--seed-recording"])

        let signifier = app.descendants(matching: .any)["liveAudioSignifier.capsule"]
        XCTAssertTrue(app.descendants(matching: .any)["liveAudioSignifier.window"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(signifier.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(signifier.label, "Recording audio level, Cleanup profile")
    }

    func testLiveAudioSignifierUsesEffectiveCleanupModeWhenCleanupUnavailable() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history",
            "--seed-cleanup-formatting-enabled",
            "--seed-cleanup-provider-none",
            "--seed-recording"
        ])

        let signifier = app.descendants(matching: .any)["liveAudioSignifier.capsule"]
        XCTAssertTrue(app.descendants(matching: .any)["liveAudioSignifier.window"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(signifier.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(signifier.label, "Recording audio level, Raw transcript")
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
        XCTAssertTrue(app.windows["Foil Floating Status"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Paste command sent to the current app"].waitForExistence(timeout: 2))
    }

    func testMovedPreferencesLiveInSettingsPanes() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-paste"])
        openSettingsPanel()
        XCTAssertTrue(checkBox(id: "settings.keepClipboardToggle", fallbackLabel: "Keep final text on clipboard").exists)

        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-general"])
        openSettingsPanel()
        XCTAssertTrue(checkBox(id: "settings.floatingStatusToggle", fallbackLabel: "Show floating status").exists)
        let versionPredicate = NSPredicate(
            format: "identifier == %@ AND value MATCHES %@",
            "settings.general.versionRow",
            #"^\d+\.\d+\.\d+ \(\d+\)$"#
        )
        let versionValue = app.staticTexts.matching(versionPredicate).firstMatch
        XCTAssertTrue(versionValue.waitForExistence(timeout: 2), app.debugDescription)
        writeSettingsScreenshotIfRequested(name: "settings-general-version")

        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-cleanup"])
        openSettingsPanel()
        XCTAssertTrue(staticTextLabelOrValueContaining("Groups").waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(app.buttons["Add cleanup group"].waitForExistence(timeout: 4), app.debugDescription)

        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-experimental"])
        openSettingsPanel()
        XCTAssertTrue(checkBox(id: "settings.asyncPasteToggle", fallbackLabel: "Return to starting app").exists)
        XCTAssertTrue(checkBox(id: "settings.queuedPasteToggle", fallbackLabel: "Queue transcriptions for later paste").exists)
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

    func testRecordingSoundPickersShowBuiltInDefaults() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-recording"])
        openSettingsPanel()

        let startPicker = app.popUpButtons["settings.recordingStartSoundPicker"]
        let endPicker = app.popUpButtons["settings.recordingEndSoundPicker"]

        XCTAssertTrue(startPicker.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(endPicker.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertEqual(startPicker.value as? String, "Bottle")
        XCTAssertEqual(endPicker.value as? String, "Pop")
        XCTAssertTrue(app.buttons["settings.recordingStartSoundPreviewButton"].exists)
        XCTAssertTrue(app.buttons["settings.recordingEndSoundPreviewButton"].exists)
    }

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

    func testConfiguredHotkeyChoicesStartAndStopAfterSwitching() {
        relaunchWithArguments(["--ui-testing", "--reset-defaults", "--seed-history", "--settings-tab-recording"])

        let choices: [(rawValue: String, label: String)] = [
            ("rightCommand", "Right Command"),
            ("rightOption", "Right Option"),
            ("globeFn", "Globe/Fn"),
            ("custom", "Space")
        ]

        for choice in choices {
            postUITestCommand(appCommandNotification, userInfo: ["command": "prepareHotkeySwitchingAcceptance"])
            postUITestCommand(appCommandNotification, userInfo: [
                "command": "selectRecordingHotkey",
                "choice": choice.rawValue
            ])

            let configured = waitForUITestStateSnapshot { snapshot in
                snapshot.statusText == "Ready" && snapshot.sessionDetail.contains(choice.label)
            }
            XCTAssertNotNil(configured, "Expected selected hotkey \(choice.rawValue) to appear in ready session detail")

            postUITestCommand(appCommandNotification, userInfo: ["command": "simulateSelectedHotkeyCycle"])

            let state = waitForUITestStateSnapshot { snapshot in
                snapshot.recordingEvents.contains { $0.name == "audioRecorderStart" }
                    && snapshot.recordingEvents.contains { $0.name == "audioRecorderStop" }
            }

            guard let events = state?.recordingEvents else {
                XCTFail("Expected recording events after \(choice.rawValue) hotkey cycle")
                return
            }

            let start = requireRecordingEvent(named: "audioRecorderStart", in: events)
            let stop = requireRecordingEvent(named: "audioRecorderStop", in: events)
            XCTAssertLessThan(
                start.uptimeNanoseconds,
                stop.uptimeNanoseconds,
                "\(choice.rawValue) should start recording before it stops"
            )
        }
    }

    func testHelpButtonTargetsCanonicalTroubleshootingURL() throws {
        removeOpenedURLRecord()
        postUITestCommand(openHelpNotification)

        XCTAssertTrue(waitForOpenedURL(timeout: 5), app.debugDescription)
        let openedURL = try String(contentsOf: openedURLPath, encoding: .utf8)
        XCTAssertEqual(openedURL, "https://github.com/usefoil/foil#troubleshooting")
    }

    func testOnboardingNotShownForReturningUser() {
        launchApp(arguments: ["--ui-testing"], requireControlCenter: false)
        // UI testing mode should skip onboarding
        XCTAssertFalse(app.windows["Welcome to Foil"].exists)
    }

    func testLiveMicrophoneSmoke() throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_MICROPHONE_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_MICROPHONE_TESTS=1 to run live microphone QA.")
        }

        let resultPath = ProcessInfo.processInfo.environment["LIVE_MICROPHONE_RESULT_PATH"]
            ?? "/tmp/foil-live-microphone-result.txt"
        try? FileManager.default.removeItem(atPath: resultPath)
        let recordingScreenshotPath = liveMicrophoneScreenshotPath(resultPath: resultPath, variant: "recording-ui")
        let finalScreenshotPath = liveMicrophoneScreenshotPath(resultPath: resultPath, variant: "ui")
        for screenshotPath in [recordingScreenshotPath, finalScreenshotPath].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: screenshotPath)
        }

        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--seed-setup-ready",
            "--live-microphone-smoke"
        ], extraEnvironment: liveMicrophoneEnvironment(resultPath: resultPath), requireControlCenter: false)

        let recordingResult = waitForLiveMicrophoneResult(at: resultPath, timeout: 20) { result in
            result.contains("status=recording") || result.contains("status=pass") || result.contains("status=fail")
        }
        guard recordingResult.contains("status=recording") else {
            XCTFail("Live microphone smoke did not expose recording UX before finishing:\n\(recordingResult)")
            return
        }
        assertLiveMicrophoneRecordingUX(result: recordingResult)
        writeLiveMicrophoneScreenshotIfRequested(to: recordingScreenshotPath)

        let result = waitForLiveMicrophoneResult(at: resultPath, timeout: 20) { result in
            result.contains("status=pass") || result.contains("status=fail")
        }
        assertLiveMicrophoneReadyUX()
        writeLiveMicrophoneScreenshotIfRequested(to: finalScreenshotPath)

        guard !result.isEmpty else {
            XCTFail("Live microphone smoke produced no result file. Check macOS Microphone permission for Foil, selected input device, and any blocking TCC prompt.")
            return
        }

        XCTAssertFalse(result.contains("status=started"), "Live microphone smoke did not finish. Check microphone permission/TCC prompt or selected input device:\n\(result)")
        XCTAssertFalse(result.contains("status=recording"), "Live microphone smoke started but did not stop. Check input-device or recorder state:\n\(result)")
        XCTAssertTrue(result.contains("status=pass"), "Live microphone smoke failed:\n\(result)")
        XCTAssertFalse(result.contains("bytes=0"), "Live microphone smoke captured no audio:\n\(result)")
        if ProcessInfo.processInfo.environment["LIVE_MICROPHONE_INPUT_ROUTE"] == "built-in" {
            XCTAssertTrue(result.contains("input_route_request=built-in"), "Live microphone smoke did not request the built-in route:\n\(result)")
            XCTAssertTrue(result.contains("selected_input_transport=Built-in"), "Live microphone smoke did not select a built-in input:\n\(result)")
        }
        if ProcessInfo.processInfo.environment["LIVE_MICROPHONE_APPLE_VOICE_TEXT"]?.isEmpty == false {
            XCTAssertTrue(result.contains("apple_voice_playback=enabled"), "Apple voice playback was not enabled:\n\(result)")
            XCTAssertTrue(result.contains("apple_voice_process_started=true"), "Apple voice process did not start:\n\(result)")
            let observedPeak = max(
                liveMicrophoneFloatValue(named: "level_peak", in: result),
                liveMicrophoneFloatValue(named: "file_level_peak", in: result)
            )
            XCTAssertGreaterThanOrEqual(
                observedPeak,
                0.02,
                "Apple voice playback did not produce a captured microphone level above threshold:\n\(result)"
            )
        }
    }

    // MARK: - E2E Transcription (requires provider API key)

    func testE2ETranscription() throws {
        let env = ProcessInfo.processInfo.environment
        let isOpenAIE2E = env["E2E_TRANSCRIPTION_PROVIDER"] == "openai"
        let isOpenAICompatibleE2E = env["E2E_TRANSCRIPTION_PROVIDER"] == "openai-compatible"
        let apiKey: String
        if isOpenAIE2E || isOpenAICompatibleE2E {
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

        let resultPath = env["E2E_RESULT_PATH"] ?? "/tmp/foil-e2e-result.txt"
        let cleanupReceiptPath = env["E2E_CLEANUP_RECEIPT_PATH"] ?? "/tmp/foil-e2e-cleanup-receipt.txt"
        try? FileManager.default.removeItem(atPath: resultPath)
        try? FileManager.default.removeItem(atPath: cleanupReceiptPath)

        var environment = ["E2E_API_KEY": apiKey]
        if isOpenAIE2E {
            environment["E2E_TRANSCRIPTION_PROVIDER"] = "openai"
            environment["E2E_TRANSCRIPTION_MODEL"] = env["E2E_TRANSCRIPTION_MODEL"] ?? "whisper-1"
        } else if isOpenAICompatibleE2E {
            environment["E2E_TRANSCRIPTION_PROVIDER"] = "openai-compatible"
            environment["E2E_TRANSCRIPTION_BASE_URL"] = env["E2E_TRANSCRIPTION_BASE_URL"] ?? "http://127.0.0.1:8080/v1"
            environment["E2E_TRANSCRIPTION_MODEL"] = env["E2E_TRANSCRIPTION_MODEL"] ?? "whisper-1"
        } else if let model = env["E2E_TRANSCRIPTION_MODEL"] {
            environment["E2E_TRANSCRIPTION_MODEL"] = model
        }
        if let wavPath = env["E2E_WAV_PATH"], !wavPath.isEmpty {
            environment["E2E_WAV_PATH"] = wavPath
        }
        for key in [
            "E2E_CLEANUP_PROVIDER",
            "E2E_CLEANUP_MODE",
            "E2E_CLEANUP_MODEL",
            "E2E_CLEANUP_BASE_URL",
            "E2E_CLEANUP_API_KEY"
        ] {
            if let value = env[key], !value.isEmpty {
                environment[key] = value
            }
        }
        let requestedCleanupProvider = env["E2E_CLEANUP_PROVIDER"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedCleanupMode = env["E2E_CLEANUP_MODE"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedCleanupMode = requestedCleanupMode?.isEmpty == false ? requestedCleanupMode! : "cleanUp"
        if let requestedCleanupProvider, !requestedCleanupProvider.isEmpty, requestedCleanupProvider != "none" {
            environment["E2E_CLEANUP_RECEIPT_PATH"] = cleanupReceiptPath
        }
        environment["E2E_RESULT_PATH"] = resultPath

        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--e2e-transcribe"
        ], extraEnvironment: environment)

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

        if let requestedCleanupProvider, !requestedCleanupProvider.isEmpty, requestedCleanupProvider != "none" {
            let receipt = waitForTextFile(atPath: cleanupReceiptPath, timeout: 5)
            XCTAssertFalse(receipt.isEmpty, "Cleanup receipt should be written when E2E_CLEANUP_PROVIDER=\(requestedCleanupProvider)")
            let fields = keyValueReceiptFields(receipt)
            XCTAssertEqual(fields["status"], "applied", "Cleanup did not complete successfully:\n\(receipt)")
            XCTAssertEqual(fields["provider"], requestedCleanupProvider)
            XCTAssertEqual(fields["mode"], expectedCleanupMode)
            if let expectedModel = env["E2E_CLEANUP_MODEL"], !expectedModel.isEmpty {
                XCTAssertEqual(fields["model"], expectedModel)
            }
            XCTAssertGreaterThan(Int(fields["input_length"] ?? "0") ?? 0, 0, receipt)
            XCTAssertGreaterThan(Int(fields["output_length"] ?? "0") ?? 0, 0, receipt)
        }
    }

    private func waitForTextFile(atPath path: String, timeout: TimeInterval) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOfFile: path, encoding: .utf8),
               !text.isEmpty {
                return text
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func keyValueReceiptFields(_ receipt: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: receipt
            .split(separator: "\n")
            .compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), String(parts[1]))
            })
    }

    private func readGroqKeyViaCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", "com.neonwatty.Foil",
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
        if app.windows["Foil UI Test"].exists {
            return app.windows["Foil UI Test"]
        }
        return app.staticTexts["Ready"]
    }

    private var uiTestControlCenterHost: XCUIElement {
        app.descendants(matching: .any)["uiTest.controlCenter"]
    }

    private func launchApp(
        arguments: [String],
        extraEnvironment: [String: String] = [:],
        requireControlCenter: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        terminateAppAndStaleInstances()
        dismissSystemSetupAssistant()

        app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["FOIL_UITEST_STATE_PATH"] = stateSnapshotURL.path
        app.launchEnvironment["FOIL_UITEST_COMMAND_PATH"] = commandInboxURL.path
        app.launchEnvironment["FOIL_UITEST_OPENED_URL_PATH"] = openedURLPath.path
        for (key, value) in extraEnvironment {
            app.launchEnvironment[key] = value
        }
        removeUITestStateSnapshot()
        removeUITestCommandInbox()
        removeOpenedURLRecord()
        clearPendingAppShellSelection()
        app.launch()
        dismissSystemSetupAssistant()

        if requireControlCenter {
            XCTAssertTrue(controlCenter.waitForExistence(timeout: 8), app.debugDescription, file: file, line: line)
        }
        // GitHub's macOS runners can report this menu bar app as disabled/backgrounded
        // even after the UI-test host exists. Keep setup focused on launch readiness;
        // click helpers reactivate the app before interaction.
        _ = waitForAppForeground(timeout: 2)
    }

    private func terminateAppAndStaleInstances() {
        if app != nil {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 3)
        }
        runQuietProcess("/usr/bin/pkill", arguments: ["-x", "Foil"])
        runQuietProcess("/usr/bin/pkill", arguments: ["-x", "Foil"])
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if !processExists(named: "Foil") && !processExists(named: "Foil") {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.75))
    }

    @discardableResult
    private func waitForAppForeground(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.state == .runningForeground {
                return true
            }
            activateAppForInteraction()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return app.state == .runningForeground
    }

    private func activateAppForInteraction() {
        runQuietProcess("/usr/bin/open", arguments: ["-b", "com.neonwatty.Foil"])
    }

    private func runQuietProcess(_ executable: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private func processExists(named processName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", processName]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func dismissSystemSetupAssistant() {
        runQuietProcess("/usr/bin/osascript", arguments: [
            "-e",
            "tell application id \"com.apple.SetupAssistant\" to quit"
        ])
        runQuietProcess("/usr/bin/pkill", arguments: ["-x", "Setup Assistant"])
        runQuietProcess("/usr/bin/pkill", arguments: ["-f", "com.apple.SetupAssistant"])
    }

    private func launchForProviderQA(extraArguments: [String] = []) {
        launchApp(arguments: [
            "--ui-testing",
            "--reset-defaults",
            "--seed-history"
        ] + extraArguments)
    }

    private func openSettingsPanel() {
        openAppShellSettings(navID: settingsNavIDForLaunchArguments())
    }

    private func openTranscriptionSettingsPanel() {
        openAppShellSettings(navID: "appShell.nav.settings.transcription")
        XCTAssertTrue(providerPickerExists(timeout: 6), app.debugDescription)
    }

    private func openAppShellHistory() {
        let openFoilButton = button(id: "menu.openFoilButton", fallbackLabel: "Open Foil")
        XCTAssertTrue(openFoilButton.waitForExistence(timeout: 2), app.debugDescription)
        openFoilButton.click()

        let historyNavItem = app.descendants(matching: .any)["appShell.nav.history"]
        XCTAssertTrue(historyNavItem.waitForExistence(timeout: 4), app.debugDescription)
        historyNavItem.click()

        XCTAssertTrue(elementExists(id: "appShell.history", timeout: 4), app.debugDescription)
        XCTAssertTrue(elementExists(id: "history.root", timeout: 2), app.debugDescription)
        XCTAssertEqual(historyNavItem.value as? String, "Selected")
    }

    private func openAppShellInsights() {
        let openFoilButton = button(id: "menu.openFoilButton", fallbackLabel: "Open Foil")
        XCTAssertTrue(openFoilButton.waitForExistence(timeout: 2), app.debugDescription)
        openFoilButton.click()

        let insightsNavItem = app.descendants(matching: .any)["appShell.nav.insights"]
        XCTAssertTrue(insightsNavItem.waitForExistence(timeout: 4), app.debugDescription)
        insightsNavItem.click()

        XCTAssertTrue(elementExists(id: "appShell.insights", timeout: 4), app.debugDescription)
        XCTAssertEqual(insightsNavItem.value as? String, "Selected")
    }

    private func openAppShellHome() {
        let openFoilButton = button(id: "menu.openFoilButton", fallbackLabel: "Open Foil")
        XCTAssertTrue(openFoilButton.waitForExistence(timeout: 2), app.debugDescription)
        openFoilButton.click()

        XCTAssertTrue(elementExists(id: "appShell.root", timeout: 4), app.debugDescription)
        XCTAssertTrue(elementExists(id: "appShell.home", timeout: 2), app.debugDescription)
    }

    private func openAppShellCleanupSettings() {
        openAppShellSettings(navID: "appShell.nav.settings.cleanup")
    }

    private func openAppShellSettings(navID: String) {
        closeWindowIfPresent(named: "History")
        setPendingAppShellSelection(navID: navID)

        let openFoilButton = button(id: "menu.openFoilButton", fallbackLabel: "Open Foil")
        if openFoilButton.waitForExistence(timeout: 2) {
            openFoilButton.click()
        }

        let navItem = app.descendants(matching: .any)[navID]
        if !navItem.waitForExistence(timeout: 4) {
            activateAppForInteraction()
        }
        XCTAssertTrue(navItem.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(selectAppShellSettingsPane(navID: navID, timeout: 5), app.debugDescription)
        XCTAssertFalse(app.windows["Settings"].exists, app.debugDescription)
    }

    private func closeWindowIfPresent(named title: String) {
        let window = app.windows[title]
        guard window.exists else { return }

        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        if closeButton.exists {
            clickElement(closeButton)
        } else {
            window.typeKey("w", modifierFlags: .command)
        }
        XCTAssertFalse(window.waitForExistence(timeout: 2), app.debugDescription)
    }

    private func settingsNavIDForLaunchArguments() -> String {
        let arguments = app.launchArguments
        if arguments.contains("--settings-tab-general") { return "appShell.nav.settings.general" }
        if arguments.contains("--settings-tab-recording") { return "appShell.nav.settings.recording" }
        if arguments.contains("--settings-tab-cleanup") { return "appShell.nav.settings.cleanup" }
        if arguments.contains("--settings-tab-paste") { return "appShell.nav.settings.paste" }
        if arguments.contains("--settings-tab-privacy") { return "appShell.nav.settings.storage" }
        if arguments.contains("--settings-tab-whats-new") { return "appShell.nav.settings.whatsNew" }
        if arguments.contains("--settings-tab-experimental") || arguments.contains("--settings-tab-advanced") {
            return "appShell.nav.settings.experimental"
        }
        return "appShell.nav.settings.transcription"
    }

    private func setPendingAppShellSelection(navID: String) {
        guard let section = appShellSectionRawValue(for: navID) else { return }
        for domain in appShellSelectionDefaultsDomains {
            runQuietProcess("/usr/bin/defaults", arguments: [
                "write",
                domain,
                "FoilAppShell.pendingSelection",
                section
            ])
        }
    }

    private func clearPendingAppShellSelection() {
        for domain in appShellSelectionDefaultsDomains {
            runQuietProcess("/usr/bin/defaults", arguments: [
                "delete",
                domain,
                "FoilAppShell.pendingSelection"
            ])
        }
    }

    private var appShellSelectionDefaultsDomains: [String] {
        [
            "com.neonwatty.Foil",
            "com.neonwatty.Foil.Dev"
        ]
    }

    private func appShellSectionRawValue(for navID: String) -> String? {
        switch navID {
        case "appShell.nav.home":
            return "home"
        case "appShell.nav.insights":
            return "insights"
        case "appShell.nav.history":
            return "history"
        case "appShell.nav.settings.general":
            return "general"
        case "appShell.nav.settings.recording":
            return "recording"
        case "appShell.nav.settings.transcription":
            return "transcription"
        case "appShell.nav.settings.cleanup":
            return "cleanup"
        case "appShell.nav.settings.paste":
            return "paste"
        case "appShell.nav.settings.storage":
            return "storage"
        case "appShell.nav.settings.whatsNew":
            return "whatsNew"
        case "appShell.nav.settings.experimental":
            return "experimental"
        default:
            return nil
        }
    }

    private func selectAppShellHistoryVocabularyToken(_ token: String) {
        let tokenElement = app.descendants(matching: .any)["Select \(token) for Vocabulary"]
        XCTAssertTrue(tokenElement.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(tokenElement)
    }

    private func assertAppShellSettingsPane(navID: String, requiredID: String) {
        let navItem = app.descendants(matching: .any)[navID]
        XCTAssertTrue(navItem.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(
            selectAppShellSettingsPane(navID: navID, requiredID: requiredID, timeout: 5),
            app.debugDescription
        )
        XCTAssertFalse(app.windows["Settings"].exists, app.debugDescription)
    }

    private func selectAppShellSettingsPane(
        navID: String,
        requiredID: String? = nil,
        timeout: TimeInterval
    ) -> Bool {
        let navItem = app.descendants(matching: .any)[navID]
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if appShellSettingsPaneIsSelected(navItem: navItem, requiredID: requiredID) {
                return true
            }

            if navItem.exists {
                if navItem.isHittable {
                    navItem.click()
                } else {
                    clickElementDirectly(navItem)
                }
            } else {
                activateAppForInteraction()
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline

        return appShellSettingsPaneIsSelected(navItem: navItem, requiredID: requiredID)
    }

    private func appShellSettingsPaneIsSelected(navItem: XCUIElement, requiredID: String?) -> Bool {
        guard app.descendants(matching: .any)["appShell.preferences"].exists else {
            return false
        }
        let value = String(describing: navItem.value ?? "")
        guard value.contains("Selected") else {
            return false
        }
        guard let requiredID else {
            return true
        }
        return app.descendants(matching: .any)[requiredID].exists
    }

    private func openHistoryWindow() {
        postUITestCommand(openHistoryNotification)
    }

    private func postUITestCommand(_ notification: Notification.Name) {
        postUITestCommand(notification, userInfo: nil)
    }

    private func postUITestCommand(_ notification: Notification.Name, userInfo: [String: Any]?) {
        if notification == historyCommandNotification
            || notification == onboardingCommandNotification
            || notification == appCommandNotification {
            postUITestCommandToFile(notification, userInfo: userInfo)
            return
        }
        DistributedNotificationCenter.default().postNotificationName(
            notification,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func postUITestCommandToFile(_ notification: Notification.Name, userInfo: [String: Any]?) {
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "notification": notification.rawValue,
            "userInfo": userInfo ?? [:]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            XCTFail("Failed to serialize UI-test command \(notification.rawValue)")
            return
        }
        do {
            try data.write(to: commandInboxURL, options: .atomic)
        } catch {
            XCTFail("Failed to write UI-test command \(notification.rawValue): \(error)")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func removeUITestStateSnapshot() {
        try? FileManager.default.removeItem(at: stateSnapshotURL)
    }

    private func removeUITestCommandInbox() {
        try? FileManager.default.removeItem(at: commandInboxURL)
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
        elementExists(id: "appShell.preferences", timeout: timeout)
            && !app.windows["Settings"].exists
    }

    private func button(id: String, fallbackLabel: String) -> XCUIElement {
        if id.hasPrefix("menu."), uiTestControlCenterHost.exists {
            let scope = app.windows["Foil UI Test"].exists ? app.windows["Foil UI Test"] : uiTestControlCenterHost
            let identified = scope.descendants(matching: .button)[id]
            if identified.exists {
                return identified
            }
            let genericIdentified = scope.descendants(matching: .any)[id]
            if genericIdentified.exists {
                return genericIdentified
            }
            return scope.descendants(matching: .button)[fallbackLabel]
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
        dismissSystemSetupAssistant()
        activateAppForInteraction()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        if element.isHittable {
            element.click()
            return
        }

        let deadline = Date().addingTimeInterval(3)
        repeat {
            activateAppForInteraction()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            if element.isHittable {
                element.click()
                return
            }
        } while Date() < deadline

        if element.isHittable {
            element.click()
        } else {
            clickElementDirectly(element)
        }
    }

    private func clickElement(atNormalizedOffset offset: CGVector, in element: XCUIElement) {
        let frame = element.frame
        guard frame.isFiniteAndNonEmpty else {
            element.coordinate(withNormalizedOffset: offset).click()
            return
        }
        clickDirectly(at: CGPoint(
            x: frame.minX + (frame.width * offset.dx),
            y: frame.minY + (frame.height * offset.dy)
        ))
    }

    private func clickElementDirectly(_ element: XCUIElement) {
        let frame = element.frame
        guard frame.isFiniteAndNonEmpty else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            return
        }
        clickDirectly(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    private func clickDirectly(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        mouseUp?.post(tap: .cghidEventTap)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
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

    private func assertDefaultCleanupGroupStatusVisible(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            staticTextLabelOrValueContaining("Default cleanup group").waitForExistence(timeout: 4),
            app.debugDescription,
            file: file,
            line: line
        )
        XCTAssertTrue(
            staticTextLabelOrValueContaining("Default for unassigned apps").waitForExistence(timeout: 2),
            app.debugDescription,
            file: file,
            line: line
        )
        XCTAssertTrue(
            staticTextLabelOrValueContaining("Unassigned apps paste raw transcripts").waitForExistence(timeout: 2),
            app.debugDescription,
            file: file,
            line: line
        )
    }

    private func staticTextLabelOrValueContaining(_ text: String, in root: XCUIElement? = nil) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        return (root ?? app).staticTexts.matching(predicate).firstMatch
    }

    private func elementLabelOrValueContains(_ element: XCUIElement, _ text: String) -> Bool {
        let label = String(describing: element.label)
        let value = String(describing: element.value ?? "")
        return label.contains(text) || value.contains(text)
    }

    private func waitForElementLabelOrValue(
        _ element: XCUIElement,
        containing text: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && elementLabelOrValueContains(element, text) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return element.exists && elementLabelOrValueContains(element, text)
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        clickElement(element)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        chooseEditMenuItem("Select All")
        chooseEditMenuItem("Paste")
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let pastedValue = String(describing: element.value ?? "")
        if pastedValue.contains(String(text.prefix(16))) {
            return
        }

        typeKeyDirectly(0, flags: .maskCommand)
        typeKeyDirectly(51)
        element.typeText(text)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    private func chooseEditMenuItem(_ title: String) {
        let editMenu = app.menuBars.menuBarItems["Edit"]
        XCTAssertTrue(editMenu.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(editMenu)
        let item = app.menuItems[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(item)
    }

    private func typeKeyDirectly(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        keyUp?.post(tap: .cghidEventTap)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
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

    private var cleanupGroupModePicker: XCUIElement {
        cleanupPopUpButton(
            id: "settings.cleanupGroups.modePicker",
            valueOptions: ["Raw transcript", "Cleanup profile"]
        )
    }

    private var cleanupGroupProviderPicker: XCUIElement {
        cleanupPopUpButton(
            id: "settings.cleanupGroups.providerPicker",
            valueOptions: ["Groq", "OpenAI", "Custom", "None"]
        )
    }

    private func cleanupGroupGroqModelPickerValueContains(_ text: String) -> Bool {
        let picker = cleanupPopUpButton(
            id: "settings.cleanupGroups.groqModelPicker",
            valueOptions: ["Llama 3.1 8B Instant", "Llama 3.3 70B Versatile"]
        )
        return elementValueContains(picker, text)
    }

    private func cleanupGroupOpenAIModelPickerValueContains(_ text: String) -> Bool {
        let picker = cleanupPopUpButton(
            id: "settings.cleanupGroups.openAIModelPicker",
            valueOptions: ["GPT-5.4 mini", "GPT-5.4", "GPT-5.5"]
        )
        return elementValueContains(picker, text)
    }

    private func cleanupGroupModePickerValueContains(_ text: String) -> Bool {
        elementValueContains(cleanupGroupModePicker, text)
    }

    private func waitForCleanupGroupModePickerValueContaining(_ text: String, timeout: TimeInterval = 4) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if cleanupGroupModePickerValueContains(text) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return cleanupGroupModePickerValueContains(text)
    }

    private func elementValueContains(_ element: XCUIElement, _ text: String) -> Bool {
        let value = String(describing: element.value ?? "")
        return value.contains(text) || app.staticTexts[text].exists || app.descendants(matching: .any)[text].exists
    }

    private func cleanupPopUpButton(id: String, valueOptions: [String]) -> XCUIElement {
        if app.popUpButtons[id].exists {
            return app.popUpButtons[id]
        }
        let identified = app.descendants(matching: .any)[id]
        if identified.exists {
            return identified
        }
        for option in valueOptions {
            let predicate = NSPredicate(format: "value CONTAINS %@", option)
            let matchingPicker = app.popUpButtons.matching(predicate).firstMatch
            if matchingPicker.exists {
                return matchingPicker
            }
        }
        return app.popUpButtons[id]
    }

    private func cleanupPromptEditorValueContains(_ text: String) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", text, text)
        let matchingEditor = app.textViews.matching(predicate).firstMatch
        if matchingEditor.exists {
            return true
        }

        let editor = cleanupPromptEditor
        guard editor.waitForExistence(timeout: 4) else { return false }
        let value = String(describing: editor.value ?? "")
        let label = String(describing: editor.label)
        return value.contains(text) || label.contains(text)
    }

    private func waitForCleanupPromptEditorValueContaining(_ text: String, timeout: TimeInterval = 4) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if cleanupPromptEditorValueContains(text) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return cleanupPromptEditorValueContains(text)
    }

    private var cleanupPromptEditor: XCUIElement {
        if app.textViews["settings.cleanupGroups.promptEditor"].exists {
            return app.textViews["settings.cleanupGroups.promptEditor"]
        }
        let promptPredicate = NSPredicate(
            format: "value CONTAINS %@ OR label CONTAINS %@",
            "Clean up the transcript",
            "Clean up the transcript"
        )
        let promptEditor = app.textViews.matching(promptPredicate).firstMatch
        if promptEditor.exists {
            return promptEditor
        }
        return app.descendants(matching: .any)["settings.cleanupGroups.promptEditor"]
    }

    private var cleanupGroupResetPromptButton: XCUIElement {
        if app.buttons["settings.cleanupGroups.resetPromptButton"].exists {
            return app.buttons["settings.cleanupGroups.resetPromptButton"]
        }
        return app.buttons["Reset"].firstMatch
    }

    private func selectActiveCleanupMode(_ name: String) {
        let mode = name == "Cleanup profile" ? "cleanUp" : "raw"
        postUITestCommand(appCommandNotification, userInfo: [
            "command": "setDefaultCleanupMode",
            "mode": mode
        ])
        XCTAssertTrue(waitForCleanupGroupModePickerValueContaining(name), app.debugDescription)
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
            clickElement(sheetsButton)
            return
        }

        let dialogsButton = app.dialogs.firstMatch.buttons[title]
        if dialogsButton.waitForExistence(timeout: 1) {
            clickElement(dialogsButton)
            return
        }

        let button = app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 2), app.debugDescription)
        clickElement(button)
    }

    private func relaunchWithSeededHistory() {
        relaunchWithArguments([
            "--ui-testing",
            "--reset-defaults",
            "--seed-history"
        ])
    }

    private func relaunchWithArguments(_ arguments: [String]) {
        launchApp(arguments: arguments)
    }

    private func installSystemInterruptionMonitor() {
        addUIInterruptionMonitor(withDescription: "Dismiss Setup Assistant") { interruption in
            let labels = [
                "Allow",
                "Continue",
                "Not Now",
                "Set Up Later",
                "Skip",
                "Cancel",
                "Done",
                "OK"
            ]
            for label in labels {
                let button = interruption.buttons[label].firstMatch
                if button.exists {
                    if label == "Allow" {
                        button.click()
                    } else {
                        self.clickElementDirectly(button)
                    }
                    return true
                }
            }
            return false
        }
    }

    private func triggerSystemInterruptionMonitor() {
        activateAppForInteraction()
        if app.windows.firstMatch.exists {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    private func liveMicrophoneEnvironment(resultPath: String) -> [String: String] {
        var environment = ["LIVE_MICROPHONE_RESULT_PATH": resultPath]
        if let signingIdentity = ProcessInfo.processInfo.environment["LIVE_MICROPHONE_SIGNING_IDENTITY"] {
            environment["LIVE_MICROPHONE_SIGNING_IDENTITY"] = signingIdentity
        }
        if let inputRoute = ProcessInfo.processInfo.environment["LIVE_MICROPHONE_INPUT_ROUTE"] {
            environment["LIVE_MICROPHONE_INPUT_ROUTE"] = inputRoute
        }
        if let duration = ProcessInfo.processInfo.environment["LIVE_MICROPHONE_DURATION_SECONDS"] {
            environment["LIVE_MICROPHONE_DURATION_SECONDS"] = duration
        }
        if let appleVoiceText = ProcessInfo.processInfo.environment["LIVE_MICROPHONE_APPLE_VOICE_TEXT"] {
            environment["LIVE_MICROPHONE_APPLE_VOICE_TEXT"] = appleVoiceText
        }
        if let screenshotDir = ProcessInfo.processInfo.environment["LIVE_MICROPHONE_SCREENSHOT_DIR"] {
            environment["LIVE_MICROPHONE_SCREENSHOT_DIR"] = screenshotDir
        }
        return environment
    }

    private func liveMicrophoneScreenshotPath(resultPath: String, variant: String) -> URL? {
        guard let screenshotDir = ProcessInfo.processInfo.environment["LIVE_MICROPHONE_SCREENSHOT_DIR"],
              !screenshotDir.isEmpty else {
            return nil
        }
        let directory = URL(fileURLWithPath: screenshotDir, isDirectory: true)
        let resultName = URL(fileURLWithPath: resultPath).deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent("\(resultName)-\(variant).png")
    }

    private func waitForLiveMicrophoneResult(
        at path: String,
        timeout: TimeInterval,
        matching predicate: (String) -> Bool
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var result = ""
        while Date() < deadline {
            result = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            if predicate(result) {
                break
            }
            if result.contains("status=permission_requested") {
                triggerSystemInterruptionMonitor()
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return result
    }

    private func assertLiveMicrophoneRecordingUX(result: String) {
        XCTAssertTrue(result.contains("recording_started=true"), "Live microphone receipt did not mark recording started:\n\(result)")
        XCTAssertTrue(result.contains("recording_stopped=false"), "Live microphone receipt skipped the active recording phase:\n\(result)")
        XCTAssertTrue(waitForSessionTitle("Recording", timeout: 3), app.debugDescription)

        XCTAssertTrue(
            staticTextLabelOrValueContaining("Release Right Command").waitForExistence(timeout: 2),
            "Recording detail should tell the user how to finish recording."
        )

        let startButton = app.buttons["menu.recording.startButton"]
        let stopButton = app.buttons["menu.recording.stopButton"]
        let cancelButton = app.buttons["menu.recording.cancelButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(stopButton.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(startButton.isEnabled, "Start should be disabled while recording.")
        XCTAssertTrue(stopButton.isEnabled, "Stop should be enabled while recording.")
        XCTAssertTrue(cancelButton.isEnabled, "Cancel should be enabled while recording.")
        XCTAssertEqual(cancelButton.label, "Cancel recording")

        let floatingWindow = app.descendants(matching: .any)["floatingStatus.window"]
        XCTAssertTrue(floatingWindow.waitForExistence(timeout: 3), app.debugDescription)
        let liveFeedback = app.descendants(matching: .any)["liveFeedback.hud"]
        XCTAssertTrue(liveFeedback.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(staticTextLabelOrValueContaining("Recording", in: liveFeedback).exists, app.debugDescription)
    }

    private func assertLiveMicrophoneReadyUX() {
        XCTAssertTrue(waitForSessionTitle("Ready", timeout: 3), app.debugDescription)
        XCTAssertFalse(
            staticTextLabelOrValueContaining("Recording...").exists,
            "Recording feedback should clear after the live microphone smoke finishes."
        )

        let startButton = app.buttons["menu.recording.startButton"]
        let stopButton = app.buttons["menu.recording.stopButton"]
        let cancelButton = app.buttons["menu.recording.cancelButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(stopButton.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(startButton.isEnabled, "Start should be enabled when the live smoke returns to Ready.")
        XCTAssertFalse(stopButton.isEnabled, "Stop should be disabled when the live smoke returns to Ready.")
        XCTAssertFalse(cancelButton.isEnabled, "Cancel should be disabled when the live smoke returns to Ready.")
    }

    private func writeLiveMicrophoneScreenshotIfRequested(to url: URL?) {
        guard let url else { return }
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Live microphone UI"
        attachment.lifetime = .keepAlways
        add(attachment)

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: url)
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("foil-live-microphone-screenshots", isDirectory: true)
                .appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(
                    at: fallbackURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try screenshot.pngRepresentation.write(to: fallbackURL)
                print("Saved live microphone screenshot to fallback path \(fallbackURL.path) after \(url.path) failed: \(error)")
            } catch {
                print("Failed to write live microphone screenshot to \(url.path) or \(fallbackURL.path): \(error)")
            }
        }
    }

    private func writeSettingsScreenshotIfRequested(name: String) {
        let screenshot = screenshot(preferredElements: [
            app.windows["Foil"],
            app.descendants(matching: .any)["appShell.root"],
            app.descendants(matching: .any)["appShell.preferences"],
            app.descendants(matching: .any)["settings.root"]
        ])
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Settings \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func writeHistoryTransformScreenshot(name: String) {
        let screenshot = screenshot(preferredElements: [
            app.windows["Foil"],
            app.descendants(matching: .any)["appShell.root"],
            app.descendants(matching: .any)["history.root"]
        ])
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "History transform \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let screenshotDir = ProcessInfo.processInfo.environment["HISTORY_TRANSFORM_SCREENSHOT_DIR"]
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "/tmp/foil-history-transform-screenshots"

        let url = URL(fileURLWithPath: screenshotDir, isDirectory: true)
            .appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: url)
            print("Saved history transform screenshot to \(url.path)")
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("foil-history-transform-screenshots", isDirectory: true)
                .appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(
                    at: fallbackURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try screenshot.pngRepresentation.write(to: fallbackURL)
                print("Saved history transform screenshot to fallback path \(fallbackURL.path) after \(url.path) failed: \(error)")
            } catch {
                print("Failed to write history transform screenshot to \(url.path) or \(fallbackURL.path): \(error)")
            }
        }
    }

    private func writeActiveModeScreenshot(name: String) {
        let screenshot = screenshot(preferredElements: activeModeScreenshotTargets(for: name))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Cleanup profile \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let screenshotDir = ProcessInfo.processInfo.environment["ACTIVE_MODE_SCREENSHOT_DIR"]
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "/tmp/foil-active-mode-screenshots"

        let url = URL(fileURLWithPath: screenshotDir, isDirectory: true)
            .appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: url)
            print("Saved active mode screenshot to \(url.path)")
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("foil-active-mode-screenshots", isDirectory: true)
                .appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(
                    at: fallbackURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try screenshot.pngRepresentation.write(to: fallbackURL)
                print("Saved active mode screenshot to fallback path \(fallbackURL.path) after \(url.path) failed: \(error)")
            } catch {
                print("Failed to write active mode screenshot to \(url.path) or \(fallbackURL.path): \(error)")
            }
        }
    }

    private func activeModeScreenshotTargets(for name: String) -> [XCUIElement] {
        if name.hasPrefix("selector") {
            return [
                app.windows["Foil"],
                app.descendants(matching: .any)["appShell.root"],
                app.descendants(matching: .any)["appShell.preferences"],
                app.descendants(matching: .any)["settings.root"],
                cleanupGroupModePicker
            ]
        }
        return [
            app.windows["Foil UI Test"],
            app.descendants(matching: .any)["uiTest.controlCenter"]
        ]
    }

    private func screenshot(preferredElements: [XCUIElement]) -> XCUIScreenshot {
        for element in preferredElements where element.exists && element.frame.isFiniteAndNonEmpty {
            return element.screenshot()
        }
        return app.screenshot()
    }

    private func liveMicrophoneFloatValue(named name: String, in result: String) -> Float {
        let prefix = "\(name)="
        guard let line = result.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
            return 0
        }
        return Float(line.dropFirst(prefix.count)) ?? 0
    }
}

private extension CGRect {
    var isFiniteAndNonEmpty: Bool {
        width.isFinite && height.isFinite && minX.isFinite && minY.isFinite && !isEmpty && !isNull
    }
}

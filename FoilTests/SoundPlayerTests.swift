import XCTest
@testable import Foil

final class SoundPlayerTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SoundPlayerTests"

    override func setUpWithError() throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testStartSoundUsesAppOwnedRecordingStartCueWhenEnabledByDefault() {
        var requestedNames: [String] = []
        let player = SoundPlayer(defaults: defaults, playCueNamed: { name in
            requestedNames.append(name)
        })

        player.playStartSound()

        XCTAssertEqual(requestedNames, ["recordingStart"])
    }

    func testStartSoundDoesNotPlayWhenSoundEffectsAreDisabled() {
        defaults.set(false, forKey: "soundEffectsEnabled")
        var requestedNames: [String] = []
        let player = SoundPlayer(defaults: defaults, playCueNamed: { name in
            requestedNames.append(name)
        })

        player.playStartSound()

        XCTAssertTrue(requestedNames.isEmpty)
    }

    func testStopSoundUsesSystemPopCueWhenEnabledByDefault() {
        var requestedNames: [String] = []
        let player = SoundPlayer(defaults: defaults, playSystemSoundNamed: { name in
            requestedNames.append(name)
        })

        player.playStopSound()

        XCTAssertEqual(requestedNames, ["Pop"])
    }

    func testStopSoundDoesNotPlayWhenSoundEffectsAreDisabled() {
        defaults.set(false, forKey: "soundEffectsEnabled")
        var requestedNames: [String] = []
        let player = SoundPlayer(defaults: defaults, playSystemSoundNamed: { name in
            requestedNames.append(name)
        })

        player.playStopSound()

        XCTAssertTrue(requestedNames.isEmpty)
    }

    func testStartSoundCanBeDisabledIndependently() {
        defaults.set(RecordingSoundCue.none.rawValue, forKey: "recordingStartSoundCue")
        var appCueNames: [String] = []
        var systemCueNames: [String] = []
        let player = SoundPlayer(
            defaults: defaults,
            playCueNamed: { appCueNames.append($0) },
            playSystemSoundNamed: { systemCueNames.append($0) }
        )

        player.playStartSound()
        player.playStopSound()

        XCTAssertTrue(appCueNames.isEmpty)
        XCTAssertEqual(systemCueNames, ["Pop"])
    }

    func testStopSoundCanBeDisabledIndependently() {
        defaults.set(RecordingSoundCue.none.rawValue, forKey: "recordingEndSoundCue")
        var appCueNames: [String] = []
        var systemCueNames: [String] = []
        let player = SoundPlayer(
            defaults: defaults,
            playCueNamed: { appCueNames.append($0) },
            playSystemSoundNamed: { systemCueNames.append($0) }
        )

        player.playStartSound()
        player.playStopSound()

        XCTAssertEqual(appCueNames, ["recordingStart"])
        XCTAssertTrue(systemCueNames.isEmpty)
    }

    func testStartAndStopCanUseSeparateSelectedCues() {
        defaults.set(RecordingSoundCue.recordingStop.rawValue, forKey: "recordingStartSoundCue")
        defaults.set(RecordingSoundCue.softChime.rawValue, forKey: "recordingEndSoundCue")
        var appCueNames: [String] = []
        var systemCueNames: [String] = []
        let player = SoundPlayer(
            defaults: defaults,
            playCueNamed: { appCueNames.append($0) },
            playSystemSoundNamed: { systemCueNames.append($0) }
        )

        player.playStartSound()
        player.playStopSound()

        XCTAssertEqual(systemCueNames, ["Pop"])
        XCTAssertEqual(appCueNames, ["softChime"])
    }

    func testGlobalSoundEffectsToggleOverridesSelectedStartAndEndCues() {
        defaults.set(false, forKey: "soundEffectsEnabled")
        defaults.set(RecordingSoundCue.softChime.rawValue, forKey: "recordingStartSoundCue")
        defaults.set(RecordingSoundCue.recordingStart.rawValue, forKey: "recordingEndSoundCue")
        var appCueNames: [String] = []
        let player = SoundPlayer(defaults: defaults, playCueNamed: { appCueNames.append($0) })

        player.playStartSound()
        player.playStopSound()
        player.preview(.softChime)

        XCTAssertTrue(appCueNames.isEmpty)
    }
}

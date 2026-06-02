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

    func testStartSoundUsesBottleCueWhenEnabledByDefault() {
        var systemCueNames: [String] = []
        let player = SoundPlayer(
            defaults: defaults,
            playSystemSoundNamed: { systemCueNames.append($0) }
        )

        player.playStartSound()

        XCTAssertEqual(systemCueNames, ["Bottle"])
    }

    func testStartSoundDoesNotPlayWhenSoundEffectsAreDisabled() {
        defaults.set(false, forKey: "soundEffectsEnabled")
        var requestedNames: [String] = []
        let player = SoundPlayer(defaults: defaults, playSystemSoundNamed: { name in
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
        var systemCueNames: [String] = []
        let player = SoundPlayer(
            defaults: defaults,
            playSystemSoundNamed: { systemCueNames.append($0) }
        )

        player.playStartSound()
        player.playStopSound()

        XCTAssertEqual(systemCueNames, ["Pop"])
    }

    func testStopSoundCanBeDisabledIndependently() {
        defaults.set(RecordingSoundCue.none.rawValue, forKey: "recordingEndSoundCue")
        var systemCueNames: [String] = []
        let player = SoundPlayer(
            defaults: defaults,
            playSystemSoundNamed: { systemCueNames.append($0) }
        )

        player.playStartSound()
        player.playStopSound()

        XCTAssertEqual(systemCueNames, ["Bottle"])
    }

    func testStartAndStopCanUseSeparateSelectedCues() {
        defaults.set(RecordingSoundCue.ping.rawValue, forKey: "recordingStartSoundCue")
        defaults.set(RecordingSoundCue.glass.rawValue, forKey: "recordingEndSoundCue")
        var systemCueNames: [String] = []
        let player = SoundPlayer(
            defaults: defaults,
            playSystemSoundNamed: { systemCueNames.append($0) }
        )

        player.playStartSound()
        player.playStopSound()

        XCTAssertEqual(systemCueNames, ["Ping", "Glass"])
    }

    func testAllBuiltInSystemSoundCuesMapToAvailableSystemSoundFiles() {
        for cue in RecordingSoundCue.allCases where cue != .none {
            let soundName = try! XCTUnwrap(cue.systemSoundName)
            let soundURL = URL(fileURLWithPath: "/System/Library/Sounds")
                .appendingPathComponent("\(soundName).aiff")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: soundURL.path),
                "\(soundName) should be available as a built-in macOS system sound"
            )
        }
    }

    func testGlobalSoundEffectsToggleOverridesSelectedStartAndEndCues() {
        defaults.set(false, forKey: "soundEffectsEnabled")
        defaults.set(RecordingSoundCue.glass.rawValue, forKey: "recordingStartSoundCue")
        defaults.set(RecordingSoundCue.tink.rawValue, forKey: "recordingEndSoundCue")
        var systemCueNames: [String] = []
        let player = SoundPlayer(defaults: defaults, playSystemSoundNamed: { systemCueNames.append($0) })

        player.playStartSound()
        player.playStopSound()
        player.preview(.pop)

        XCTAssertTrue(systemCueNames.isEmpty)
    }
}

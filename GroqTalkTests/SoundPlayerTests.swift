import XCTest
@testable import GroqTalk

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
}

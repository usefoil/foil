import XCTest
@testable import Foil

#if DEBUG
@MainActor
final class AudioUXSnapshotRendererTests: XCTestCase {
    func testLiveAudioLevelScaleBoostsNormalLevelsWithoutChangingEndpoints() {
        XCTAssertEqual(LiveAudioLevelScale.visualLevel(for: 0), 0, accuracy: 0.001)
        XCTAssertEqual(LiveAudioLevelScale.visualLevel(for: 1), 1, accuracy: 0.001)

        XCTAssertEqual(LiveAudioLevelScale.visualLevel(for: 0.02), 0.303, accuracy: 0.001)
        XCTAssertEqual(LiveAudioLevelScale.visualLevel(for: 0.05), 0.452, accuracy: 0.001)
        XCTAssertEqual(LiveAudioLevelScale.visualLevel(for: 0.10), 0.574, accuracy: 0.001)
        XCTAssertEqual(LiveAudioLevelScale.visualLevel(for: 0.25), 0.741, accuracy: 0.001)
    }

    func testLiveAudioLevelScalePreservesDynamicRangeAndBoundsInvalidInputs() {
        let quiet = LiveAudioLevelScale.visualLevel(for: 0.02)
        let normal = LiveAudioLevelScale.visualLevel(for: 0.05)
        let moderate = LiveAudioLevelScale.visualLevel(for: 0.10)
        let loud = LiveAudioLevelScale.visualLevel(for: 0.25)
        let veryLoud = LiveAudioLevelScale.visualLevel(for: 0.70)

        XCTAssertGreaterThan(quiet, 0.30)
        XCTAssertGreaterThan(normal, quiet)
        XCTAssertGreaterThan(moderate, normal)
        XCTAssertGreaterThan(loud, moderate)
        XCTAssertGreaterThan(veryLoud, loud)
        XCTAssertLessThan(loud, 0.90)
        XCTAssertLessThan(veryLoud, 0.95)

        XCTAssertEqual(LiveAudioLevelScale.visualLevel(for: -0.50), 0, accuracy: 0.001)
        XCTAssertEqual(LiveAudioLevelScale.visualLevel(for: 2), 1, accuracy: 0.001)
        XCTAssertEqual(LiveAudioLevelScale.visualLevel(for: .nan), 0, accuracy: 0.001)
    }

    func testLaunchRequestAcceptsSeparateOutputArgument() {
        let request = AudioUXSnapshotRenderer.launchRequest(arguments: [
            "Foil",
            AudioUXSnapshotRenderer.renderFlag,
            AudioUXSnapshotRenderer.outputFlag,
            "/tmp/foil-audio-ux-snapshots"
        ])

        XCTAssertEqual(request?.outputDirectory.path, "/tmp/foil-audio-ux-snapshots")
    }

    func testLaunchRequestAcceptsEqualsOutputArgument() {
        let request = AudioUXSnapshotRenderer.launchRequest(arguments: [
            "Foil",
            AudioUXSnapshotRenderer.renderFlag,
            "\(AudioUXSnapshotRenderer.outputFlag)=/tmp/foil-audio-ux-snapshots"
        ])

        XCTAssertEqual(request?.outputDirectory.path, "/tmp/foil-audio-ux-snapshots")
    }

    func testSnapshotMatrixCoversRequiredAudioUXStatesAndViews() {
        XCTAssertEqual(AudioUXSnapshotRenderer.Scenario.allCases.map(\.rawValue), [
            "idle",
            "recording",
            "processing",
            "success",
            "warning",
            "error"
        ])
        XCTAssertEqual(AudioUXSnapshotRenderer.SnapshotViewKind.allCases.map(\.rawValue), [
            "signifier",
            "floating-status"
        ])
    }
}
#endif

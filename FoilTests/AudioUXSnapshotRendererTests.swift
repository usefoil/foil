import XCTest
@testable import Foil

#if DEBUG
@MainActor
final class AudioUXSnapshotRendererTests: XCTestCase {
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

import XCTest
@testable import GroqTalk

@MainActor
final class RecordingStartCueSchedulerTests: XCTestCase {
    func testSchedulePlaysStartCueAfterDelayWhenRecordingStillActive() async throws {
        var isRecording = true
        var playCount = 0
        let scheduler = RecordingStartCueScheduler(
            delayNanoseconds: 1_000_000,
            isRecording: { isRecording },
            playStartSound: { playCount += 1 }
        )

        scheduler.schedule()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(playCount, 1)
    }

    func testScheduleDoesNotPlayStartCueWhenRecordingStopsBeforeDelay() async throws {
        var isRecording = true
        var playCount = 0
        let scheduler = RecordingStartCueScheduler(
            delayNanoseconds: 20_000_000,
            isRecording: { isRecording },
            playStartSound: { playCount += 1 }
        )

        scheduler.schedule()
        isRecording = false
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(playCount, 0)
    }
}

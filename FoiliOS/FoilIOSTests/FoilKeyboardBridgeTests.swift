import XCTest
@testable import FoilIOS

final class FoilKeyboardBridgeTests: XCTestCase {
    private var bridge: FoilKeyboardBridge!

    override func setUp() {
        super.setUp()
        bridge = FoilKeyboardBridge()
        bridge.reset()
    }

    override func tearDown() {
        bridge.reset()
        bridge = nil
        super.tearDown()
    }

    func testConsumeTranscriptForInsertionReturnsTranscriptOnceAndClearsSharedState() {
        bridge.complete(transcript: "Foil one shot insert", message: "Ready")

        XCTAssertEqual(bridge.consumeTranscriptForInsertion(), "Foil one shot insert")
        XCTAssertNil(bridge.consumeTranscriptForInsertion())

        let snapshot = bridge.load()
        XCTAssertEqual(snapshot.phase, .idle)
        XCTAssertNil(snapshot.transcript)
        XCTAssertEqual(bridge.storageReport().operation, "insert")
    }

    func testConsumeTranscriptForInsertionIgnoresEmptyTranscript() {
        bridge.complete(transcript: "   ", message: "Ready")

        XCTAssertNil(bridge.consumeTranscriptForInsertion())

        XCTAssertEqual(bridge.load().phase, .idle)
        XCTAssertEqual(bridge.storageReport().operation, "insert")
    }

    func testConsumeTranscriptForInsertionIgnoresNonCompleteLeftoverTranscripts() {
        let phases: [FoilKeyboardPhase] = [.idle, .handoffRequested, .listening, .processing, .failed]

        for phase in phases {
            bridge.save(
                FoilKeyboardSnapshot(
                    phase: phase,
                    transcript: "leftover transcript",
                    message: "Leftover \(phase.rawValue)",
                    updatedAt: Date()
                )
            )

            XCTAssertNil(bridge.consumeTranscriptForInsertion(), "Expected \(phase.rawValue) to be non-insertable.")
            XCTAssertEqual(bridge.load().phase, .idle)
            XCTAssertNil(bridge.load().transcript)
            XCTAssertEqual(bridge.storageReport().operation, "insert")
        }
    }

    func testInsertableTranscriptRequiresCompleteNonEmptyTranscript() {
        XCTAssertEqual(
            FoilKeyboardSnapshot(
                phase: .complete,
                transcript: "  ready to insert  ",
                message: "Ready",
                updatedAt: Date()
            ).insertableTranscript,
            "ready to insert"
        )

        XCTAssertNil(
            FoilKeyboardSnapshot(
                phase: .complete,
                transcript: "   ",
                message: "Ready",
                updatedAt: Date()
            ).insertableTranscript
        )

        XCTAssertNil(
            FoilKeyboardSnapshot(
                phase: .failed,
                transcript: "leftover transcript",
                message: "Failed",
                updatedAt: Date()
            ).insertableTranscript
        )
    }
}

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
}

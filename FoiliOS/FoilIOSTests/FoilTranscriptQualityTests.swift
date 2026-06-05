import XCTest
@testable import FoilIOS

final class FoilTranscriptQualityTests: XCTestCase {
    func testRejectsEmptyAndPunctuationOnlyTranscripts() {
        XCTAssertFalse(FoilTranscriptQuality.isAcceptable(""))
        XCTAssertFalse(FoilTranscriptQuality.isAcceptable("   \n\t"))
        XCTAssertFalse(FoilTranscriptQuality.isAcceptable("."))
        XCTAssertFalse(FoilTranscriptQuality.isAcceptable("...?!"))
        XCTAssertFalse(FoilTranscriptQuality.isAcceptable(" - "))
    }

    func testAcceptsShortRealSpeechTranscripts() {
        XCTAssertTrue(FoilTranscriptQuality.isAcceptable("OK"))
        XCTAssertTrue(FoilTranscriptQuality.isAcceptable("Number 3"))
        XCTAssertTrue(FoilTranscriptQuality.isAcceptable("Violet cactus number one"))
    }
}

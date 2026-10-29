import XCTest
@testable import Foil

final class ManagedLocalModelCatalogTests: XCTestCase {
    func testLanguageFilteringKeepsMultilingualDictationOffEnglishOnlyModels() throws {
        let catalog = try ManagedLocalModelCatalog.bundled()
        XCTAssertTrue(catalog.models(for: .unanswered).isEmpty)
        XCTAssertEqual(catalog.models(for: .englishOnly).count, 10)
        XCTAssertEqual(catalog.models(for: .multilingual).map(\.id),
                       ["tiny", "base", "small", "medium", "large-v3-turbo", "large-v3"])
        let large = try catalog.model("large-v3")
        XCTAssertGreaterThan(large.bytes, Int64(Int32.max), "Large downloads need 64-bit byte counts")
        XCTAssertEqual(large.sha256, "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2")
    }

    func testLanguageIntentDoesNotDefaultToEnglish() throws {
        let catalog = try ManagedLocalModelCatalog.bundled()
        XCTAssertNil(catalog.recommendation(for: .unanswered))
        XCTAssertEqual(catalog.recommendation(for: .englishOnly)?.id, "base.en")
        XCTAssertEqual(catalog.recommendation(for: .multilingual)?.id, "base")
        XCTAssertEqual(try catalog.model("base").downloadURL.absoluteString,
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin")
        XCTAssertThrowsError(try catalog.model("../base"))
    }
    func testBundledCatalogProvidesImmutableInstallableModels() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ManagedLocalModels", withExtension: "json"),
            "The production installer needs a bundled catalog for offline reconstruction")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["revision"] as? String, "5359861c739e955e79d9a303bcbc70fb988958b1")
        let models = try XCTUnwrap(object["models"] as? [[String: Any]])
        XCTAssertEqual(models.compactMap { $0["id"] as? String }, [
            "tiny.en", "tiny", "base.en", "base", "small.en", "small",
            "medium.en", "medium", "large-v3-turbo", "large-v3"
        ])
        XCTAssertEqual(models.compactMap { $0["bytes"] as? Int }, [
            77704715, 77691713, 147964211, 147951465, 487614201, 487601967,
            1533774781, 1533763059, 1624555275, 3095033483
        ])
    }
}

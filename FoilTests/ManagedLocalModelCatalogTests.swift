import XCTest
@testable import Foil

final class ManagedLocalModelCatalogTests: XCTestCase {
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
        XCTAssertEqual(models.compactMap { $0["id"] as? String }, ["base.en", "base"])
        XCTAssertEqual(models.compactMap { $0["bytes"] as? Int }, [147964211, 147951465])
    }
}

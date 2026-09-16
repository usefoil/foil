import Foundation

enum ManagedDictationLanguage: String, Codable, Sendable {
    case unanswered, englishOnly, multilingual
}

struct ManagedLocalModelCatalog: Sendable {
    struct Model: Codable, Equatable, Sendable {
        let id: String
        let filename: String
        let bytes: Int64
        let sha256: String
        var downloadURL: URL {
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/\(ManagedLocalModelCatalog.revision)/\(filename)")!
        }
    }
    static let revision = "5359861c739e955e79d9a303bcbc70fb988958b1"
    let models: [Model]

    static func bundled() throws -> Self {
        struct Document: Decodable { let revision: String; let models: [Model] }
        guard let url = Bundle.main.url(forResource: "ManagedLocalModels", withExtension: "json") else {
            throw ManagedLocalError.modelIntegrity
        }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard document.revision == revision, document.models.map(\.id) == ["base.en", "base"],
              document.models.allSatisfy({ model in
                  model.filename == "ggml-\(model.id).bin" && model.bytes > 0
                      && model.sha256.count == 64
                      && model.sha256.allSatisfy { "0123456789abcdef".contains($0) }
              }) else { throw ManagedLocalError.modelIntegrity }
        return Self(models: document.models)
    }

    func recommendation(for language: ManagedDictationLanguage) -> Model? {
        switch language {
        case .unanswered: nil
        case .englishOnly: try? model("base.en")
        case .multilingual: try? model("base")
        }
    }

    func model(_ id: String) throws -> Model {
        guard let model = models.first(where: { $0.id == id }) else { throw ManagedLocalError.modelIntegrity }
        return model
    }
}

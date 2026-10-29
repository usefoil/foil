import Foundation

@main struct Smoke {
    @MainActor static func main() async throws {
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let root = repository.appendingPathComponent(".research/model-switch-smoke/models")
        let json = try Data(contentsOf: repository.appendingPathComponent("Foil/Resources/ManagedLocalModels.json"))
        struct Document: Decodable { let models: [ManagedLocalModelCatalog.Model] }
        let catalog = ManagedLocalModelCatalog(models: try JSONDecoder().decode(Document.self, from: json).models)
        let runtime = ManagedLocalRuntime(helperURL: URL(fileURLWithPath: "/tmp/foil-model-switch-build/Build/Products/Debug/Foil.app/Contents/Helpers/whisper-server"))
        defer { runtime.stop() }
        let store = try ManagedLocalModelStore(root: root, catalog: catalog)
        let coordinator = ManagedLocalModelCoordinator(runtime: runtime, store: store)
        var results: [[String: String]] = []
        var oldID: UUID?
        for id in (ProcessInfo.processInfo.environment["FOIL_MODEL_SWITCH_SMOKE_MODELS"]?.components(separatedBy: ",") ?? ["tiny.en", "base.en", "tiny.en"]) {
            try await coordinator.installAndSelect(id)
            guard coordinator.activeID == id, coordinator.selectedID == id,
                  let session = runtime.session, session.id != oldID,
                  try await session.health() else { fatalError("Wrong or unready model after switch") }
            oldID = session.id
            let boundary = UUID().uuidString
            var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
            body.append(try Data(contentsOf: repository.appendingPathComponent("Foil/e2e-test-audio.wav")))
            body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n--\(boundary)--\r\n".utf8))
            let (data, response) = try await session.transcribe(body: body, contentType: "multipart/form-data; boundary=\(boundary)")
            let text = String(decoding: data, as: UTF8.self)
            guard (response as? HTTPURLResponse)?.statusCode == 200, text.lowercased().contains("quick brown fox") else { fatalError("Bad transcription: \(text)") }
            results.append(["model": id, "session": session.id.uuidString, "transcript": text])
            print("PASS model=\(id) healthy=true newSession=true transcript=\(text)")
        }
        let receipt = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try receipt.write(to: repository.appendingPathComponent(".research/model-switch-smoke/receipt.json"))
        print("PASS: production installer and owned runtime switched models and transcribed with each")
    }
}

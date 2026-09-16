import XCTest
@testable import Foil

@MainActor
final class ManagedLocalModelCoordinatorTests: XCTestCase {
    func testMissingOfflineSelectionFailsWithoutChangingDurableChoice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"installed":["base.en"],"selectedID":"base.en"}"#.utf8)
            .write(to: root.appendingPathComponent("inventory.json"))
        let coordinator = ManagedLocalModelCoordinator(runtime: ManagedLocalRuntime(), store: try ManagedLocalModelStore(root: root))
        do { try await coordinator.restore(); XCTFail("Missing model was restored") }
        catch { XCTAssertEqual(error as? ManagedLocalModelStore.Failure, .unavailable) }
        XCTAssertEqual(coordinator.selectedID, "base.en")
        XCTAssertNil(coordinator.activeID)
        if case .failed = coordinator.state {} else { XCTFail("Missing selection must expose actionable failure") }
        let inventory = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("inventory.json"))) as! [String: Any]
        XCTAssertEqual(inventory["selectedID"] as? String, "base.en")
    }

    func testFailedInstallKeepsExistingHealthyRuntimeAndProviderSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ManagedLocalRuntime()
        defer { runtime.stop() }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ggml-tiny.en", withExtension: "bin"))
        let model = try ManagedLocalModel.verify(url: url, id: "tiny.en", size: 77_704_715,
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f")
        let previous = try await runtime.start(model: model)
        let store = try ManagedLocalModelStore(root: root, capacity: { _ in 0 })
        let coordinator = ManagedLocalModelCoordinator(runtime: runtime, store: store)
        do { try await coordinator.installAndSelect("base"); XCTFail("No-space installation accepted") }
        catch { XCTAssertEqual(error as? ManagedLocalModelStore.Failure, .insufficientSpace) }
        XCTAssertEqual(runtime.session?.id, previous.id)
        let healthy = try await previous.health()
        XCTAssertTrue(healthy)
        XCTAssertNil(coordinator.selectedID)
        XCTAssertNil(coordinator.candidateID)
        if case .failed = coordinator.state {} else { XCTFail("Failed switch must remain visible beside active model") }
    }

    func testVerifiedFixtureRestoresHealthyActiveAndEnforcesRemovalEligibility() async throws {
        let (root, store) = try isolatedVerifiedFixtureStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ManagedLocalRuntime()
        defer { runtime.stop() }
        let coordinator = ManagedLocalModelCoordinator(runtime: runtime, store: store)

        try await coordinator.restore()
        XCTAssertEqual(coordinator.activeID, "base")
        let session = try XCTUnwrap(runtime.session)
        let healthy = try await session.health()
        XCTAssertTrue(healthy)
        await XCTAssertThrowsErrorAsync(try await coordinator.remove("base"))
        try await coordinator.remove("base.en")
        XCTAssertFalse(coordinator.installed.contains { $0.id == "base.en" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.installationURL(
            try store.catalog.model("base.en")).path))
    }

    private func isolatedVerifiedFixtureStore() throws -> (URL, ManagedLocalModelStore) {
        guard let fixture = ProcessInfo.processInfo.environment["FOIL_MANAGED_REVIEW_FIXTURE_ROOT"],
              !fixture.isEmpty else {
            throw XCTSkip("Non-live provisioned model review skipped: TEST_RUNNER_FOIL_MANAGED_REVIEW_FIXTURE_ROOT is absent")
        }
        let acceptanceFixtureRoot = URL(fileURLWithPath: fixture)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let catalog = try ManagedLocalModelCatalog.bundled()
        for id in ["base.en", "base"] {
            let entry = try catalog.model(id)
            let source = acceptanceFixtureRoot.appendingPathComponent(
                "5359861c739e955e79d9a303bcbc70fb988958b1-\(entry.sha256)-\(id).bin")
            _ = try ManagedLocalModel.verify(url: source, id: id, size: entry.bytes, sha256: entry.sha256)
            let destination = root.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            _ = try ManagedLocalModel.verify(url: destination, id: id, size: entry.bytes, sha256: entry.sha256)
        }
        try FileManager.default.copyItem(at: acceptanceFixtureRoot.appendingPathComponent("inventory.json"),
                                         to: root.appendingPathComponent("inventory.json"))
        return (root, try ManagedLocalModelStore(root: root))
    }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T,
                                          file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) }
    catch { }
}

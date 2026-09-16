import CryptoKit
import XCTest
@testable import Foil

final class ManagedLocalRuntimeTests: XCTestCase {
    func testCancelledHashingStopsBeforeAcceptingModel() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        let model = try ManagedLocalModel.verify(url: url, id: "fixture", size: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(try model.revalidate()) { error in XCTAssertTrue(error is CancellationError) }
        }.value
    }

    func testCorruptOrTruncatedModelCannotBeVerified() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        XCTAssertThrowsError(try ManagedLocalModel.verify(url: url, id: "fixture", size: 4,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        XCTAssertThrowsError(try ManagedLocalModel.verify(url: url, id: "fixture", size: 3,
            sha256: String(repeating: "0", count: 64)))
    }

    func testVerifiedModelDetectsReplacementBeforeLaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        let model = try ManagedLocalModel.verify(url: url, id: "fixture", size: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try Data("xyz".utf8).write(to: url)
        XCTAssertThrowsError(try model.revalidate())
    }

    func testForeignHealthCannotProveReadiness() throws {
        let id = UUID()
        let hash = String(repeating: "a", count: 64)
        let foreign = Data("{\"status\":\"ok\"}".utf8)
        XCTAssertFalse(ManagedLocalHealth.matches(foreign, session: id, modelSHA256: hash, pid: 123))
        let exact = try JSONSerialization.data(withJSONObject: ["status": "ok", "service": "foil-whisper",
            "session": id.uuidString, "model_sha256": hash, "pid": 123])
        XCTAssertTrue(ManagedLocalHealth.matches(exact, session: id, modelSHA256: hash, pid: 123))
        XCTAssertFalse(ManagedLocalHealth.matches(exact, session: UUID(), modelSHA256: hash, pid: 123))
        XCTAssertFalse(ManagedLocalHealth.matches(exact, session: id, modelSHA256: hash, pid: 124))
        XCTAssertFalse(ManagedLocalHealth.matches(exact, session: id, modelSHA256: String(repeating: "b", count: 64), pid: 123))
    }
}

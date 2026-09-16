import XCTest
@testable import Foil

final class ManagedLocalModelStoreTests: XCTestCase {
    func testInstallRepairsCorruptCatalogDestinationAndPreservesSelection() async throws {
        let root = root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = ManagedLocalModelCatalog.Model(
            id: "fixture",
            filename: "fixture.bin",
            bytes: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelDownloadFixture.self]
        ModelDownloadFixture.status = 200
        let store = try ManagedLocalModelStore(
            root: root,
            catalog: ManagedLocalModelCatalog(models: [entry]),
            capacity: { _ in 1_000_000_000 },
            configuration: configuration
        )
        let destination = store.installationURL(entry)
        try Data("abd".utf8).write(to: destination)
        try Data(#"{"installed":["fixture"],"selectedID":"fixture"}"#.utf8)
            .write(to: root.appendingPathComponent("inventory.json"))

        let before = try await store.reconstruct()
        XCTAssertTrue(before.installed.isEmpty)
        XCTAssertEqual(before.selectedID, "fixture")
        XCTAssertFalse(before.recovery.isEmpty)

        let repaired = try await store.install("fixture") { _ in }
        XCTAssertEqual(repaired.id, "fixture")
        XCTAssertEqual(try Data(contentsOf: destination), Data("abc".utf8))
        let after = try await store.reconstruct()
        XCTAssertEqual(after.installed.map(\.id), ["fixture"])
        XCTAssertEqual(after.selectedID, "fixture")
    }

    func testUnchangedInventoryCanBeReadWithoutDirectoryWritePermission() async throws {
        let root = root()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let store = try ManagedLocalModelStore(root: root)
        _ = try await store.reconstruct()
        let inventory = root.appendingPathComponent("inventory.json")
        let before = try Data(contentsOf: inventory)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        let snapshot = try await store.reconstruct()
        XCTAssertTrue(snapshot.installed.isEmpty)
        XCTAssertEqual(try Data(contentsOf: inventory), before)
    }

    func testSharedWritableDirectoryIsNotAnAppOwnedStore() async throws {
        let root = root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: root.path)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await ManagedLocalModelStore(root: root).reconstruct()
            XCTFail("Other users could replace model-store files")
        } catch { XCTAssertEqual(error as? ManagedLocalModelStore.Failure, .unsafeStorage) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testUnsuccessfulHTTPAndTruncatedBytesNeverBecomeInstalled() async throws {
        for status in [401, 200] {
            let root = root()
            defer { try? FileManager.default.removeItem(at: root) }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ModelDownloadFixture.self]
            ModelDownloadFixture.status = status
            let store = try ManagedLocalModelStore(root: root, capacity: { _ in 1_000_000_000 }, configuration: configuration)
            do {
                _ = try await store.install("base.en") { _ in }
                XCTFail("Rejected download was installed")
            } catch {
                XCTAssertEqual(error as? ManagedLocalModelStore.Failure, status == 401 ? .httpStatus : .integrity)
            }
            let snapshot = try await store.reconstruct()
            XCTAssertTrue(snapshot.installed.isEmpty)
            XCTAssertNil(snapshot.selectedID)
        }
    }

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("foil-model-test-\(UUID().uuidString)")
    }

    func testFreshStoreReconstructsEmptyInventoryWithoutNetwork() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedLocalModelStore(root: root)
        let snapshot = try await store.reconstruct()
        XCTAssertTrue(snapshot.installed.isEmpty)
        XCTAssertNil(snapshot.selectedID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("inventory.json").path))
    }

    func testUnknownAndInsufficientCapacityFailBeforeAnyNetworkOrPartialBytes() async throws {
        for capacity: Int64? in [nil, 1] {
            let root = root()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try ManagedLocalModelStore(root: root, capacity: { _ in capacity })
            do {
                _ = try await store.install("base.en") { _ in }
                XCTFail("Insufficient/unknown capacity accepted")
            } catch {
                XCTAssertEqual(error as? ManagedLocalModelStore.Failure,
                    capacity == nil ? .unknownCapacity : .insufficientSpace)
            }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty,
                "Preflight failure must not create a journal, partial, or inventory")
        }
    }

    func testMidStreamDiskFullPreservesSelectionAndNeverPromotesBytes() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChunkedModelDownloadFixture.self]
        let store = try ManagedLocalModelStore(root: root, capacity: { _ in 1_000_000_000 },
            configuration: configuration, writeChunk: { file, data in
                try file.write(contentsOf: data.prefix(3))
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
            })
        _ = try await store.reconstruct()
        let before = try Data(contentsOf: root.appendingPathComponent("inventory.json"))
        do { _ = try await store.install("base.en") { _ in }; XCTFail("Disk-full stream installed") }
        catch { XCTAssertEqual(error as? ManagedLocalModelStore.Failure, .insufficientSpace) }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("inventory.json")), before)
        let partial = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: root.path).first { $0.hasPrefix("partial-") })
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(partial)), Data("abc".utf8))
        let recovered = try await ManagedLocalModelStore(root: root).reconstruct()
        XCTAssertTrue(recovered.installed.isEmpty)
        XCTAssertFalse(recovered.recovery.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(partial).path))
    }

    func testSymlinkStoreCannotTouchDestination() async throws {
        let root = root(), outside = self.root()
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)
        do {
            let store = try ManagedLocalModelStore(root: root)
            _ = try await store.reconstruct()
            XCTFail("Symlink store accepted")
        } catch { XCTAssertEqual(error as? ManagedLocalModelStore.Failure, .unsafeStorage) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testPreferencesCannotClaimAnUnverifiedInstalledSelection() async throws {
        let root = root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"installed":["base.en"],"selectedID":"base.en"}"#.utf8)
            .write(to: root.appendingPathComponent("inventory.json"))
        let snapshot = try await ManagedLocalModelStore(root: root).reconstruct()
        XCTAssertTrue(snapshot.installed.isEmpty)
        XCTAssertEqual(snapshot.selectedID, "base.en", "Do not silently rewrite a missing durable choice")
        XCTAssertFalse(snapshot.recovery.isEmpty)
    }

    func testDownloadRedirectPolicyRejectsDowngradeAndForeignHosts() {
        for address in ["https://huggingface.co/file", "https://us.aws.cdn.hf.co/file", "https://cas-bridge.xethub.hf.co/file"] {
            XCTAssertTrue(ManagedLocalModelStore.permitsDownloadURL(URL(string: address)!))
        }
        for address in ["http://huggingface.co/file", "https://huggingface.co.evil.example/file",
                        "https://user:secret@huggingface.co/file", "https://example.com/file"] {
            XCTAssertFalse(ManagedLocalModelStore.permitsDownloadURL(URL(string: address)!))
        }
    }

    func testRedirectDelegateRejectsUnsafeLocationsAndScrubsPinnedCDNRequest() throws {
        let root = root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try ManagedLocalModelCatalog.bundled().model("base.en")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: entry.downloadURL)
        let redirect = HTTPURLResponse(url: entry.downloadURL, statusCode: 302, httpVersion: nil, headerFields: [:])!
        for address in ["http://huggingface.co/model", "https://untrusted.example/model",
                        "https://user:secret@huggingface.co/model", "https://huggingface.co:444/model"] {
            let download = try ModelDownload(partial: root.appendingPathComponent(UUID().uuidString), entry: entry,
                configuration: .ephemeral, progress: { _ in })
            download.urlSession(session, task: task, willPerformHTTPRedirection: redirect,
                newRequest: URLRequest(url: URL(string: address)!)) { XCTAssertNil($0) }
        }
        let download = try ModelDownload(partial: root.appendingPathComponent(UUID().uuidString), entry: entry,
            configuration: .ephemeral, progress: { _ in })
        let cdn = URL(string: "https://cas-bridge.xethub.hf.co/xet-bridge-us/pinned-object?X-Amz-Signature=fixture")!
        var request = URLRequest(url: cdn)
        request.httpMethod = "POST"
        request.setValue("must-not-forward", forHTTPHeaderField: "Authorization")
        request.setValue("must-not-forward", forHTTPHeaderField: "Cookie")
        for hop in 1...6 {
            download.urlSession(session, task: task, willPerformHTTPRedirection: redirect, newRequest: request) { forwarded in
                if hop == 6 { XCTAssertNil(forwarded); return }
                XCTAssertEqual(forwarded?.url, cdn, "Keep the pinned CDN path and signed query")
                XCTAssertEqual(forwarded?.httpMethod, "GET")
                XCTAssertNil(forwarded?.value(forHTTPHeaderField: "Authorization"))
                XCTAssertNil(forwarded?.value(forHTTPHeaderField: "Cookie"))
            }
        }
    }

    func testUnknownLengthOverflowStopsBeforeWritingExcessBytes() async throws {
        let root = root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChunkedModelDownloadFixture.self]
        let partial = root.appendingPathComponent("partial")
        let entry = ManagedLocalModelCatalog.Model(id: "base.en", filename: "ggml-base.en.bin", bytes: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let download = try ModelDownload(partial: partial, entry: entry, configuration: configuration, progress: { _ in })
        do { try await download.run(); XCTFail("Unknown-length overflow was accepted") }
        catch { XCTAssertEqual(error as? ManagedLocalModelStore.Failure, .integrity) }
        XCTAssertLessThanOrEqual(try Data(contentsOf: partial).count, 3, "Excess bytes must never reach disk, even when URLSession coalesces chunks")
    }

    func testUnknownLengthValidBodyIsAcceptedAndVerified() async throws {
        let root = root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChunkedModelDownloadFixture.self]
        let partial = root.appendingPathComponent("partial")
        let entry = ManagedLocalModelCatalog.Model(id: "base.en", filename: "ggml-base.en.bin", bytes: 6,
            sha256: "bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721")
        let download = try ModelDownload(partial: partial, entry: entry, configuration: configuration, progress: { _ in })
        try await download.run()
        XCTAssertEqual(try Data(contentsOf: partial), Data("abcdef".utf8))
    }
}

private final class ChunkedModelDownloadFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Transfer-Encoding": "chunked"])!
        XCTAssertEqual(response.expectedContentLength, -1)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("abc".utf8))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            self.client?.urlProtocol(self, didLoad: Data("def".utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private final class ModelDownloadFixture: URLProtocol {
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "3"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("abc".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

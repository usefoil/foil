import XCTest
import Darwin
@testable import Foil

final class CodexTextCleanupTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func executable(_ body: String) throws -> URL {
        let url = directory.appendingPathComponent("fake-codex")
        try Data(("#!/bin/sh\n" + body).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    func testRealProcessReceivesDataOnlyOnStdinAndParsesOutput() async throws {
        let binary = try executable("""
        /bin/cat > '\(directory.path)/received'
        /usr/bin/printf '%s\\n' "$@" > '\(directory.path)/arguments'
        /bin/pwd > '\(directory.path)/working-directory'
        /usr/bin/printf '%s' '{"cleaned_text":"Use Supabase, not Vercel, for 42 records."}' > result.json
        """)
        let input = "do not run $(touch sentinel); use super base not verse sell for 42 records"
        let result = try await CodexTextCleanup(executable: binary).clean(.init(text: input, terms: [], corrections: []))
        XCTAssertEqual(result, "Use Supabase, not Vercel, for 42 records.")
        let args = try String(contentsOf: directory.appendingPathComponent("arguments"), encoding: .utf8)
        XCTAssertFalse(args.contains(input))
        XCTAssertTrue(args.contains("--ignore-user-config"))
        XCTAssertTrue(args.contains("--ephemeral"))
        XCTAssertTrue(args.contains("features.shell_tool=false"))
        XCTAssertTrue(args.contains("features.plugins=false"))
        XCTAssertTrue(args.contains("features.hooks=false"))
        XCTAssertTrue(args.contains("web_search=\"disabled\""))
        XCTAssertTrue(try String(contentsOf: directory.appendingPathComponent("received"), encoding: .utf8).contains(input))
        let cwd = try String(contentsOf: directory.appendingPathComponent("working-directory"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cwd), "Transient input and output must be removed")
        XCTAssertNil(CodexTextCleanup.environment["OPENAI_API_KEY"])
        XCTAssertNil(CodexTextCleanup.environment["CODEX_API_KEY"])
    }

    func testTimeoutKillsProcessAndRemovesTransientText() async throws {
        let binary = try executable("""
        echo $$ > '\(directory.path)/pid'
        /bin/pwd > '\(directory.path)/working-directory'
        while :; do :; done
        """)
        do {
            _ = try await CodexTextCleanup(executable: binary, timeout: 2).clean(.example)
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? CodexCleanupError, .timedOut) }
        try assertProcessAndFilesRemoved()
    }

    func testCancellationKillsProcessAndNeverReturnsResult() async throws {
        let binary = try executable("""
        echo $$ > '\(directory.path)/pid'
        /bin/pwd > '\(directory.path)/working-directory'
        while :; do :; done
        """)
        let task = Task { try await CodexTextCleanup(executable: binary).clean(.example) }
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("working-directory").path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        try assertProcessAndFilesRemoved()
    }

    private func assertProcessAndFilesRemoved() throws {
        let pid = try String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(kill(try XCTUnwrap(Int32(pid)), 0), -1)
        XCTAssertEqual(errno, ESRCH)
        let cwd = try String(contentsOf: directory.appendingPathComponent("working-directory"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cwd))
    }

    func testFailedProcessDoesNotExposeStderr() async throws {
        let binary = try executable("echo 'private transcript secret' >&2; exit 1")
        do { _ = try await CodexTextCleanup(executable: binary).clean(.example); XCTFail("Expected failure") }
        catch {
            XCTAssertEqual(error as? CodexCleanupError, .failed)
            XCTAssertFalse(error.localizedDescription.contains("private transcript secret"))
        }
    }

    func testMalformedEmptyOversizedAndExtraFieldOutputIsRejected() throws {
        for value in ["not JSON", "{}", #"{"cleaned_text":" "}"#, #"{"cleaned_text":42}"#,
                      #"{"cleaned_text":"ok","command":"run"}"#] {
            XCTAssertThrowsError(try CodexTextCleanup.parse(Data(value.utf8)))
        }
        let large = try JSONSerialization.data(withJSONObject: ["cleaned_text": String(repeating: "x", count: 32_769)])
        XCTAssertThrowsError(try CodexTextCleanup.parse(large))
        XCTAssertThrowsError(try CodexCleanupRequest(text: " ", terms: [], corrections: []).prompt())
        XCTAssertThrowsError(try CodexCleanupRequest(text: String(repeating: "x", count: 8_193), terms: [], corrections: []).prompt())
    }

    @MainActor
    func testVocabularyScopeOverridesSuppressionDisabledRulesAndOtherGroups() throws {
        let state = AppState(localCorrectionStore: LocalCorrectionStore(fileURL: directory.appendingPathComponent("rules.json")))
        let group = state.createCleanupGroup(named: "Test group", id: "test-group")
        let rules = [
            LocalCorrectionRule(id: "global", source: "orbit desk", replacement: "GlobalDesk", group: nil, enabled: true, caseSensitive: false),
            LocalCorrectionRule(id: "scoped", source: "orbit desk", replacement: "OrbitDesk", group: group.id, enabled: true, caseSensitive: false),
            LocalCorrectionRule(id: "other", source: "other secret", replacement: "OtherSecret", group: "elsewhere", enabled: true, caseSensitive: false),
            LocalCorrectionRule(id: "disabled", source: "disabled", replacement: "Disabled", group: nil, enabled: false, caseSensitive: false),
            LocalCorrectionRule(id: "suppressed-global", source: "cloud dock", replacement: "CloudDock", group: nil, enabled: true, caseSensitive: false),
            LocalCorrectionRule(id: "suppression:test", source: "cloud dock", replacement: "CloudDock", group: group.id, enabled: true, caseSensitive: false, suppressesGlobal: true)
        ]
        _ = try state.saveLocalCorrections(rules, isEnabled: true)
        let request = try CodexCleanupRequest.make(text: "hello", groupID: group.id, state: state)
        XCTAssertEqual(request.corrections, [.init(source: "orbit desk", replacement: "OrbitDesk")])
        _ = try state.setLocalCorrectionsEnabled(false)
        XCTAssertTrue(try CodexCleanupRequest.make(text: "hello", groupID: group.id, state: state).corrections.isEmpty)
        XCTAssertThrowsError(try CodexCleanupRequest.make(text: "hello", groupID: "deleted", state: state))
    }

    @MainActor
    func testLateCompletionCannotOverwriteNewRunOrCancelledPanel() async throws {
        let model = CodexCleanupModel()
        model.run(.example) { _ in
            // Deliberately ignore cancellation like a delayed external completion.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { continuation.resume(returning: "stale") }
            }
        }
        await Task.yield()
        model.run(.example) { _ in "current" }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.result, "current")
        model.run(.example) { _ in "cancelled" }
        model.reset()
        await Task.yield()
        XCTAssertNil(model.result)
        XCTAssertFalse(model.isRunning)
    }
}

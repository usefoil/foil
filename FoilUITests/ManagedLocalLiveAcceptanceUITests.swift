import XCTest

final class ManagedLocalLiveAcceptanceUITests: XCTestCase {
    func testLiveManagedLocalAcceptanceRequiresExplicitDriver() throws {
        guard ProcessInfo.processInfo.environment["FOIL_RUN_MANAGED_LOCAL_GUI_ACCEPTANCE"] == "1" else {
            throw XCTSkip("Run scripts/test-managed-local-gui.sh for production-permission GUI acceptance; fixtures are not live proof.")
        }
        guard let receipt = ProcessInfo.processInfo.environment["FOIL_MANAGED_LOCAL_GUI_RECEIPT"],
              FileManager.default.fileExists(atPath: receipt) else {
            XCTFail("Live acceptance was requested without an executable-driver receipt path.")
            return
        }
        let environment = ProcessInfo.processInfo.environment
        guard let validator = environment["FOIL_MANAGED_LOCAL_GUI_VALIDATOR"],
              FileManager.default.isExecutableFile(atPath: validator),
              let scenario = environment["FOIL_MANAGED_LOCAL_GUI_SCENARIO"],
              let stateRoot = environment["FOIL_MANAGED_LOCAL_GUI_STATE_ROOT"] else {
            XCTFail("Live acceptance was requested without the receipt validator context.")
            return
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            validator, "--scenario", scenario, "--state-root", stateRoot,
            "--validate-receipt", receipt
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let validation = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, validation)
    }
}

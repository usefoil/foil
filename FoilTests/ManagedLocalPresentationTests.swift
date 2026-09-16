import XCTest
@testable import Foil

final class ManagedLocalPresentationTests: XCTestCase {
    func testCatalogPresentationUsesPinnedSizesAndSeparatesTemporarySpace() throws {
        let catalog = try ManagedLocalModelCatalog.bundled()
        let english = try catalog.model("base.en")
        let multilingual = try catalog.model("base")

        XCTAssertEqual(ManagedLocalPresentation.name(for: english.id), "Base English")
        XCTAssertEqual(ManagedLocalPresentation.name(for: multilingual.id), "Base Multilingual")
        XCTAssertEqual(ManagedLocalPresentation.downloadSize(for: english), "148 MB")
        XCTAssertEqual(ManagedLocalPresentation.installedSize(for: english), "148 MB")
        XCTAssertEqual(ManagedLocalPresentation.temporarySpace(for: english), "67 MB")
        XCTAssertEqual(ManagedLocalPresentation.requiredSpace(for: english), "215 MB")
    }

    func testDownloadPresentationUsesActualBytesWhileLaterStagesAreIndeterminate() throws {
        let downloading = ManagedLocalPresentation.status(
            state: .downloading("base.en", 73_982_105, 147_964_211),
            selectedID: nil, activeID: nil, candidateID: "base.en", recovery: []
        )
        XCTAssertEqual(downloading.title, "Downloading Base English")
        XCTAssertEqual(try XCTUnwrap(downloading.progress), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(downloading.detail, "74 MB of 148 MB")

        let verifying = ManagedLocalPresentation.status(
            state: .verifying("base.en"), selectedID: nil, activeID: nil,
            candidateID: "base.en", recovery: []
        )
        XCTAssertNil(verifying.progress)
        XCTAssertEqual(verifying.title, "Verifying Base English")

        let starting = ManagedLocalPresentation.status(
            state: .starting("base.en"), selectedID: "base", activeID: "base",
            candidateID: "base.en", recovery: []
        )
        XCTAssertNil(starting.progress)
        XCTAssertEqual(starting.detail, "Candidate: Base English · Active: Base Multilingual")
    }

    func testFailedSwitchNamesStillWorkingActiveModel() {
        let status = ManagedLocalPresentation.status(
            state: .failed("The managed local model could not start."),
            selectedID: "base.en", activeID: "base.en", candidateID: nil, recovery: []
        )
        XCTAssertEqual(status.title, "Model change failed")
        XCTAssertEqual(status.detail,
            "The managed local model could not start. Still active: Base English")
        XCTAssertTrue(status.canRetry)
    }

    func testCancelledDownloadExposesRetryWithoutDiscardingActiveModel() {
        let status = ManagedLocalPresentation.status(
            state: .cancelled,
            selectedID: "base.en",
            activeID: "base.en",
            candidateID: nil,
            recovery: []
        )
        XCTAssertEqual(status.title, "Model operation cancelled")
        XCTAssertEqual(status.detail, "Still active: Base English")
        XCTAssertTrue(status.isReady)
        XCTAssertTrue(status.canRetry)
        XCTAssertNil(status.progress)
    }

    func testMissingSelectionRecoveryNeverClaimsReady() {
        let status = ManagedLocalPresentation.status(
            state: .idle, selectedID: "base", activeID: nil, candidateID: nil,
            recovery: ["The selected model base is missing or corrupt."]
        )
        XCTAssertEqual(status.title, "Restore local model")
        XCTAssertFalse(status.isReady)
        XCTAssertTrue(status.canRetry)
        XCTAssertEqual(status.detail, "The selected model base is missing or corrupt.")
    }

    func testConstructionOrRestoreErrorIsActionableAndNeverReady() {
        let unavailable = ManagedLocalPresentation.status(
            coordinatorState: nil, selectedID: nil, activeID: nil, candidateID: nil,
            recovery: [], externalError: "The model catalog could not be loaded."
        )
        XCTAssertEqual(unavailable.title, "Local model unavailable")
        XCTAssertEqual(unavailable.detail, "The model catalog could not be loaded.")
        XCTAssertFalse(unavailable.isReady)
        XCTAssertFalse(unavailable.canRetry,
            "A missing coordinator must not offer a retry action that cannot run")

        let restoreFailed = ManagedLocalPresentation.status(
            coordinatorState: .idle, selectedID: "base.en", activeID: nil, candidateID: nil,
            recovery: [], externalError: "The selected model could not be restored."
        )
        XCTAssertEqual(restoreFailed.title, "Restore local model")
        XCTAssertEqual(restoreFailed.detail, "The selected model could not be restored.")
        XCTAssertFalse(restoreFailed.isReady)
        XCTAssertTrue(restoreFailed.canRetry)
    }

    func testStaleRestoreErrorCannotMaskRetryProgressOrCancellation() {
        let downloading = ManagedLocalPresentation.status(
            coordinatorState: .downloading("base.en", 73_982_105, 147_964_211),
            selectedID: "base.en",
            activeID: nil,
            candidateID: "base.en",
            recovery: [],
            externalError: "Previous restore failed"
        )
        XCTAssertEqual(downloading.title, "Downloading Base English")
        XCTAssertEqual(downloading.progress ?? -1, 0.5, accuracy: 0.000_001)

        let cancelled = ManagedLocalPresentation.status(
            coordinatorState: .cancelled,
            selectedID: "base.en",
            activeID: nil,
            candidateID: nil,
            recovery: [],
            externalError: "Previous restore failed"
        )
        XCTAssertEqual(cancelled.title, "Model operation cancelled")
    }

    func testRemovalProtectionSeparatesSelectedActiveAndCandidateModels() {
        XCTAssertEqual(ManagedLocalPresentation.removalReason(
            id: "base.en", selectedID: "base.en", activeID: nil, candidateID: nil,
            protectedIDs: []), "Selected models cannot be removed. Select another model first.")
        XCTAssertEqual(ManagedLocalPresentation.removalReason(
            id: "base.en", selectedID: "base", activeID: "base.en", candidateID: nil,
            protectedIDs: ["base.en"]), "Active or in-use models cannot be removed.")
        XCTAssertEqual(ManagedLocalPresentation.removalReason(
            id: "base.en", selectedID: "base", activeID: "base", candidateID: "base.en",
            protectedIDs: []), "A model being installed or started cannot be removed.")
        XCTAssertNil(ManagedLocalPresentation.removalReason(
            id: "base.en", selectedID: "base", activeID: "base", candidateID: nil,
            protectedIDs: []))
    }
}

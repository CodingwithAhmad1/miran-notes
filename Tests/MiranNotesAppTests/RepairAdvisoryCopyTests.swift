import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class RepairAdvisoryCopyTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranCopy-\(UUID().uuidString)", isDirectory: true)
    }

    func testExternalEditConflictCopyIsStable() {
        XCTAssertFalse(ExternalEditConflictCopy.alertTitle.isEmpty)
        XCTAssertFalse(ExternalEditConflictCopy.alertMessage.isEmpty)
        XCTAssertFalse(ExternalEditConflictCopy.buttonKeepEdits.isEmpty)
        XCTAssertFalse(ExternalEditConflictCopy.buttonUseSavedFile.isEmpty)
        XCTAssertFalse(ExternalEditConflictCopy.buttonCompare.isEmpty)
        XCTAssertFalse(ExternalEditConflictCopy.detailsLines(diskDate: Date()).isEmpty)
    }

    func testPresentFullBufferAdvisory() {
        let vault = try! tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        let model = AppModel(repository: repo)
        model.presentFullBufferAdvisory()
        XCTAssertEqual(model.repairAdvisory?.kind, .fullBufferFallback)
        XCTAssertFalse(model.repairAdvisory?.title.isEmpty ?? true)
        XCTAssertFalse(model.repairAdvisory?.detailsPlainText?.isEmpty ?? true)
    }

    func testPresentSizeLimitAdvisory() {
        let vault = try! tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        let model = AppModel(repository: repo)
        model.presentSizeLimitAdvisory()
        XCTAssertEqual(model.repairAdvisory?.kind, .sizeLimitExceeded)
        XCTAssertFalse(model.repairAdvisory?.title.isEmpty ?? true)
    }

    func testRepairDiagnosticsMapsGapWarning() {
        let warnings = ["Found a block gap. Expanded previous block coverage."]
        let details = RepairDiagnosticsBuilder.details(repairWarnings: warnings, hadWikiLinkAdvisory: false)
        XCTAssertNotNil(details)
        XCTAssertTrue(details!.lowercased().contains("section"))
        XCTAssertFalse(details!.lowercased().contains("utf"))
    }
}

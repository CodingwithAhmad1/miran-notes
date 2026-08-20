import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelIconBrowserAndMoveTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    private func waitForAsync(_ maxAttempts: Int = 80, _ intervalMs: UInt64 = 25, _ condition: () -> Bool) async throws {
        for _ in 0..<maxAttempts {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(intervalMs))
        }
    }

    func testIconPositionsRoundTripAndPruneStaleIDs() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let model = AppModel(repository: repo)
        let folderID = UUID()
        let keep = UUID()
        let stale = UUID()

        model.setIconPosition(CGPoint(x: 10, y: 20), itemID: stale, folderID: folderID, validItemIDs: [stale, keep])
        model.setIconPosition(CGPoint(x: 100, y: 200), itemID: keep, folderID: folderID, validItemIDs: [keep])

        // Stale entry pruned by the second save; keep survives with its snap position.
        let reloaded = AppModel(repository: repo)
        let positions = reloaded.iconPositions(folderID: folderID)
        XCTAssertEqual(positions[keep], CGPoint(x: 100, y: 200))
        XCTAssertNil(positions[stale])

        model.clearIconLayout(folderID: folderID)
        XCTAssertTrue(model.iconPositions(folderID: folderID).isEmpty)
    }

    func testFolderViewModePersists() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let model = AppModel(repository: repo)
        let folderID = UUID()

        XCTAssertEqual(model.folderPageViewMode(folderID: folderID), .icons, "icons is the default")
        model.setFolderPageViewMode(.list, folderID: folderID)

        let reloaded = AppModel(repository: repo)
        reloaded.loadFolderViewModes()
        XCTAssertEqual(reloaded.folderPageViewMode(folderID: folderID), .list)
    }

    func testMoveNoteIntoDashboardIsRejectedWithAlert() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let dashboardID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Dash")
        try await repo.setFolderRole(.dashboard, folderID: dashboardID)
        let repositoryID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Repo")
        try await repo.setFolderRole(.repository, folderID: repositoryID)
        let (doc, _) = try await repo.createNote(named: "movable", folderID: repositoryID)

        let model = AppModel(repository: repo)
        await model.refreshNotes()

        model.moveNote(noteID: doc.metadata.noteID, toFolderID: dashboardID)
        guard case .message(let text) = model.userAlert else {
            return XCTFail("expected role-violation alert")
        }
        XCTAssertTrue(text.contains("Dashboard"))
        // Note did not move.
        XCTAssertEqual(model.noteSummaries.first(where: { $0.noteID == doc.metadata.noteID })?.folderID, repositoryID)
    }

    func testMoveNoteBetweenRepositoriesMovesOnDisk() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let sourceID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Source")
        try await repo.setFolderRole(.repository, folderID: sourceID)
        let destinationID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Destination")
        try await repo.setFolderRole(.repository, folderID: destinationID)
        let (doc, _) = try await repo.createNote(named: "traveler", folderID: sourceID)

        let model = AppModel(repository: repo)
        await model.refreshNotes()

        model.moveNote(noteID: doc.metadata.noteID, toFolderID: destinationID)
        try await waitForAsync {
            model.noteSummaries.first(where: { $0.noteID == doc.metadata.noteID })?.folderID == destinationID
        }
        let summary = try XCTUnwrap(model.noteSummaries.first(where: { $0.noteID == doc.metadata.noteID }))
        XCTAssertEqual(summary.folderID, destinationID)
        XCTAssertTrue(summary.relativePath.hasPrefix("destination/"), "note file relocated under the destination folder: \(summary.relativePath)")
    }
}

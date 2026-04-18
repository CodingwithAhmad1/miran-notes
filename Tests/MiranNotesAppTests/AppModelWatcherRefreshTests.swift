import Foundation
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelWatcherRefreshTests: XCTestCase {
    func testRepositoryReconcileAfterExternalMarkdownListsTwoNotes() async throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "ImportMd")
        let (_, seedPath) = try await repo.createNote(named: "seed", folderID: folderID, bodyFileExtension: "md")
        let folderPrefix = (seedPath as NSString).deletingLastPathComponent
        let droppedStem = "dropped-import"

        let dropURL = vault.appendingPathComponent("\(folderPrefix)/\(droppedStem).md")
        try "external markdown".write(to: dropURL, atomically: true, encoding: .utf8)

        try await repo.reconcileManifest()
        let summaries = try await repo.listNotes()
        XCTAssertEqual(summaries.count, 2)
        XCTAssertTrue(summaries.contains { $0.relativePath == "\(folderPrefix)/\(droppedStem)" })
    }

    func testSimulateWatcherEventAfterExternalMarkdownAddsNoteToSummaries() async throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "ImportMd")
        let (_, seedPath) = try await repo.createNote(named: "seed", folderID: folderID, bodyFileExtension: "md")
        let folderPrefix = (seedPath as NSString).deletingLastPathComponent
        let droppedStem = "dropped-import"

        let model = AppModel(repository: repo)
        model.workspaceGateState = .ready
        await model.refreshNotes()
        XCTAssertEqual(model.noteSummaries.count, 1)

        let dropURL = vault.appendingPathComponent("\(folderPrefix)/\(droppedStem).md")
        try "external markdown".write(to: dropURL, atomically: true, encoding: .utf8)

        await model.simulateWatcherEvent()

        XCTAssertEqual(model.userAlert, .none)
        XCTAssertEqual(model.noteSummaries.count, 2)
        XCTAssertTrue(model.noteSummaries.contains { $0.relativePath == "\(folderPrefix)/\(droppedStem)" })
        XCTAssertTrue(model.noteSummaries.contains { $0.bodyFileExtension == "md" })
    }
}

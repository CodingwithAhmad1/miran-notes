import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class VaultStructureTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    func testCreateFolderAndNoteUsesNestedRelativePath() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Work")
        let (_, relPath) = try await repo.createNote(named: "task", folderID: folderID)

        XCTAssertTrue(relPath.contains("/"), "Expected nested path, got \(relPath)")
        let txt = vault.appendingPathComponent("\(relPath).txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: txt.path))

        let summaries = try await repo.listNotes()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].folderID, folderID)
    }

    func testDeleteNoteRemovesFilesAndManifestEntry() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (doc, path) = try await repo.createNote(named: "gone")
        let id = doc.metadata.noteID

        try await repo.deleteNote(noteID: id)

        let txt = vault.appendingPathComponent("\(path).txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: txt.path))
        let manifest = try await repo.loadManifest()
        XCTAssertNil(manifest.entry(noteID: id))
    }

    func testDeleteFolderFailsWhenFolderContainsNote() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Inbox")
        _ = try await repo.createNote(named: "item", folderID: folderID)

        do {
            try await repo.deleteFolder(id: folderID)
            XCTFail("Expected folderNotEmpty")
        } catch let error as NoteRepositoryError {
            if case .folderNotEmpty = error {
                return
            }
            XCTFail("Expected folderNotEmpty, got \(error)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMoveNoteToFolderUpdatesPathIndex() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (doc, oldPath) = try await repo.createNote(named: "move-me")
        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Target")

        try await repo.moveNote(noteID: doc.metadata.noteID, toFolderID: folderID)

        let summaries = try await repo.listNotes()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].noteID, doc.metadata.noteID)
        XCTAssertEqual(summaries[0].folderID, folderID)
        XCTAssertNotEqual(summaries[0].relativePath, oldPath)
    }

    func testListNotesDisambiguatesSameDisplayTitleInDifferentFolders() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createNote(named: "same-name")
        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Inbox")
        _ = try await repo.createNote(named: "same-name", folderID: folderID)

        let summaries = try await repo.listNotes()
        XCTAssertEqual(summaries.count, 2)
        let titles = Set(summaries.map(\.title))
        XCTAssertEqual(titles.count, 2, "Duplicate sidebar titles should be disambiguated with folder context")
        XCTAssertTrue(titles.contains(where: { $0.contains("Root") }))
        XCTAssertTrue(titles.contains(where: { $0.contains("Inbox") }))
    }
}

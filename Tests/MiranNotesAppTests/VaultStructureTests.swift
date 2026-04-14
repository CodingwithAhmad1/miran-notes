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

    func testDeleteFolderRecursivelyRemovesNotesMetadataAndSubfolders() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let parentID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Inbox")
        let (parentDoc, parentPath) = try await repo.createNote(named: "top-item", folderID: parentID)

        let parentTxt = vault.appendingPathComponent("\(parentPath).txt")
        let parentMeta = vault.appendingPathComponent("\(parentPath).meta.json")

        try await repo.deleteFolder(id: parentID)

        let manifest = try await repo.loadManifest()
        XCTAssertNil(manifest.entry(noteID: parentDoc.metadata.noteID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parentTxt.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parentMeta.path))

        let catalog = try await repo.loadFolderCatalog()
        XCTAssertNil(catalog.folder(id: parentID))
    }

    func testDeleteFolderRemovesNoteAuxDirectory() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Inbox")
        let (doc, _) = try await repo.createNote(named: "item", folderID: folderID)

        let auxDirectory = VaultPaths.auxDirectory(vaultURL: vault, noteID: doc.metadata.noteID)
        try FileManager.default.createDirectory(at: auxDirectory, withIntermediateDirectories: true)
        let auxFile = auxDirectory.appendingPathComponent("blob.bin")
        try Data([0x01, 0x02, 0x03]).write(to: auxFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: auxFile.path))

        try await repo.deleteFolder(id: folderID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: auxDirectory.path))
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

    func testListNotesKeepsSameDisplayTitleForNotesInDifferentFolders() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createNote(named: "same-name")
        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Inbox")
        _ = try await repo.createNote(named: "same-name", folderID: folderID)

        let summaries = try await repo.listNotes()
        XCTAssertEqual(summaries.count, 2)
        let titles = Set(summaries.map(\.title))
        XCTAssertEqual(titles.count, 1, "UI uses the same primary title; paths differ for disambiguation")
        let paths = Set(summaries.map(\.relativePath))
        XCTAssertEqual(paths.count, 2)
    }

    func testCreateFolderAllowsDuplicateDisplayNamesWithDistinctPaths() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let firstID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "New Folder")
        let secondID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "New Folder")
        XCTAssertNotEqual(firstID, secondID)

        let (_, firstPath) = try await repo.createNote(named: "same", folderID: firstID)
        let (_, secondPath) = try await repo.createNote(named: "same", folderID: secondID)
        XCTAssertNotEqual(firstPath, secondPath)
        XCTAssertTrue(firstPath.hasPrefix("new-folder/"))
        XCTAssertTrue(secondPath.hasPrefix("new-folder-2/"))
    }

    func testRenameFolderDoesNotRewriteNoteRelativePaths() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Inbox")
        let (doc, oldPath) = try await repo.createNote(named: "item", folderID: folderID)

        try await repo.renameFolder(id: folderID, newName: "Renamed")

        let summaries = try await repo.listNotes()
        let updated = try XCTUnwrap(summaries.first(where: { $0.noteID == doc.metadata.noteID }))
        XCTAssertEqual(updated.relativePath, oldPath)
    }
}

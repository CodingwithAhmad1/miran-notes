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
        try await repo.setFolderRole(.repository, folderID: folderID)
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
        try await repo.setFolderRole(.repository, folderID: parentID)
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
        try await repo.setFolderRole(.repository, folderID: folderID)
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
        try await repo.setFolderRole(.repository, folderID: folderID)

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
        try await repo.setFolderRole(.repository, folderID: folderID)
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
        try await repo.setFolderRole(.repository, folderID: firstID)
        try await repo.setFolderRole(.repository, folderID: secondID)

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
        try await repo.setFolderRole(.repository, folderID: folderID)
        let (doc, oldPath) = try await repo.createNote(named: "item", folderID: folderID)

        try await repo.renameFolder(id: folderID, newName: "Renamed")

        let summaries = try await repo.listNotes()
        let updated = try XCTUnwrap(summaries.first(where: { $0.noteID == doc.metadata.noteID }))
        XCTAssertEqual(updated.relativePath, oldPath)
    }

    func testFolderCatalogV2MigrationAssignsRepositoryRoles() throws {
        let uid = UUID()
        var folders: [FolderEntry] = [
            .root,
            FolderEntry(id: uid, name: "Alpha", storageSegment: "alpha", parentFolderID: FolderCatalog.rootFolderID, role: nil),
        ]
        var catalog = FolderCatalog(schemaVersion: 2, folders: folders)
        catalog.ensureRoot()
        XCTAssertEqual(catalog.schemaVersion, 3)
        XCTAssertEqual(catalog.folder(id: uid)?.role, .repository)
    }

    func testNestedDashboardRepositoryNotePath() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let hubID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Hub")
        try await repo.setFolderRole(.dashboard, folderID: hubID)
        let leafID = try await repo.createFolder(parentID: hubID, name: "Leaf")
        try await repo.setFolderRole(.repository, folderID: leafID)
        let (_, path) = try await repo.createNote(named: "inner", folderID: leafID)
        XCTAssertTrue(path.contains("/"), "Expected multi-segment path, got \(path)")
    }

    func testCreateSubfolderUnderRepositoryFails() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "R")
        try await repo.setFolderRole(.repository, folderID: folderID)
        do {
            _ = try await repo.createFolder(parentID: folderID, name: "Nested")
            XCTFail("Expected invalidFolderMove")
        } catch let error as NoteRepositoryError {
            XCTAssertEqual(error, .invalidFolderMove)
        }
    }

    func testCreateNoteInDashboardFails() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "D")
        try await repo.setFolderRole(.dashboard, folderID: folderID)
        do {
            _ = try await repo.createNote(named: "n", folderID: folderID)
            XCTFail("Expected folderCannotContainNotes")
        } catch let error as NoteRepositoryError {
            XCTAssertEqual(error, .folderCannotContainNotes(folderID))
        }
    }

    func testFolderIDOwningNoteResolvesNestedRepositoryPath() throws {
        let p = UUID()
        let a = UUID()
        var folders: [FolderEntry] = [
            .root,
            FolderEntry(id: p, name: "P", storageSegment: "p", parentFolderID: FolderCatalog.rootFolderID, role: .dashboard),
            FolderEntry(id: a, name: "A", storageSegment: "a", parentFolderID: p, role: .repository),
        ]
        var catalog = FolderCatalog(folders: folders)
        catalog.ensureRoot()
        XCTAssertEqual(catalog.relativeDirectoryPath(for: a), "p/a")
        XCTAssertEqual(catalog.folderIDOwningNote(relativePathWithoutExtension: "p/a/note-stem"), a)
        XCTAssertEqual(catalog.folderIDOwningNote(relativePathWithoutExtension: "vault-root-note"), FolderCatalog.rootFolderID)
    }

    func testReconcileAssignsLeafFolderForExternalMarkdownInNestedRepo() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let hubID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Hub")
        try await repo.setFolderRole(.dashboard, folderID: hubID)
        let leafID = try await repo.createFolder(parentID: hubID, name: "Leaf")
        try await repo.setFolderRole(.repository, folderID: leafID)
        var catalog = try await repo.loadFolderCatalog()
        catalog.ensureRoot()
        let dirPrefix = catalog.relativeDirectoryPath(for: leafID)
        let rel = "\(dirPrefix)/dropped-md"
        let mdURL = vault.appendingPathComponent(rel).appendingPathExtension("md")
        try "# body".write(to: mdURL, atomically: true, encoding: .utf8)
        try await repo.reconcileManifest()
        let summaries = try await repo.listNotes()
        let found = try XCTUnwrap(summaries.first { $0.relativePath == rel })
        XCTAssertEqual(found.folderID, leafID)
        XCTAssertEqual(found.bodyFileExtension, "md")
    }

    func testReconcileSkipsMarkdownInsideDashboardOnlyFolder() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let dashID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "DashOnly")
        try await repo.setFolderRole(.dashboard, folderID: dashID)
        var catalog = try await repo.loadFolderCatalog()
        catalog.ensureRoot()
        let prefix = catalog.relativeDirectoryPath(for: dashID)
        let rel = "\(prefix)/should-skip"
        let mdURL = vault.appendingPathComponent(rel).appendingPathExtension("md")
        try FileManager.default.createDirectory(at: mdURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "!".write(to: mdURL, atomically: true, encoding: .utf8)
        try await repo.reconcileManifest()
        let summaries = try await repo.listNotes()
        XCTAssertNil(summaries.first { $0.relativePath == rel })
    }
}

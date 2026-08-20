import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class NoteRepositoryTrashTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    func testTrashThenRestorePreservesNoteIDAndContent() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        var (doc, path) = try await repo.createNote(named: "keepsake")
        doc.text = "precious content"
        doc.metadata.blocks = [
            Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: doc.text.utf16.count), level: nil, icon: nil)
        ]
        _ = try await repo.save(doc, asBaseName: path)
        let noteID = doc.metadata.noteID

        try await repo.trashNote(noteID: noteID)

        // Gone from the vault list; present in trash.
        let listed = try await repo.listNotes()
        XCTAssertFalse(listed.contains { $0.noteID == noteID })
        let trashed = await repo.listTrashedNotes()
        XCTAssertEqual(trashed.map(\.noteID), [noteID])

        let restoredPath = try await repo.restoreTrashedNote(noteID: noteID)
        let after = try await repo.listNotes()
        XCTAssertTrue(after.contains { $0.noteID == noteID })
        let loaded = try await repo.loadNote(noteID: noteID)
        XCTAssertEqual(loaded.document.text, "precious content")
        XCTAssertEqual(loaded.document.metadata.noteID, noteID, "restore must preserve identity so links resolve again")
        XCTAssertFalse(restoredPath.isEmpty)

        // Trash entry consumed.
        let remaining = await repo.listTrashedNotes()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testTrashCopyExistsBeforeVaultDeletion() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (doc, _) = try await repo.createNote(named: "crash-window")
        try await repo.trashNote(noteID: doc.metadata.noteID)

        let trashDir = VaultPaths.trashNoteDirectory(vaultURL: vault, noteID: doc.metadata.noteID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashDir.appendingPathComponent("trash-record.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashDir.appendingPathComponent("body.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashDir.appendingPathComponent("meta.json").path))
    }

    func testPermanentDeleteAndEmptyTrash() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (docA, _) = try await repo.createNote(named: "one")
        let (docB, _) = try await repo.createNote(named: "two")
        try await repo.trashNote(noteID: docA.metadata.noteID)
        try await repo.trashNote(noteID: docB.metadata.noteID)

        await repo.deleteTrashedNotePermanently(noteID: docA.metadata.noteID)
        var trashed = await repo.listTrashedNotes()
        XCTAssertEqual(trashed.map(\.noteID), [docB.metadata.noteID])

        await repo.emptyTrash()
        trashed = await repo.listTrashedNotes()
        XCTAssertTrue(trashed.isEmpty)
    }

    func testRestoreIntoRecoveredFolderWhenOriginalFolderGone() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let folderID = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Doomed")
        try await repo.setFolderRole(.repository, folderID: folderID)
        let (doc, _) = try await repo.createNote(named: "orphan", folderID: folderID)

        try await repo.trashNote(noteID: doc.metadata.noteID)
        try await repo.deleteFolder(id: folderID)

        let restoredPath = try await repo.restoreTrashedNote(noteID: doc.metadata.noteID)
        let listed = try await repo.listNotes()
        XCTAssertTrue(listed.contains { $0.noteID == doc.metadata.noteID }, "restored somewhere valid: \(restoredPath)")
    }
}

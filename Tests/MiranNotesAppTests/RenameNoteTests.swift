import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class RenameNoteTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranRename-\(UUID().uuidString)", isDirectory: true)
    }

    func testRenameNoteChangesBaseNamePreservesNoteID() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (doc, oldBase) = try await repo.createNote(named: "alpha")
        let id = doc.metadata.noteID

        let newBase = try await repo.renameNote(from: oldBase, to: "renamed-title")
        XCTAssertNotEqual(newBase, oldBase)
        XCTAssertTrue(newBase.contains("renamed"))

        let loaded = try await repo.loadNote(baseName: newBase)
        XCTAssertEqual(loaded.metadata.noteID, id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("\(oldBase).txt").path))
    }
}

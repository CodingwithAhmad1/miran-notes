import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelCommandBatchLimitTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    func testTruncatedBatchMatchesPrefixApplyAndSetsRepairAdvisory() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, base) = try await repo.createNote(named: "batch-note")

        let limited = AppModel(
            repository: repo,
            commandPipelineContract: CommandPipelineContract(maxCommandsPerBatch: 3)
        )
        await limited.refreshNotes()
        limited.selectedBaseName = base
        await limited.loadSelectedNote()

        let fourInserts = (0..<4).map { i in
            EditCommand.replaceText(range: TextRange(start: i, length: 0), replacement: String(UnicodeScalar(97 + i)!))
        }
        limited.apply(fourInserts, recordUndo: false)

        XCTAssertEqual(limited.activeDocument?.text, "abc")
        XCTAssertEqual(limited.repairAdvisory?.kind, .commandBatchTruncated)

        let full = AppModel(repository: repo, commandPipelineContract: CommandPipelineContract(maxCommandsPerBatch: 128))
        await full.refreshNotes()
        full.selectedBaseName = base
        await full.loadSelectedNote()
        full.apply(Array(fourInserts.prefix(3)), recordUndo: false)

        XCTAssertEqual(full.activeDocument?.text, limited.activeDocument?.text)
        XCTAssertNil(full.repairAdvisory)
    }

    func testDoesNotReplaceExistingRepairAdvisoryWhenTruncating() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, base) = try await repo.createNote(named: "batch-note2")

        let model = AppModel(
            repository: repo,
            commandPipelineContract: CommandPipelineContract(maxCommandsPerBatch: 1)
        )
        await model.refreshNotes()
        model.selectedBaseName = base
        await model.loadSelectedNote()

        let existing = RepairAdvisory(
            kind: .sizeLimitExceeded,
            title: "Existing",
            explanation: "Existing advisory",
            detailsPlainText: nil
        )
        model.repairAdvisory = existing

        let two = [
            EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "a"),
            EditCommand.replaceText(range: TextRange(start: 1, length: 0), replacement: "b"),
        ]
        model.apply(two, recordUndo: false)

        XCTAssertEqual(model.repairAdvisory?.kind, .sizeLimitExceeded)
        XCTAssertEqual(model.activeDocument?.text, "a")
    }
}

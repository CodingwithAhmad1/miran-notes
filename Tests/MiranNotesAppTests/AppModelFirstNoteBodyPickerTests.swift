import Foundation
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelFirstNoteBodyPickerTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    private func waitUntil(
        maxAttempts: Int = 120,
        intervalMs: UInt64 = 25,
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<maxAttempts {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(intervalMs))
        }
    }

    func testCreateNoteInEmptyFolderShowsPickerThenPersistsConvention() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let model = AppModel(repository: repo)
        model.loadVault()
        try await waitUntil {
            if case .ready = model.workspaceGateState { return true }
            return false
        }

        model.createFolder(name: "EmptyTopic")
        try await waitUntil { model.topLevelFolderEntries.count == 1 }
        let folderID = try XCTUnwrap(model.topLevelFolderEntries.first?.id)
        model.selectFolderForPage(folderID)

        model.createNote()
        try await waitUntil { model.pendingFolderFirstNoteBodyPicker != nil }
        XCTAssertEqual(model.pendingFolderFirstNoteBodyPicker?.folderID, folderID)

        model.confirmPendingFirstNoteBodyFormat(bodyFileExtension: "md")
        try await waitUntil { model.pendingFolderFirstNoteBodyPicker == nil }
        try await waitUntil { model.noteSummaries.contains { $0.folderID == folderID && $0.bodyFileExtension == "md" } }

        let stored = FolderNoteBodyConventionStore.load(vaultURL: vault)
        XCTAssertEqual(stored[folderID], "md")
    }
}

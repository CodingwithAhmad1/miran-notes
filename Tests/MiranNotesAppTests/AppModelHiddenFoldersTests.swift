import Foundation
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelHiddenFoldersTests: XCTestCase {
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

    func testHideFolderClearsSelectionAndSidebarVisibility() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Inbox")

        let model = AppModel(repository: repo)
        model.loadVault()

        try await waitUntil {
            if case .ready = model.workspaceGateState { return true }
            return false
        }
        try await waitUntil { model.topLevelFolderEntries.count == 1 }

        let folderID = try XCTUnwrap(model.topLevelFolderEntries.first?.id)
        model.selectFolderForPage(folderID)
        XCTAssertEqual(model.selectedFolderID, folderID)

        model.hideTopLevelFolders(ids: [folderID])

        XCTAssertTrue(model.visibleTopLevelFolderEntries.isEmpty)
        XCTAssertNil(
            model.selectedFolderID,
            "With no visible folders and no vault-root notes, selection falls back to nil."
        )
    }

    func testHiddenFoldersPersistPerVault() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "Archives")

        let model = AppModel(repository: repo)
        model.loadVault()

        try await waitUntil {
            if case .ready = model.workspaceGateState { return true }
            return false
        }
        try await waitUntil { model.topLevelFolderEntries.count == 1 }

        let folderID = try XCTUnwrap(model.topLevelFolderEntries.first?.id)
        model.hideTopLevelFolders(ids: [folderID])
        XCTAssertTrue(model.visibleTopLevelFolderEntries.isEmpty)

        let model2 = AppModel(repository: repo)
        model2.loadVault()

        try await waitUntil {
            if case .ready = model2.workspaceGateState { return true }
            return false
        }
        try await waitUntil { model2.topLevelFolderEntries.count == 1 }
        try await waitUntil { model2.hiddenTopLevelFolderIDs.contains(folderID) }

        XCTAssertTrue(model2.visibleTopLevelFolderEntries.isEmpty)
        XCTAssertEqual(model2.hiddenTopLevelFolderIDs, Set([folderID]))
    }

    func testDeleteFolderRemovesIdFromHiddenStore() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createFolder(parentID: FolderCatalog.rootFolderID, name: "TrashMe")

        let model = AppModel(repository: repo)
        model.loadVault()

        try await waitUntil {
            if case .ready = model.workspaceGateState { return true }
            return false
        }
        try await waitUntil { model.topLevelFolderEntries.count == 1 }

        let folderID = try XCTUnwrap(model.topLevelFolderEntries.first?.id)
        model.hideTopLevelFolders(ids: [folderID])
        XCTAssertEqual(VaultHiddenFoldersStore.load(vaultURL: vault), Set([folderID]))

        model.deleteFolder(id: folderID)

        try await waitUntil { model.topLevelFolderEntries.isEmpty }
        try await waitUntil { VaultHiddenFoldersStore.load(vaultURL: vault).isEmpty }

        XCTAssertTrue(model.hiddenTopLevelFolderIDs.isEmpty)
    }
}

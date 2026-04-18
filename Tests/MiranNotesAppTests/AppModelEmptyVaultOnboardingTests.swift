import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelEmptyVaultOnboardingTests: XCTestCase {
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

    func testEmptyVaultAfterLoadVaultIsOnboardingState() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let model = AppModel(repository: repo)
        model.loadVault()

        try await waitUntil {
            if case .ready = model.workspaceGateState { return true }
            return false
        }
        try await waitUntil { model.noteSummaries.isEmpty && model.selectedFolderID == nil }

        XCTAssertTrue(model.isEmptyVaultOnboardingState)
    }

    func testOnboardingStateFalseWhenVaultHasRootNote() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createNote(named: "solo")

        let model = AppModel(repository: repo)
        model.loadVault()

        try await waitUntil {
            if case .ready = model.workspaceGateState { return true }
            return false
        }
        try await waitUntil { !model.noteSummaries.isEmpty }

        XCTAssertFalse(model.isEmptyVaultOnboardingState)
        XCTAssertNil(model.selectedFolderID, "Welcome flow keeps nil selection until user picks a folder")

        model.selectFolderForPage(FolderCatalog.rootFolderID)
        XCTAssertEqual(model.selectedFolderID, FolderCatalog.rootFolderID)
        XCTAssertTrue(VaultWelcomeDismissalStore.isDismissed(vaultURL: vault))
    }

    func testOnboardingStateFalseAfterCreateFolder() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let model = AppModel(repository: repo)
        model.loadVault()

        try await waitUntil {
            if case .ready = model.workspaceGateState { return true }
            return false
        }
        try await waitUntil { model.isEmptyVaultOnboardingState }

        model.createFolder()

        try await waitUntil { !model.isEmptyVaultOnboardingState }
        try await waitUntil { model.selectedFolderID != nil }

        XCTAssertNotNil(model.selectedFolderID)
        XCTAssertTrue(VaultWelcomeDismissalStore.isDismissed(vaultURL: vault))
    }

    func testExistingTopLevelFolderDoesNotAutoSelectUntilUserPicks() async throws {
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

        XCTAssertNil(model.selectedFolderID)
        let folderID = try XCTUnwrap(model.topLevelFolderEntries.first?.id)
        model.selectFolderForPage(folderID)
        XCTAssertEqual(model.selectedFolderID, folderID)
        XCTAssertTrue(VaultWelcomeDismissalStore.isDismissed(vaultURL: vault))
    }
}

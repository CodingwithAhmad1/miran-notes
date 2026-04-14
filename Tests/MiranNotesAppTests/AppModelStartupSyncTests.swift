import Foundation
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelStartupSyncTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    func testStartupLinkGraphSyncDecisionImmediateAtThreshold() {
        let decision = LinkGraphStartupPolicy.decision(
            noteCount: 2_000,
            noteLinkRelationshipCount: 100,
            hardThreshold: 2_000,
            historicalAverageMs: 40,
            budgetMs: 120
        )
        XCTAssertEqual(decision.mode, .immediate)
    }

    func testStartupLinkGraphSyncDecisionDeferredAboveThreshold() {
        let decision = LinkGraphStartupPolicy.decision(
            noteCount: 2_001,
            noteLinkRelationshipCount: 100,
            hardThreshold: 2_000,
            historicalAverageMs: 40,
            budgetMs: 120
        )
        XCTAssertEqual(decision.mode, .deferred)
    }

    func testStartupLinkGraphSyncDecisionDeferredWhenHistoricalAverageOverBudget() {
        let decision = LinkGraphStartupPolicy.decision(
            noteCount: 500,
            noteLinkRelationshipCount: 2_000,
            hardThreshold: 2_000,
            historicalAverageMs: 220,
            budgetMs: 120
        )
        XCTAssertEqual(decision.mode, .deferred)
    }

    func testLoadVaultDeferredSyncStillLoadsInitialNote() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createNote(named: "startup-note")

        let model = AppModel(repository: repo, largeVaultLinkGraphSyncThreshold: 0)
        model.loadVault()

        // Deferred sync should not block folder-page load once the user selects the vault root.
        var ready = false
        for _ in 0..<100 {
            if case .ready = model.workspaceGateState, !model.noteSummaries.isEmpty {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(ready, "vault should become ready with notes listed")

        await model.selectFolderForPage(FolderCatalog.rootFolderID)

        var listed = false
        for _ in 0..<100 {
            if model.selectedFolderID == FolderCatalog.rootFolderID,
               model.folderPageNoteSummaries.count == 1 {
                listed = true
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(listed, "folder page should list root notes even when link graph sync is deferred")
        XCTAssertEqual(model.userAlert, .none)
    }
}

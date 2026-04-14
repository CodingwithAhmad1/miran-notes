import Foundation
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelStartupSyncTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranNotesStartupSync-\(UUID().uuidString)", isDirectory: true)
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

        // Deferred sync should not block initial folder-page load for root-level notes.
        var loaded = false
        for _ in 0..<100 {
            if case .ready = model.workspaceGateState,
               model.selectedFolderID == FolderCatalog.rootFolderID,
               model.folderPageDocuments.count == 1 {
                loaded = true
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(loaded, "loadVault should load the folder page for root notes even when link graph sync is deferred")
        XCTAssertNil(model.lastError)
    }
}

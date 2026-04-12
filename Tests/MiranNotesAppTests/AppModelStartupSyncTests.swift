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
        let decision = AppModel.startupLinkGraphSyncDecision(
            noteCount: 2_000,
            noteLinkRelationshipCount: 100,
            hardThreshold: 2_000,
            historicalAverageMs: 40,
            budgetMs: 120
        )
        XCTAssertEqual(decision.mode, .immediate)
    }

    func testStartupLinkGraphSyncDecisionDeferredAboveThreshold() {
        let decision = AppModel.startupLinkGraphSyncDecision(
            noteCount: 2_001,
            noteLinkRelationshipCount: 100,
            hardThreshold: 2_000,
            historicalAverageMs: 40,
            budgetMs: 120
        )
        XCTAssertEqual(decision.mode, .deferred)
    }

    func testStartupLinkGraphSyncDecisionDeferredWhenHistoricalAverageOverBudget() {
        let decision = AppModel.startupLinkGraphSyncDecision(
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

        // Deferred sync should not block initial selection and note loading.
        var loaded = false
        for _ in 0..<100 {
            if model.selectedBaseName != nil, model.activeDocument != nil {
                loaded = true
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(loaded, "loadVault should load initial note even when link graph sync is deferred")
        XCTAssertNil(model.lastError)
    }
}

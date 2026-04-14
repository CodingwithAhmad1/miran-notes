import Foundation
import XCTest

@testable import MiranNotesApp

final class VaultCrashSafetyTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    func testRecoverPendingCommitsOnCleanVaultIsNoOp() throws {
        let vault = try tempVaultURL()
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let summary = try VaultCommitCoordinator.recoverPendingCommits(vaultRoot: vault)
        XCTAssertEqual(summary.resumedAndCompletedCount, 0)
        XCTAssertEqual(summary.discardedStagingCount, 0)
    }

    func testCorruptStagingDirectoryIsDiscarded() throws {
        let vault = try tempVaultURL()
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let pendingRoot = VaultPaths.pendingCommitsDirectory(vaultURL: vault)
        try FileManager.default.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        let bad = pendingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: bad.appendingPathComponent("vault-commit.json"))
        let summary = try VaultCommitCoordinator.recoverPendingCommits(vaultRoot: vault)
        XCTAssertEqual(summary.resumedAndCompletedCount, 0)
        XCTAssertEqual(summary.discardedStagingCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bad.path))
    }

    func testSimulatedMidCommitFailureThenRecoveryCompletesVault() async throws {
        let vault = try tempVaultURL()
        var coordinator = VaultCommitCoordinator()
        coordinator.testFailAfterRenameCount = 2
        let repo = NoteRepository(vaultURL: vault, commitCoordinator: coordinator)
        try await repo.ensureVault()

        do {
            _ = try await repo.createNote(named: "crash-test")
            XCTFail("expected simulated commit failure")
        } catch {
            XCTAssert(error is VaultCommitSimulationError, "unexpected error: \(error)")
        }

        let pendingRoot = VaultPaths.pendingCommitsDirectory(vaultURL: vault)
        let stagingBefore = try FileManager.default.contentsOfDirectory(atPath: pendingRoot.path)
        XCTAssertFalse(stagingBefore.isEmpty, "staging should remain for recovery")

        let summary = try VaultCommitCoordinator.recoverPendingCommits(vaultRoot: vault)
        XCTAssertEqual(summary.resumedAndCompletedCount, 1)

        let stagingAfter = try? FileManager.default.contentsOfDirectory(atPath: pendingRoot.path)
        XCTAssertEqual(stagingAfter?.count ?? 0, 0, "staging should be cleared after recovery")

        let fresh = NoteRepository(vaultURL: vault)
        let notes = try await fresh.listNotes()
        XCTAssertEqual(notes.count, 1)
    }

    func testSuccessfulSaveLeavesNoPendingStaging() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createNote(named: "clean")
        let pendingRoot = VaultPaths.pendingCommitsDirectory(vaultURL: vault)
        let children = (try? FileManager.default.contentsOfDirectory(atPath: pendingRoot.path)) ?? []
        XCTAssertEqual(children.count, 0)
    }
}

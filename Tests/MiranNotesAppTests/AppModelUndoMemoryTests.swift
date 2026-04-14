import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelUndoMemoryTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    /// Rapid single-character replaces coalesce into one undo step by default (300 ms window).
    func testCoalescingMergesRapidReplaceTextIntoFewerSteps() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "coalesce-note")

        let undoManager = UndoManager()
        let model = AppModel(repository: repo)
        model.setUndoManager(undoManager)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        for i in 0..<15 {
            model.apply(.replaceText(range: TextRange(start: i, length: 0), replacement: "x"))
        }
        XCTAssertLessThan(model.undoHistory.count, 15, "Coalescing should merge rapid typing steps")
        XCTAssertTrue(undoManager.canUndo)
    }

    func testUndoRedoAfterPruneStillConsistent() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "redo-note")

        let undoManager = UndoManager()
        let policy = UndoPolicy(maxUndoSteps: 5, coalesceReplaceTextWindowNanoseconds: 0)
        let model = AppModel(repository: repo, undoPolicy: policy)
        model.setUndoManager(undoManager)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        for i in 0..<8 {
            let ch = String(UnicodeScalar(97 + i)!)
            model.apply(.replaceText(range: TextRange(start: i, length: 0), replacement: ch))
        }
        XCTAssertLessThanOrEqual(model.undoHistory.count, 5)

        undoManager.undo()
        let afterUndo = model.activeDocument?.text ?? ""
        undoManager.redo()
        let afterRedo = model.activeDocument?.text ?? ""
        XCTAssertNotEqual(afterUndo, afterRedo)
        XCTAssertTrue(undoManager.canUndo)
    }

    /// Worst-case retained checkpoints: at most `maxUndoSteps + 1` document versions.
    func testRetentionEstimateBoundedAfterManyEditsNoCoalesce() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "mem-note")

        let policy = UndoPolicy(maxUndoSteps: 50, coalesceReplaceTextWindowNanoseconds: 0)
        let model = AppModel(repository: repo, undoPolicy: policy)
        model.setUndoManager(UndoManager())
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        guard let doc0 = model.activeDocument else {
            XCTFail("expected document")
            return
        }
        let perDoc = doc0.estimatedUndoMemoryBytes

        for i in 0..<60 {
            model.apply(.replaceText(range: TextRange(start: i, length: 0), replacement: "m"))
        }
        XCTAssertEqual(model.undoHistory.count, 50)

        let cap = (policy.maxUndoSteps + 1) * max(perDoc, model.activeDocument?.estimatedUndoMemoryBytes ?? 0)
        XCTAssertLessThanOrEqual(model.undoRetentionMemoryEstimateBytes, cap + 64_000)
    }

    func testLargeNoteUndoRetentionLinearInCheckpointCount() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "big-mem")

        let policy = UndoPolicy(maxUndoSteps: 20, coalesceReplaceTextWindowNanoseconds: 0)
        let model = AppModel(repository: repo, undoPolicy: policy)
        model.setUndoManager(UndoManager())
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        let big = String(repeating: "a", count: 100_000)
        model.apply([.replaceText(range: TextRange(start: 0, length: 0), replacement: big)], recordUndo: false)

        for i in 0..<25 {
            let pos = 50_000 + i
            model.apply(.replaceText(range: TextRange(start: pos, length: 0), replacement: "x"))
        }
        XCTAssertEqual(model.undoHistory.count, 20)

        let est = model.undoRetentionMemoryEstimateBytes
        XCTAssertGreaterThan(est, 1_000_000)
        let per = model.activeDocument?.estimatedUndoMemoryBytes ?? 0
        XCTAssertLessThanOrEqual(est, (policy.maxUndoSteps + 1) * per + 500_000)
    }
}

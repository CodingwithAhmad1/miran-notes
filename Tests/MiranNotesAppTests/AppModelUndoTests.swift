import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelUndoTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranNotesUndoTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testUndoStackHasAtMostMaxStepsAfter201Edits() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "undo-note")

        let undoManager = UndoManager()
        let noCoalesce = UndoPolicy(maxUndoSteps: 200, coalesceReplaceTextWindowNanoseconds: 0)
        let model = AppModel(repository: repo, undoPolicy: noCoalesce)
        model.setUndoManager(undoManager)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        for i in 0..<201 {
            model.apply(.replaceText(range: TextRange(start: i, length: 0), replacement: "x"))
        }

        XCTAssertLessThanOrEqual(model.undoHistory.count, 200, "Undo stack must not exceed 200 steps")
        XCTAssertGreaterThan(model.undoHistory.count, 0, "Undo history must not be empty after 201 edits")
    }

    func testUndoStackRetainsRecentEntriesAfterOverflow() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "undo-retain")

        let undoManager = UndoManager()
        let noCoalesce = UndoPolicy(maxUndoSteps: 200, coalesceReplaceTextWindowNanoseconds: 0)
        let model = AppModel(repository: repo, undoPolicy: noCoalesce)
        model.setUndoManager(undoManager)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        for i in 0..<201 {
            model.apply(.replaceText(range: TextRange(start: i, length: 0), replacement: "y"))
        }

        // The 200th-most-recent undo must still be functional (canUndo is true)
        XCTAssertTrue(undoManager.canUndo, "NSUndoManager must still have undo entries after pruning")
        XCTAssertEqual(model.undoHistory.count, 200, "undoHistory deque must have exactly 200 entries after pruning")
    }

    func testClearUndoStackResetsBothManagerAndHistory() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "undo-clear")

        let undoManager = UndoManager()
        let model = AppModel(repository: repo)
        model.setUndoManager(undoManager)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        model.apply(.replaceText(range: TextRange(start: 0, length: 0), replacement: "a"))
        model.apply(.replaceText(range: TextRange(start: 1, length: 0), replacement: "b"))
        XCTAssertTrue(undoManager.canUndo)

        // Switching notes calls clearUndoStack internally
        model.changeSelection(baseName: nil)
        await model.loadSelectedNote()

        XCTAssertFalse(undoManager.canUndo, "NSUndoManager must be cleared on note switch")
        XCTAssertEqual(model.undoHistory.count, 0, "undoHistory deque must be empty after clearUndoStack")
    }

    func testRemoveInterceptorStopsCallingIt() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "interceptor-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        var callCount = 0
        let token = model.registerCommandInterceptor { commands, _, _ in
            callCount += 1
            return commands
        }

        model.apply(.replaceText(range: TextRange(start: 0, length: 0), replacement: "a"))
        XCTAssertEqual(callCount, 1, "Interceptor should fire once before removal")

        model.removeCommandInterceptor(token)

        model.apply(.replaceText(range: TextRange(start: 1, length: 0), replacement: "b"))
        XCTAssertEqual(callCount, 1, "Interceptor must not fire after removal")
    }

    func testTwoLocalInterceptorsRunInRegistrationOrder() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "order-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        var order: [Int] = []
        _ = model.registerCommandInterceptor { commands, _, _ in
            order.append(1)
            return commands
        }
        _ = model.registerCommandInterceptor { commands, _, _ in
            order.append(2)
            return commands
        }

        _ = model.apply(.replaceText(range: TextRange(start: 0, length: 0), replacement: "x"))
        XCTAssertEqual(order, [1, 2], "Local interceptors should run in registration order after extension interceptors")
    }
}


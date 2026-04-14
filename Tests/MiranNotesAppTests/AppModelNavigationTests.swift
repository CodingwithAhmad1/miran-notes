import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelNavigationTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranNotesAppModelNav-\(UUID().uuidString)", isDirectory: true)
    }

    private func waitForAsync(_ maxAttempts: Int = 80, _ intervalMs: UInt64 = 25, _ condition: () -> Bool) async throws {
        for _ in 0..<maxAttempts {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(intervalMs))
        }
    }

    func testSwitchNotePersistsPendingDebouncedEditsWithoutWaitingForDebounce() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseA) = try await repo.createNote(named: "note-alpha")
        let (_, baseB) = try await repo.createNote(named: "note-beta")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseA
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "from-a"))

        model.changeSelection(baseName: baseB)
        try await waitForAsync { model.selectedBaseName == baseB && model.activeDocument?.text == "" }

        let textURLA = vault.appendingPathComponent("\(baseA).txt")
        let onDiskA = try String(contentsOf: textURLA, encoding: .utf8)
        XCTAssertEqual(onDiskA, "from-a")
    }

    func testCreateNoteFlushesPriorNoteBeforeSwitching() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseA) = try await repo.createNote(named: "prior-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseA
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "saved-before-new"))

        model.createNote()
        try await waitForAsync { model.selectedBaseName != baseA }

        let textURLA = vault.appendingPathComponent("\(baseA).txt")
        let onDiskA = try String(contentsOf: textURLA, encoding: .utf8)
        XCTAssertEqual(onDiskA, "saved-before-new")
    }

    func testRenameActiveNotePersistsUnsavedBufferBeforeRepositoryRename() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, oldBase) = try await repo.createNote(named: "rename-src")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = oldBase
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "buffer-text"))

        model.renameActiveNote(newTitle: "Renamed Title")
        try await waitForAsync { model.selectedBaseName != oldBase }

        guard let newBase = model.selectedBaseName else {
            XCTFail("Expected new base name after rename")
            return
        }
        let textURL = vault.appendingPathComponent("\(newBase).txt")
        let onDisk = try String(contentsOf: textURL, encoding: .utf8)
        XCTAssertEqual(onDisk, "buffer-text")
    }

    func testRapidNoteSwitchLoadsCleanSecondNoteAfterPriorFlush() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseA) = try await repo.createNote(named: "rapid-a")
        let (_, baseB) = try await repo.createNote(named: "rapid-b")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseA
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "x"))

        model.changeSelection(baseName: baseB)
        try await waitForAsync { model.selectedBaseName == baseB }

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(model.activeDocument?.text, "")
        let textURLB = vault.appendingPathComponent("\(baseB).txt")
        let onDiskB = try String(contentsOf: textURLB, encoding: .utf8)
        XCTAssertEqual(onDiskB, "")
    }

    func testChangeSelectionResolvesOutlineNoteTokenToRelativePath() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (doc, relPath) = try await repo.createNote(named: "token-test")
        let id = doc.metadata.noteID

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.changeSelection(baseName: "n:\(id.uuidString)")
        try await waitForAsync { model.selectedBaseName == relPath && model.activeDocument?.metadata.noteID == id }
        XCTAssertEqual(model.userAlert, .none)
    }

    func testEditorCursorOffsetResetOnNoteSwitch() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseA) = try await repo.createNote(named: "cursor-note-a")
        let (_, baseB) = try await repo.createNote(named: "cursor-note-b")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseA
        await model.loadSelectedNote()
        model.editorCursorOffset = 42

        model.changeSelection(baseName: baseB)
        // editorCursorOffset must be reset to 0 immediately when loadSelectedNote runs
        await model.loadSelectedNote()

        XCTAssertEqual(model.editorCursorOffset, 0, "editorCursorOffset must reset to 0 on note switch")
    }
}

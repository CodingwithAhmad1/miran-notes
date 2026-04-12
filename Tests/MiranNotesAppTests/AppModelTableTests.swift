import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelTableTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranTable-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - addTableToActiveNote

    func testAddTableToActiveNoteRegistersArtifactInActiveDocument() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "note-with-table")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()
        XCTAssertNotNil(model.activeDocument)

        model.addTableToActiveNote()
        // Give the async Task a chance to run.
        for _ in 0..<40 {
            if model.activeDocument?.metadata.artifacts.isEmpty == false { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(model.activeDocument?.metadata.artifacts.count, 1)
        XCTAssertEqual(model.activeDocument?.metadata.artifacts.first?.kind, .table)
    }

    func testAddTableToActiveNoteEventuallyPersistsToDisk() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "table-persist")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        model.addTableToActiveNote()
        // Wait for the artifact task + debounce autosave (>400 ms).
        try await Task.sleep(for: .milliseconds(600))

        // Reload from disk to verify persistence.
        let reloaded = try await repo.loadNote(baseName: baseName)
        XCTAssertFalse(reloaded.document.metadata.artifacts.isEmpty, "Table artifact should have been persisted by autosave")
    }

    func testSwitchingToNoteWithoutArtifactClearsTableEditorPayload() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, sourcePath) = try await repo.createNote(named: "with-table")
        let (_, plainPath) = try await repo.createNote(named: "no-table")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = sourcePath
        await model.loadSelectedNote()
        model.addTableToActiveNote()
        for _ in 0..<40 {
            if model.tableEditorPayload != nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNotNil(model.tableEditorPayload)

        model.selectedBaseName = plainPath
        await model.loadSelectedNote()
        XCTAssertNil(model.tableEditorPayload, "Table editor payload must reset when active note has no matching table artifact")
    }

    // MARK: - insertWikiLink cursor awareness

    func testInsertWikiLinkAtCursorOffsetInsertsAtCorrectPosition() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "link-cursor-test")
        let (_, targetBase) = try await repo.createNote(named: "target-note")
        let targetDoc = try await repo.loadNote(baseName: targetBase)
        let targetID = targetDoc.document.metadata.noteID

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        // Set cursor to position 0 (start of document).
        model.editorCursorOffset = 0
        model.insertWikiLink(to: targetID, displayText: "Target")

        let text = model.activeDocument?.text ?? ""
        XCTAssertTrue(text.hasPrefix("[[Target]]"), "Link inserted at cursor (offset 0) should appear at the start; got: \(text)")
    }

    func testInsertWikiLinkUsesDocumentEndWhenCursorOffsetIsAtEnd() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "link-end-test")
        let (_, targetBase) = try await repo.createNote(named: "another-target")
        let targetDoc = try await repo.loadNote(baseName: targetBase)
        let targetID = targetDoc.document.metadata.noteID

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        let beforeText = model.activeDocument?.text ?? ""
        model.editorCursorOffset = beforeText.utf16.count
        model.insertWikiLink(to: targetID, displayText: "Another")

        let text = model.activeDocument?.text ?? ""
        XCTAssertTrue(text.hasSuffix("[[Another]]"), "Link should be appended at end; got: \(text)")
    }

    // MARK: - apply(_:) return value

    func testApplyReturnsUpdatedDocument() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "apply-return-test")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        let returned = model.apply(.replaceText(
            range: TextRange(start: 0, length: 0),
            replacement: "Hello"
        ))

        XCTAssertEqual(returned.text, model.activeDocument?.text, "apply should return the same document that was set as activeDocument")
        XCTAssertTrue(returned.text.contains("Hello"))
    }

    func testCommandInterceptorCanTransformCommandBatch() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "interceptor-test")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        model.registerCommandInterceptor { commands, _, _ in
            commands.map { command in
                switch command {
                case let .replaceText(range, replacement):
                    return .replaceText(range: range, replacement: replacement.uppercased())
                default:
                    return command
                }
            }
        }

        _ = model.apply(.replaceText(range: TextRange(start: 0, length: 0), replacement: "hello"))
        XCTAssertEqual(model.activeDocument?.text, "HELLO")
    }
}

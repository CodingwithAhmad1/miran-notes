import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelSearchTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    private func waitForAsync(_ maxAttempts: Int = 80, _ intervalMs: UInt64 = 25, _ condition: () -> Bool) async throws {
        for _ in 0..<maxAttempts {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(intervalMs))
        }
    }

    func testBodySearchIndexRebuildAndFilterByBody() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseA) = try await repo.createNote(named: "alpha-note")
        let (_, baseB) = try await repo.createNote(named: "beta-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        try await waitForAsync { model.bodySearchIndex.count >= 2 }
        XCTAssertFalse(model.isBodySearchIndexBuilding)

        model.selectedBaseName = baseA
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "search-token-abc"))
        model.changeSelection(baseName: baseB)
        try await waitForAsync { model.selectedBaseName == baseB }

        await model.refreshNotes()
        let idA = try XCTUnwrap(model.noteSummaries.first { $0.relativePath == baseA }?.noteID)
        try await waitForAsync {
            model.bodySearchIndex[idA]?.contains("search-token") ?? false
        }

        model.noteQuery = "search-token"
        XCTAssertEqual(model.filteredNoteSummaries.count, 1)
        XCTAssertEqual(model.filteredNoteSummaries.first?.noteID, idA)
    }

    func testSearchSnippetForBodyMatch() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseA) = try await repo.createNote(named: "snippet-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        try await waitForAsync { model.bodySearchIndex.count >= 1 }
        XCTAssertFalse(model.isBodySearchIndexBuilding)

        model.selectedBaseName = baseA
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "preamble find-me-here epilogue"))
        model.changeSelection(baseName: nil)
        try await waitForAsync { model.selectedBaseName == nil }

        await model.refreshNotes()
        let idA = try XCTUnwrap(model.noteSummaries.first { $0.relativePath == baseA }?.noteID)
        try await waitForAsync {
            model.bodySearchIndex[idA]?.contains("find-me") ?? false
        }

        model.noteQuery = "find-me"
        let summary = try XCTUnwrap(model.filteredNoteSummaries.first)
        let snippet = model.searchSnippet(for: summary)
        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet!.contains("find-me"))
    }

    func testActiveDocumentOverridesIndexForUnsavedBodyMatch() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseA) = try await repo.createNote(named: "live-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        try await waitForAsync { model.bodySearchIndex.count >= 1 }
        XCTAssertFalse(model.isBodySearchIndexBuilding)

        model.selectedBaseName = baseA
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "unsaved-xyz"))

        model.noteQuery = "unsaved-xyz"
        XCTAssertEqual(model.filteredNoteSummaries.count, 1)
        XCTAssertEqual(model.filteredNoteSummaries.first?.relativePath, baseA)
    }

    func testBodySearchIndexNotBuildingAfterIndexReady() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createNote(named: "solo-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        try await waitForAsync { model.bodySearchIndex.count >= 1 }
        XCTAssertFalse(model.isBodySearchIndexBuilding)
    }
}

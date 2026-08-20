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

    func testBodySearchIndexRebuildsAfterRefresh() async throws {
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
    }

    func testVaultSearchMatchesNoteBodies() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseA) = try await repo.createNote(named: "alpha-note")
        _ = try await repo.createNote(named: "beta-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        try await waitForAsync { model.bodySearchIndex.count >= 2 }

        model.selectedBaseName = baseA
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "unique-body-xyz-123"))
        model.changeSelection(baseName: nil)
        try await waitForAsync { model.selectedBaseName == nil }

        await model.refreshNotes()
        let idA = try XCTUnwrap(model.noteSummaries.first { $0.relativePath == baseA }?.noteID)
        try await waitForAsync { model.bodySearchIndex[idA]?.contains("unique-body") ?? false }

        model.vaultSearchQuery = "unique-body"
        XCTAssertEqual(
            model.filteredNoteSummaries.map(\.relativePath),
            [baseA],
            "Vault search matches note bodies via the body search index."
        )
        XCTAssertEqual(
            model.searchMatchKind(
                try XCTUnwrap(model.noteSummaries.first { $0.relativePath == baseA }),
                queryLowercased: "unique-body"
            ),
            .body
        )

        model.vaultSearchQuery = "alpha"
        XCTAssertEqual(model.filteredNoteSummaries.count, 1)
        XCTAssertEqual(model.filteredNoteSummaries.first?.relativePath, baseA)
    }

    func testVaultSearchFiltersByRelativePath() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseA) = try await repo.createNote(named: "my-special-title")
        _ = try await repo.createNote(named: "other-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        try await waitForAsync { model.bodySearchIndex.count >= 1 }

        model.vaultSearchQuery = baseA
        XCTAssertEqual(model.filteredNoteSummaries.count, 1)
        XCTAssertEqual(model.filteredNoteSummaries.first?.relativePath, baseA)
    }

    func testSearchSnippetShowsBodyContextForBodyMatches() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseA) = try await repo.createNote(named: "snippet-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        try await waitForAsync { model.bodySearchIndex.count >= 1 }

        model.selectedBaseName = baseA
        await model.loadSelectedNote()
        model.apply(EditCommand.replaceText(range: TextRange(start: 0, length: 0), replacement: "preamble find-me-here epilogue"))
        model.changeSelection(baseName: nil)
        try await waitForAsync { model.selectedBaseName == nil }

        await model.refreshNotes()
        let summary = try XCTUnwrap(model.noteSummaries.first { $0.relativePath == baseA })
        try await waitForAsync { model.bodySearchIndex[summary.noteID]?.contains("find-me-here") ?? false }

        model.vaultSearchQuery = "find-me"
        let snippet = try XCTUnwrap(model.searchSnippet(for: summary))
        XCTAssertTrue(snippet.contains("find-me-here"))

        // Title-only queries with no body occurrence have no snippet.
        model.vaultSearchQuery = "snippet"
        XCTAssertNil(model.searchSnippet(for: summary))
    }

    func testVaultSearchMatchingNoteSummariesSortedByTitle() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createNote(named: "zebra-note")
        _ = try await repo.createNote(named: "apple-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        try await waitForAsync { model.bodySearchIndex.count >= 2 }

        model.vaultSearchQuery = "note"
        let matches = model.vaultSearchMatchingNoteSummaries
        XCTAssertEqual(matches.count, 2)
        let titles = matches.map(\.title)
        XCTAssertEqual(
            titles.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }),
            titles
        )
    }

    func testVaultSearchResultSubtitleIncludesFolderAndPath() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, path) = try await repo.createNote(named: "solo")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        let summary = try XCTUnwrap(model.noteSummaries.first { $0.relativePath == path })
        let subtitle = model.vaultSearchResultSubtitle(for: summary)
        XCTAssertTrue(subtitle.contains("Vault"))
        XCTAssertTrue(subtitle.contains(path))
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

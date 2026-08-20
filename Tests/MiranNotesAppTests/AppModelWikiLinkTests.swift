import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelWikiLinkTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    /// The autocomplete commit batch (remove `[[query`, insert linked `[[Title]]`) applied atomically.
    func testAutocompleteCommitBatchProducesLinkedToken() throws {
        let targetID = UUID()
        var metadata = NoteMetadata.empty
        let initial = "see [[pro and more"
        metadata.blocks = [
            Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: initial.utf16.count), level: nil, icon: nil)
        ]
        let doc = NoteDocument(text: initial, metadata: metadata)

        // The query token is "[[pro" at offset 4 (as WikiLinkQueryDetector would report mid-typing).
        let queryRange = TextRange(start: 4, length: 5)
        let batch: [EditCommand] = [
            .replaceText(range: queryRange, replacement: ""),
            .insertWikiLink(utf16Offset: 4, targetNoteID: targetID, displayText: "Project Plan")
        ]
        let result = batch.reduce(doc) { EditCommandEngine.apply($1, to: $0) }

        XCTAssertEqual(result.text, "see [[Project Plan]] and more")
        let link = try XCTUnwrap(result.metadata.links.first)
        XCTAssertEqual(link.targetNoteID, targetID)
        let ns = result.text as NSString
        XCTAssertEqual(ns.substring(with: NSRange(location: link.range.start, length: link.range.length)), "[[Project Plan]]")
    }

    func testWikiLinkMenuEntriesRankTitleOverPath() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createNote(named: "plan-of-record")
        _ = try await repo.createNote(named: "meeting-notes")

        let model = AppModel(repository: repo)
        await model.refreshNotes()

        let entries = model.wikiLinkMenuEntries(matching: "plan")
        guard case .note(_, let title, _)? = entries.first else {
            return XCTFail("expected a note entry first, got \(entries)")
        }
        XCTAssertTrue(title.lowercased().contains("plan"))
    }

    func testWikiLinkMenuEntriesExcludeCurrentNote() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, base) = try await repo.createNote(named: "self-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.changeSelection(baseName: base)
        for _ in 0..<80 {
            if model.selectedBaseName == base { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        let entries = model.wikiLinkMenuEntries(matching: "self")
        for entry in entries {
            if case .note(_, let title, _) = entry {
                XCTAssertNotEqual(title, "self-note", "current note must not be offered as its own link target")
            }
        }
    }

    func testOpenWikiLinkWithUnknownTargetAlerts() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let model = AppModel(repository: repo)
        await model.refreshNotes()

        model.openWikiLink(targetNoteID: UUID())
        guard case .message(let text) = model.userAlert else {
            return XCTFail("expected a plain alert for a dangling wiki link")
        }
        XCTAssertTrue(text.lowercased().contains("link"))
    }
}

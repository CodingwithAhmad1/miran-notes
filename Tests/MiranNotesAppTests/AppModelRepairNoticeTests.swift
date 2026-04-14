import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class AppModelRepairNoticeTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    func testRepairNoticeIsNilForValidNote() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, baseName) = try await repo.createNote(named: "clean-note")

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        XCTAssertNil(model.repairAdvisory)
    }

    func testRepairNoticeSetWhenBlocksDoNotCoverText() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (doc, baseName) = try await repo.createNote(named: "broken-meta")

        // Write text with more content than the block range covers.
        let textURL = vault.appendingPathComponent("\(baseName).txt")
        try "Hello world, this is extra text".write(to: textURL, atomically: true, encoding: .utf8)

        // Leave the metadata's block range pointing to only the first 0 bytes
        // by writing a meta with a zero-length block against the new longer text.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var badMeta = doc.metadata
        badMeta.blocks = [Block(
            id: badMeta.blocks[0].id,
            type: .paragraph,
            range: TextRange(start: 0, length: 0),
            level: nil,
            icon: nil
        )]
        let metaURL = vault.appendingPathComponent("\(baseName).meta.json")
        try encoder.encode(badMeta).write(to: metaURL)

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        XCTAssertNotNil(model.repairAdvisory, "Expected repair advisory for mismatched block ranges")
        XCTAssertEqual(model.repairAdvisory?.kind, .loadStructuralRepair)
    }

    func testRepairNoticeClearsWhenSwitchingToCleanNote() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (doc, brokenBase) = try await repo.createNote(named: "broken")
        let (_, cleanBase) = try await repo.createNote(named: "clean")

        let textURL = vault.appendingPathComponent("\(brokenBase).txt")
        try "Extra text".write(to: textURL, atomically: true, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var badMeta = doc.metadata
        badMeta.blocks = [Block(id: badMeta.blocks[0].id, type: .paragraph,
                                range: TextRange(start: 0, length: 0), level: nil, icon: nil)]
        let metaURL = vault.appendingPathComponent("\(brokenBase).meta.json")
        try encoder.encode(badMeta).write(to: metaURL)

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = brokenBase
        await model.loadSelectedNote()
        XCTAssertNotNil(model.repairAdvisory)

        model.changeSelection(baseName: cleanBase)
        for _ in 0..<80 {
            if model.selectedBaseName == cleanBase { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNil(model.repairAdvisory)
    }

    func testRepairNoticeIncludesWikiLinkAdvisoryWhenSyntaxPresentButLinksEmpty() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (doc, baseName) = try await repo.createNote(named: "wiki-note")

        // Write text with [[link]] syntax but keep metadata.links empty.
        let textURL = vault.appendingPathComponent("\(baseName).txt")
        let linkText = "See [[Some Note]] for details"
        try linkText.write(to: textURL, atomically: true, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var meta = doc.metadata
        meta.blocks = [Block(id: meta.blocks[0].id, type: .paragraph,
                             range: TextRange(start: 0, length: linkText.utf16.count), level: nil, icon: nil)]
        meta.links = []
        let metaURL = vault.appendingPathComponent("\(baseName).meta.json")
        try encoder.encode(meta).write(to: metaURL)

        let model = AppModel(repository: repo)
        await model.refreshNotes()
        model.selectedBaseName = baseName
        await model.loadSelectedNote()

        guard let advisory = model.repairAdvisory else {
            XCTFail("Expected repair advisory for missing link metadata")
            return
        }
        XCTAssertEqual(advisory.kind, .wikiLinksMissingMetadata)
        XCTAssertTrue(advisory.explanation.lowercased().contains("link"))
    }
}

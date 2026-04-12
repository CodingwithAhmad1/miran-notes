import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class LinkGraphDirtyFlagTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranNotesLinkGraphTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testSaveWithUnchangedLinksDoesNotWriteLinkGraph() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let noteID = UUID()
        let targetID = UUID()
        // First save WITH a link so link-graph.json is created
        let doc = NoteDocument(
            text: "hello",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 5), level: nil, icon: nil)],
                spans: [],
                links: [NoteLink(range: TextRange(start: 0, length: 5), targetNoteID: targetID)]
            )
        )
        try await repo.save(doc, asBaseName: "unchanged-links-note")

        let graphURL = VaultPaths.linkGraphURL(vaultURL: vault)
        let mtimeBefore = try FileManager.default.attributesOfItem(atPath: graphURL.path)[.modificationDate] as? Date

        // Small sleep to ensure mtime would differ if the file were rewritten
        try await Task.sleep(for: .milliseconds(50))

        // Save IDENTICAL document again — link graph must not be rewritten
        try await repo.save(doc, asBaseName: "unchanged-links-note")

        let mtimeAfter = try FileManager.default.attributesOfItem(atPath: graphURL.path)[.modificationDate] as? Date

        XCTAssertEqual(
            mtimeBefore?.timeIntervalSinceReferenceDate ?? 0,
            mtimeAfter?.timeIntervalSinceReferenceDate ?? 0,
            accuracy: 0.001,
            "link-graph.json must not be rewritten when links are unchanged"
        )
    }

    func testSaveWithNewLinkWritesLinkGraph() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let noteID = UUID()
        let targetID = UUID()
        let doc = NoteDocument(
            text: "hello",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 5), level: nil, icon: nil)],
                spans: [],
                links: [NoteLink(range: TextRange(start: 0, length: 5), targetNoteID: targetID)]
            )
        )
        try await repo.save(doc, asBaseName: "linked-note")

        let graph = try await repo.loadLinkGraph()
        XCTAssertNotNil(
            graph.outgoing[noteID],
            "link-graph must contain outgoing entry for the saved note"
        )
        XCTAssertTrue(
            graph.outgoing[noteID]?.contains(targetID) == true,
            "graph must record the link target"
        )
    }

    func testLinkGraphIsDirtyAfterSetOutgoing() {
        var graph = LinkGraph()
        XCTAssertFalse(graph.isDirty, "fresh graph must not be dirty")
        graph.setOutgoing(from: UUID(), to: [UUID()])
        XCTAssertTrue(graph.isDirty, "graph must be dirty after setOutgoing")
    }

    func testLinkGraphIsDirtyNotPersistedInCodable() throws {
        var graph = LinkGraph()
        graph.setOutgoing(from: UUID(), to: [UUID()])
        XCTAssertTrue(graph.isDirty)
        let data = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(LinkGraph.self, from: data)
        XCTAssertFalse(decoded.isDirty, "isDirty must always be false after decode")
    }
}

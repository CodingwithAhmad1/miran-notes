import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class BacklinkInverseResolutionTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranNotesBacklink-\(UUID().uuidString)", isDirectory: true)
    }

    func testBacklinksResolvedViaPersistedLinkGraphAndRelationshipIndex() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let targetID = UUID()
        let sourceID = UUID()

        let targetMeta = NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
            noteID: targetID,
            blocks: [
                Block(id: "b1", type: .paragraph, range: TextRange(start: 0, length: 1), level: nil, icon: nil)
            ],
            spans: [],
            links: []
        )
        let targetDoc = NoteDocument(text: "x", metadata: targetMeta)
        try await repo.save(targetDoc, asRelativePath: "target-note")

        let sourceMeta = NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
            noteID: sourceID,
            blocks: [
                Block(id: "b1", type: .paragraph, range: TextRange(start: 0, length: 20), level: nil, icon: nil)
            ],
            spans: [],
            links: [
                NoteLink(range: TextRange(start: 0, length: 10), targetNoteID: targetID, label: nil)
            ]
        )
        let sourceDoc = NoteDocument(text: "link to target", metadata: sourceMeta)
        try await repo.save(sourceDoc, asRelativePath: "source-note")

        let graph = try await repo.loadLinkGraph()
        XCTAssertTrue(graph.backlinks(to: targetID).contains(sourceID))

        let relationshipURL = VaultPaths.relationshipIndexURL(vaultURL: vault)
        let relData = try Data(contentsOf: relationshipURL)
        let rel = try JSONDecoder().decode(RelationshipIndex.self, from: relData)
        XCTAssertTrue(
            rel.relationships.contains { relationship in
                relationship.sourceNoteID == sourceID
                    && relationship.relationshipKind == "noteLink"
                    && relationship.target == .note(noteID: targetID)
            }
        )
    }
}

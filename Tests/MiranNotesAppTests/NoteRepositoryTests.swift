import CryptoKit
import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class NoteRepositoryTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranNotesTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testValidateBaseNameRejectsTraversalAndSeparators() throws {
        XCTAssertThrowsError(try NoteRepository.validateBaseName("")) { error in
            XCTAssertEqual(error as? NoteRepositoryError, .invalidRelativePath(""))
        }
        XCTAssertThrowsError(try NoteRepository.validateBaseName("..")) { error in
            XCTAssertEqual(error as? NoteRepositoryError, .invalidRelativePath(".."))
        }
        XCTAssertThrowsError(try NoteRepository.validateBaseName(".hidden")) { error in
            XCTAssertEqual(error as? NoteRepositoryError, .invalidRelativePath(".hidden"))
        }
        XCTAssertThrowsError(try NoteRepository.validateBaseName("a/b")) { error in
            XCTAssertEqual(error as? NoteRepositoryError, .invalidRelativePath("a/b"))
        }
        XCTAssertNoThrow(try NoteRepository.validateBaseName("hello-world"))
        XCTAssertThrowsError(try NoteRepository.validateBaseName("bad\u{0}name")) { error in
            XCTAssertEqual(error as? NoteRepositoryError, .invalidRelativePath("bad\u{0}name"))
        }
    }

    func testCreateNoteUsesNumericSuffixWhenSlugCollides() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let (_, firstName) = try await repo.createNote(named: "note")
        XCTAssertEqual(firstName, "note")
        let (_, secondName) = try await repo.createNote(named: "note")
        XCTAssertEqual(secondName, "note-2")
        XCTAssertNotEqual(firstName, secondName)

        let urls = try FileManager.default.contentsOfDirectory(at: vault, includingPropertiesForKeys: nil)
        let txt = urls.filter { $0.pathExtension.lowercased() == "txt" }
        XCTAssertEqual(txt.count, 2)
    }

    func testLoadNoteRepairsStaleMetadataAgainstNewText() async throws {
        let vault = try tempVaultURL()
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let base = "stale-meta"
        let textURL = vault.appendingPathComponent("\(base).txt")
        let metaURL = vault.appendingPathComponent("\(base).meta.json")

        try "hello world".write(to: textURL, atomically: true, encoding: .utf8)
        let staleMeta = NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
            noteID: UUID(),
            blocks: [
                Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil),
                Block(id: "b", type: .paragraph, range: TextRange(start: 3, length: 2), level: nil, icon: nil)
            ],
            spans: []
        )
        let data = try JSONEncoder().encode(staleMeta)
        try data.write(to: metaURL)

        let repo = NoteRepository(vaultURL: vault)
        let result = try await repo.loadNote(baseName: base)
        let report = NoteIntegrity.check(document: result.document)
        XCTAssertTrue(report.isValid, "\(report.issues)")
        XCTAssertEqual(result.document.text, "hello world")
    }

    func testSaveAndLoadRoundTrip() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let base = "round-trip"
        let noteID = UUID()
        let metadata = NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
            noteID: noteID,
            blocks: [
                Block(
                    id: "b1",
                    type: .paragraph,
                    range: TextRange(start: 0, length: "hello".utf16.count),
                    level: nil,
                    icon: nil
                )
            ],
            spans: []
        )
        let original = NoteDocument(text: "hello", metadata: metadata)
        try await repo.save(original, asBaseName: base)
        let result = try await repo.loadNote(baseName: base)
        XCTAssertEqual(result.document.text, "hello")
        XCTAssertTrue(NoteIntegrity.check(document: result.document).isValid)
    }

    func testRevisionTokenChangesAfterMetadataMutation() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let noteID = UUID()
        let base = "revision-token"
        let metadata = NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
            noteID: noteID,
            blocks: [
                Block(id: "b1", type: .paragraph, range: TextRange(start: 0, length: 5), level: nil, icon: nil)
            ],
            spans: []
        )
        let original = NoteDocument(text: "hello", metadata: metadata)
        try await repo.save(original, asBaseName: base)
        let firstToken = try await repo.noteRevisionToken(relativePath: base)
        XCTAssertNotNil(firstToken)

        var changed = original
        changed.metadata.properties["tag"] = "blue"
        try await repo.save(changed, asBaseName: base)
        let secondToken = try await repo.noteRevisionToken(relativePath: base)

        XCTAssertNotNil(secondToken)
        XCTAssertNotEqual(firstToken, secondToken)
    }

    func testNoteTextFileSHA256MatchesFileBytes() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, base) = try await repo.createNote(named: "sha-note")
        let textURL = vault.appendingPathComponent("\(base).txt")
        let data = try Data(contentsOf: textURL)
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let h = try await repo.noteTextFileSHA256(relativePath: base)
        XCTAssertEqual(h, expected)
    }

    func testListNotesRepairsMissingMetadataSidecar() async throws {
        let vault = try tempVaultURL()
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let textURL = vault.appendingPathComponent("orphan.txt")
        try "orphan".write(to: textURL, atomically: true, encoding: .utf8)

        let repo = NoteRepository(vaultURL: vault)
        try await repo.reconcileManifest()
        let notes = try await repo.listNotes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.relativePath, "orphan")

        let metaURL = vault.appendingPathComponent("orphan.meta.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path))
    }

    func testListNotesWithoutReconcileDoesNotPickUpLooseTextFiles() async throws {
        let vault = try tempVaultURL()
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "solo".write(to: vault.appendingPathComponent("solo.txt"), atomically: true, encoding: .utf8)
        let repo = NoteRepository(vaultURL: vault)
        let notes = try await repo.listNotes()
        XCTAssertEqual(notes.count, 0)
        try await repo.reconcileManifest()
        let after = try await repo.listNotes()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.relativePath, "solo")
    }

    func testSaveLinkGraphDoesNotRewriteManifestWhenOnlyGraphChanges() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        _ = try await repo.createNote(named: "manifest-stable")
        let manifestURL = VaultPaths.manifestURL(vaultURL: vault)
        let before = try Data(contentsOf: manifestURL)
        try await Task.sleep(for: .milliseconds(50))
        var graph = try await repo.loadLinkGraph()
        graph.setOutgoing(from: UUID(), to: [UUID()])
        try await repo.saveLinkGraph(graph)
        let after = try Data(contentsOf: manifestURL)
        XCTAssertEqual(before, after, "manifest.json must not be rewritten when VaultManifest has no changes")
    }

    func testSynchronizeLinkGraphFromRelationshipsRepairsMissingGraphEdges() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()

        let targetID = UUID()
        let sourceID = UUID()
        let target = NoteDocument(
            text: "target",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: targetID,
                blocks: [Block(id: "b1", type: .paragraph, range: TextRange(start: 0, length: 6), level: nil, icon: nil)],
                spans: []
            )
        )
        try await repo.save(target, asRelativePath: "target")

        let source = NoteDocument(
            text: "link",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: sourceID,
                blocks: [Block(id: "b1", type: .paragraph, range: TextRange(start: 0, length: 4), level: nil, icon: nil)],
                spans: [],
                links: [NoteLink(range: TextRange(start: 0, length: 4), targetNoteID: targetID, label: nil)]
            )
        )
        try await repo.save(source, asRelativePath: "source")

        try await repo.saveLinkGraph(LinkGraph())
        var emptyGraph = try await repo.loadLinkGraph()
        XCTAssertTrue(emptyGraph.outgoing.isEmpty)

        _ = try await repo.synchronizeLinkGraphFromRelationships()
        emptyGraph = try await repo.loadLinkGraph()
        XCTAssertEqual(emptyGraph.outgoing[sourceID], [targetID])
    }

    func testSaveUpdatesRelationshipAndPathIndexes() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let noteID = UUID()
        let targetID = UUID()
        var metadata = NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
            noteID: noteID,
            blocks: [
                Block(id: "b1", type: .paragraph, range: TextRange(start: 0, length: 5), level: nil, icon: nil)
            ],
            spans: [],
            links: [
                NoteLink(range: TextRange(start: 0, length: 5), targetNoteID: targetID, label: "target")
            ]
        )
        let artifactID = UUID()
        metadata.artifacts = [
            EmbeddedArtifact(id: artifactID, kind: .table, relativePath: "tables/\(artifactID.uuidString.lowercased()).jsonl")
        ]
        let doc = NoteDocument(text: "hello", metadata: metadata)
        try await repo.save(doc, asBaseName: "index-check")

        let relationshipURL = VaultPaths.relationshipIndexURL(vaultURL: vault)
        let pathIndexURL = VaultPaths.pathIndexURL(vaultURL: vault)
        let folderCatalogURL = VaultPaths.folderCatalogURL(vaultURL: vault)
        XCTAssertTrue(FileManager.default.fileExists(atPath: relationshipURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pathIndexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderCatalogURL.path))

        let relData = try Data(contentsOf: relationshipURL)
        let pathData = try Data(contentsOf: pathIndexURL)
        let decoder = JSONDecoder()
        let rel = try decoder.decode(RelationshipIndex.self, from: relData)
        let path = try decoder.decode(PathIndex.self, from: pathData)

        XCTAssertTrue(rel.relationships.contains { relationship in
            relationship.sourceNoteID == noteID && relationship.relationshipKind == "noteLink"
        })
        XCTAssertTrue(rel.relationships.contains { relationship in
            relationship.sourceNoteID == noteID && relationship.relationshipKind == "artifactLink"
        })
        XCTAssertTrue(path.entries.contains { $0.noteID == noteID && $0.relativePath == "index-check" })
    }

    func testSlugifyLongTitleIsCapedAt200Bytes() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let longTitle = String(repeating: "a", count: 300)
        let (_, baseName) = try await repo.createNote(named: longTitle)
        XCTAssertLessThanOrEqual(baseName.utf8.count, 200, "baseName must be ≤ 200 UTF-8 bytes")
        let textURL = vault.appendingPathComponent("\(baseName).txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: textURL.path), "File must exist after createNote with long title")
    }

    func testSlugifyMultibyteCharactersCapedAtBoundary() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        // Each Japanese character is 3 bytes in UTF-8; 100 chars = 300 bytes — must be truncated
        let longTitle = String(repeating: "あ", count: 100)
        let (_, baseName) = try await repo.createNote(named: longTitle)
        XCTAssertLessThanOrEqual(baseName.utf8.count, 200)
        // Result should be valid UTF-8 (no split multi-byte sequences)
        XCTAssertNotNil(String(baseName.utf8), "baseName must be valid UTF-8 after truncation")
    }

    func testReadRawNoteTextAndBuildBodySearchIndex() async throws {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        try await repo.ensureVault()
        let (_, base) = try await repo.createNote(named: "index-body")
        let emptyRaw = try await repo.readRawNoteText(relativePath: base)
        XCTAssertEqual(emptyRaw, "")

        let textURL = vault.appendingPathComponent("\(base).txt")
        try "indexed-body-text".write(to: textURL, atomically: true, encoding: .utf8)

        let raw = try await repo.readRawNoteText(relativePath: base)
        XCTAssertEqual(raw, "indexed-body-text")

        let index = try await repo.buildBodySearchIndex()
        let manifest = try await repo.loadManifest()
        let id = try XCTUnwrap(manifest.entry(relativePath: base)?.noteID)
        XCTAssertEqual(index[id], "indexed-body-text")
    }
}

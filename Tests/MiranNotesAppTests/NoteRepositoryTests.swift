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
            XCTAssertEqual(error as? NoteRepositoryError, .invalidBaseName(""))
        }
        XCTAssertThrowsError(try NoteRepository.validateBaseName("..")) { error in
            XCTAssertEqual(error as? NoteRepositoryError, .invalidBaseName(".."))
        }
        XCTAssertThrowsError(try NoteRepository.validateBaseName(".hidden")) { error in
            XCTAssertEqual(error as? NoteRepositoryError, .invalidBaseName(".hidden"))
        }
        XCTAssertThrowsError(try NoteRepository.validateBaseName("a/b")) { error in
            XCTAssertEqual(error as? NoteRepositoryError, .invalidBaseName("a/b"))
        }
        XCTAssertNoThrow(try NoteRepository.validateBaseName("hello-world"))
        XCTAssertThrowsError(try NoteRepository.validateBaseName("bad\u{0}name")) { error in
            XCTAssertEqual(error as? NoteRepositoryError, .invalidBaseName("bad\u{0}name"))
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
        let original = NoteDocument(id: noteID, text: "hello", metadata: metadata)
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
        let original = NoteDocument(id: noteID, text: "hello", metadata: metadata)
        try await repo.save(original, asBaseName: base)
        let firstToken = try await repo.noteRevisionToken(baseName: base)
        XCTAssertNotNil(firstToken)

        var changed = original
        changed.metadata.properties["tag"] = "blue"
        try await repo.save(changed, asBaseName: base)
        let secondToken = try await repo.noteRevisionToken(baseName: base)

        XCTAssertNotNil(secondToken)
        XCTAssertNotEqual(firstToken, secondToken)
    }

    func testListNotesRepairsMissingMetadataSidecar() async throws {
        let vault = try tempVaultURL()
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let textURL = vault.appendingPathComponent("orphan.txt")
        try "orphan".write(to: textURL, atomically: true, encoding: .utf8)

        let repo = NoteRepository(vaultURL: vault)
        let notes = try await repo.listNotes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.baseName, "orphan")

        let metaURL = vault.appendingPathComponent("orphan.meta.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path))
    }
}

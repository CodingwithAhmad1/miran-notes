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
            blocks: [
                Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil),
                Block(id: "b", type: .paragraph, range: TextRange(start: 3, length: 2), level: nil, icon: nil)
            ],
            spans: []
        )
        let data = try JSONEncoder().encode(staleMeta)
        try data.write(to: metaURL)

        let repo = NoteRepository(vaultURL: vault)
        let loaded = try await repo.loadNote(baseName: base)
        let report = NoteIntegrity.check(document: loaded)
        XCTAssertTrue(report.isValid, "\(report.issues)")
        XCTAssertEqual(loaded.text, "hello world")
    }
}

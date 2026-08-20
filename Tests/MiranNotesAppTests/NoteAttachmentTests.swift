import Foundation
import XCTest

@testable import MiranNotesApp

final class NoteAttachmentTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    private func makeSourceFile(named name: String, contents: String = "data") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranAttachSrc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testCopyInDeduplicatesNames() throws {
        let vault = try tempVaultURL()
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let store = NoteAttachmentStore(vaultURL: vault)
        let noteID = UUID()

        let first = try store.copyIn(fileAt: try makeSourceFile(named: "report.pdf"), noteID: noteID)
        let second = try store.copyIn(fileAt: try makeSourceFile(named: "report.pdf"), noteID: noteID)
        XCTAssertEqual(first, "report.pdf")
        XCTAssertEqual(second, "report-2.pdf")
        XCTAssertEqual(store.listFilenames(noteID: noteID), ["report-2.pdf", "report.pdf"])
        XCTAssertTrue(store.exists(noteID: noteID, filename: "report.pdf"))

        store.delete(noteID: noteID, filename: "report.pdf")
        XCTAssertFalse(store.exists(noteID: noteID, filename: "report.pdf"))
    }

    func testSanitizedFilenameStripsBracketsAndSeparators() {
        XCTAssertEqual(NoteAttachmentStore.sanitizedFilename("a/b[c]:d.txt"), "a-b(c)-d.txt")
        XCTAssertEqual(NoteAttachmentStore.sanitizedFilename("   "), "attachment")
    }

    func testTokenScannerFindsTokens() {
        let text = "see [attachment: report.pdf] and [attachment: notes v2.txt] end"
        let tokens = AttachmentTokenScanner.tokens(in: text)
        XCTAssertEqual(tokens.map(\.filename), ["report.pdf", "notes v2.txt"])
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: tokens[0].range), "[attachment: report.pdf]")
    }

    func testTokenScannerIgnoresMalformedTokens() {
        XCTAssertTrue(AttachmentTokenScanner.tokens(in: "[attachment: ]").isEmpty)
        XCTAssertTrue(AttachmentTokenScanner.tokens(in: "[attachment: a\nb]").isEmpty)
        XCTAssertTrue(AttachmentTokenScanner.tokens(in: "[attach: x.png]").isEmpty)
    }

    func testTokenTextRoundTripsThroughScanner() {
        let token = AttachmentTokenScanner.tokenText(filename: "photo.jpg")
        let scanned = AttachmentTokenScanner.tokens(in: "prefix \(token) suffix")
        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(scanned[0].filename, "photo.jpg")
    }
}

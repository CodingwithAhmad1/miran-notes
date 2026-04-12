import XCTest
@testable import MiranNotesCore

final class EditEngineRegressionTests: XCTestCase {
    private func baselineDocument(text: String) -> NoteDocument {
        let noteID = UUID()
        return NoteDocument(
            id: noteID,
            text: text,
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(
                        id: "b0",
                        type: .paragraph,
                        range: TextRange(start: 0, length: text.utf16.count),
                        level: nil,
                        icon: nil
                    )
                ],
                spans: []
            )
        )
    }

    func testRandomReplaceTextSequenceMaintainsIntegrity() {
        let inserts = ["", "a", "bc", "\n", "😀"]
        var doc = baselineDocument(text: "hello")

        for i in 0..<500 {
            let len = doc.text.utf16.count
            let loc = len == 0 ? 0 : (i * 17_971 + 11) % (len + 1)
            let maxDel = max(0, len - loc)
            let del = maxDel == 0 ? 0 : (i * 31 + 7) % (maxDel + 1)
            let ins = inserts[i % inserts.count]
            doc = EditCommandEngine.apply(
                .replaceText(range: TextRange(start: loc, length: del), replacement: ins),
                to: doc
            )
            let report = NoteIntegrity.check(document: doc)
            XCTAssertTrue(report.isValid, "iteration \(i) text=\(doc.text.debugDescription) issues=\(report.issues)")
        }
    }

    func testSpanAdjustsAndStaysValidWithEdits() {
        var doc = baselineDocument(text: "hello world")
        doc.metadata.spans = [Span(range: TextRange(start: 0, length: 5), style: .bold)]

        doc = EditCommandEngine.apply(
            .replaceText(range: TextRange(start: 0, length: 0), replacement: "X"),
            to: doc
        )
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)

        doc = EditCommandEngine.apply(
            .replaceText(range: TextRange(start: 0, length: 14), replacement: ""),
            to: doc
        )
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
    }

    func testSplitBlockMaintainsIntegrity() {
        var doc = baselineDocument(text: "line1\nline2")
        doc = EditCommandEngine.apply(.splitBlock(blockID: "b0", atOffset: 6), to: doc)
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
    }

    func testToggleSpanBeyondTextIsClampedAndValid() {
        var doc = baselineDocument(text: "hi")
        doc = EditCommandEngine.apply(
            .toggleSpanStyle(range: TextRange(start: 0, length: 99), style: .bold),
            to: doc
        )
        let report = NoteIntegrity.check(document: doc)
        XCTAssertTrue(report.isValid, "\(report.issues)")
        XCTAssertEqual(doc.metadata.spans.count, 1)
        XCTAssertEqual(doc.metadata.spans[0].range, TextRange(start: 0, length: 2))
    }
}

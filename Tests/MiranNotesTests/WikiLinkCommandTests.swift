import XCTest
@testable import MiranNotesCore

final class WikiLinkCommandTests: XCTestCase {
    func testInsertWikiLinkMaintainsIntegrity() {
        let noteID = UUID()
        let target = UUID()
        var doc = NoteDocument(
            text: "hi",
            metadata: NoteMetadata(
                schemaVersion: 2,
                noteID: noteID,
                blocks: [
                    Block(id: "b", type: .paragraph, range: TextRange(start: 0, length: 2), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        doc = EditCommandEngine.apply(
            .insertWikiLink(utf16Offset: 2, targetNoteID: target, displayText: "Other"),
            to: doc
        )
        let report = NoteIntegrity.check(document: doc)
        XCTAssertTrue(report.isValid, "\(report.issues)")
        XCTAssertTrue(doc.text.contains("[[Other]]"))
        XCTAssertEqual(doc.metadata.links.count, 1)
        XCTAssertEqual(doc.metadata.links[0].targetNoteID, target)
    }
}

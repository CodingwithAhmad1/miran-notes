import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class NoteMarkdownExporterAndTagsTests: XCTestCase {
    private func block(_ id: String, _ type: BlockType, _ start: Int, _ length: Int, level: Int? = nil) -> Block {
        Block(id: id, type: type, range: TextRange(start: start, length: length), level: level, icon: nil)
    }

    func testMarkdownExportGolden() {
        let text = "Title\nHello world\nitem one\ncode line\nquote me"
        var metadata = NoteMetadata.empty
        metadata.blocks = [
            block("b0", .heading, 0, 6, level: 1),      // "Title\n"
            block("b1", .paragraph, 6, 12),              // "Hello world\n"
            block("b2", .listItem, 18, 9),               // "item one\n"
            block("b3", .code, 27, 10),                  // "code line\n"
            block("b4", .callout, 37, 8)                 // "quote me"
        ]
        // Bold "world" (offset 12..17)
        metadata.spans = [Span(range: TextRange(start: 12, length: 5), style: .bold)]
        let doc = NoteDocument(text: text, metadata: metadata)

        let markdown = NoteMarkdownExporter.markdown(for: doc)
        XCTAssertEqual(
            markdown,
            """
            # Title

            Hello **world**

            - item one

            ```
            code line
            ```

            > quote me

            """
        )
    }

    func testDividerExportsAsRule() {
        var metadata = NoteMetadata.empty
        metadata.blocks = [block("b0", .divider, 0, 3)]
        let doc = NoteDocument(text: "---", metadata: metadata)
        XCTAssertEqual(NoteMarkdownExporter.markdown(for: doc), "---\n")
    }

    // MARK: - Tags

    func testTagParsingNormalizesAndDeduplicates() {
        XCTAssertEqual(NoteTags.parseList(" Swift, #ideas , swift,, PROJECT "), ["swift", "ideas", "project"])
        XCTAssertNil(NoteTags.serialized([]))
        XCTAssertEqual(NoteTags.serialized(["#Swift", "swift", "Notes "]), "swift,notes")
    }

    func testSetPropertyCommandRoundTrip() {
        var metadata = NoteMetadata.empty
        metadata.blocks = [block("b0", .paragraph, 0, 2)]
        var doc = NoteDocument(text: "hi", metadata: metadata)

        doc = EditCommandEngine.apply(.setProperty(key: "tags", value: "alpha,beta"), to: doc)
        XCTAssertEqual(doc.metadata.properties["tags"], "alpha,beta")
        XCTAssertEqual(NoteTags.parse(doc.metadata.properties), ["alpha", "beta"])

        doc = EditCommandEngine.apply(.setProperty(key: "tags", value: nil), to: doc)
        XCTAssertNil(doc.metadata.properties["tags"])
    }
}

import XCTest
@testable import MiranNotesCore

final class EditEnginePerformanceTests: XCTestCase {
    private func makeDocument(text: String, spans: [Span] = []) -> NoteDocument {
        let noteID = UUID()
        var doc = NoteDocument(
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
                spans: spans
            )
        )
        doc.metadata.spans = spans
        return doc
    }

    /// Baseline: 500 sequential single-character inserts on a 10,000-character document.
    /// Exercises `adjustBlocks`, `SpanAdjuster`, and `LinkAdjuster` on a large buffer.
    func testSequentialInsertsOnLargeDocument() {
        let longText = String(repeating: "a", count: 10_000)
        var doc = makeDocument(text: longText)

        measure {
            for i in 0..<500 {
                let len = doc.text.utf16.count
                let loc = len == 0 ? 0 : (i * 17_971 + 11) % (len + 1)
                doc = EditCommandEngine.apply(
                    .replaceText(range: TextRange(start: loc, length: 0), replacement: "x"),
                    to: doc
                )
            }
        }
    }

    /// Baseline: 200 replacements on a document carrying 50 bold spans.
    /// Exercises `SpanAdjuster` recomputation alongside `adjustBlocks` on every edit.
    func testSequentialReplacesWithSpans() {
        let text = String(repeating: "abcde", count: 200)
        let spanCount = 50
        let segmentLength = text.utf16.count / (spanCount * 2)
        let spans: [Span] = (0..<spanCount).map { i in
            let start = i * segmentLength * 2
            return Span(
                range: TextRange(start: start, length: min(segmentLength, text.utf16.count - start)),
                style: .bold
            )
        }
        var doc = makeDocument(text: text, spans: spans)

        measure {
            for i in 0..<200 {
                let len = doc.text.utf16.count
                let loc = len == 0 ? 0 : (i * 13_331 + 7) % (len + 1)
                let delMax = min(3, len - loc)
                let del = delMax <= 0 ? 0 : (i * 5 + 1) % (delMax + 1)
                doc = EditCommandEngine.apply(
                    .replaceText(range: TextRange(start: loc, length: del), replacement: "z"),
                    to: doc
                )
            }
        }
    }
}

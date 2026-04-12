import XCTest
@testable import MiranNotesCore

final class SpanAndBlockAdjustmentTests: XCTestCase {
    // MARK: - SpanAdjuster

    func testSpanShiftsWhenEditIsAfterSpan() {
        let blocks = [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 10), level: nil, icon: nil)
        ]
        let spans = [Span(range: TextRange(start: 0, length: 3), style: .bold)]
        let out = SpanAdjuster.adjust(
            spans: spans,
            replacedRange: TextRange(start: 5, length: 0),
            replacementUTF16Length: 2,
            constrainedTo: blocks
        )
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].range, TextRange(start: 0, length: 3))
    }

    func testSpanSplitsAcrossTwoBlocks() {
        let blocks = [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 5), level: nil, icon: nil),
            Block(id: "b", type: .paragraph, range: TextRange(start: 5, length: 5), level: nil, icon: nil)
        ]
        let spans = [Span(range: TextRange(start: 2, length: 8), style: .italic)]
        let out = SpanAdjuster.adjust(
            spans: spans,
            replacedRange: TextRange(start: 10, length: 0),
            replacementUTF16Length: 0,
            constrainedTo: blocks
        )
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].range, TextRange(start: 2, length: 3))
        XCTAssertEqual(out[1].range, TextRange(start: 5, length: 5))
    }

    // MARK: - adjustBlocks (via EditCommandEngine)

    func testAdjustBlocksShiftsFollowingBlockStarts() {
        let blocks = [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 4), level: nil, icon: nil),
            Block(id: "b", type: .paragraph, range: TextRange(start: 4, length: 4), level: nil, icon: nil)
        ]
        // Pre-edit layout was "aaaabbbb"; one UTF-16 code unit inserted at offset 2 → "aaXaaabbbb".
        let text = "aaXaaabbbb"
        let ctx = NoteMetadata(schemaVersion: 2, noteID: UUID(), blocks: blocks, spans: [])
        let out = EditCommandEngine.adjustBlocks(
            blocks: blocks,
            replacedRange: TextRange(start: 2, length: 0),
            replacementUTF16Length: 1,
            text: text,
            contextMetadata: ctx
        )
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].range, TextRange(start: 0, length: 5))
        XCTAssertEqual(out[1].range, TextRange(start: 5, length: 4))
    }

    func testReplaceSpanningMultipleBlocksFallsBackToNormalize() {
        let blocks = [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil),
            Block(id: "b", type: .paragraph, range: TextRange(start: 3, length: 3), level: nil, icon: nil)
        ]
        let ctx = NoteMetadata(schemaVersion: 2, noteID: UUID(), blocks: blocks, spans: [])
        let out = EditCommandEngine.adjustBlocks(
            blocks: blocks,
            replacedRange: TextRange(start: 2, length: 4),
            replacementUTF16Length: 0,
            text: "ab",
            contextMetadata: ctx
        )
        let meta = NoteMetadata(schemaVersion: 2, noteID: ctx.noteID, blocks: out, spans: [])
        XCTAssertTrue(NoteIntegrity.check(document: NoteDocument(text: "ab", metadata: meta)).isValid)
    }
}

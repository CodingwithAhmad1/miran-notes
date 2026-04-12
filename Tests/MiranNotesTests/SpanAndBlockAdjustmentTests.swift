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

    func testReplaceSpanningMultipleBlocksCollapsesDeterministically() {
        // "aaa" block A (0,3) + "bbb" block B (3,3); delete 4 chars (2,4) → "ab" (len 2)
        let blocks = [
            Block(id: "a", type: .heading, range: TextRange(start: 0, length: 3), level: 1, icon: nil),
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
        // Collapsed to one block; original first block's id and type are preserved.
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].id, "a", "First block id preserved after multi-block collapse")
        XCTAssertEqual(out[0].type, .heading, "First block type preserved after multi-block collapse")
        let meta = NoteMetadata(schemaVersion: 2, noteID: ctx.noteID, blocks: out, spans: [])
        XCTAssertTrue(NoteIntegrity.check(document: NoteDocument(text: "ab", metadata: meta)).isValid)
    }

    func testSingleBlockDeletionToZeroLengthMergesWithPredecessor() {
        // Block A (0,5) "Hello" + Block B (5,3) "end"; delete all of B → "Hello" (len 5)
        let blocks = [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 5), level: nil, icon: nil),
            Block(id: "b", type: .heading, range: TextRange(start: 5, length: 3), level: 2, icon: nil)
        ]
        let ctx = NoteMetadata(schemaVersion: 2, noteID: UUID(), blocks: blocks, spans: [])
        let out = EditCommandEngine.adjustBlocks(
            blocks: blocks,
            replacedRange: TextRange(start: 5, length: 3),
            replacementUTF16Length: 0,
            text: "Hello",
            contextMetadata: ctx
        )
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].id, "a")
        XCTAssertEqual(out[0].range, TextRange(start: 0, length: 5))
        let meta = NoteMetadata(schemaVersion: 2, noteID: ctx.noteID, blocks: out, spans: [])
        XCTAssertTrue(NoteIntegrity.check(document: NoteDocument(text: "Hello", metadata: meta)).isValid)
    }

    func testMultiBlockReplacementWithNonEmptyReplacementProducesSingleBlock() {
        // Block A (0,3) + Block B (3,3) = "aaabbb" (len 6); replace (1,5) with "XY" → "aXY" (len 3)
        // suffix after replaced range: lastBlock.end (6) - replacedRange.end (6) = 0 chars
        let blocks = [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil),
            Block(id: "b", type: .code, range: TextRange(start: 3, length: 3), level: nil, icon: nil)
        ]
        let ctx = NoteMetadata(schemaVersion: 2, noteID: UUID(), blocks: blocks, spans: [])
        let out = EditCommandEngine.adjustBlocks(
            blocks: blocks,
            replacedRange: TextRange(start: 1, length: 5),
            replacementUTF16Length: 2,
            text: "aXY",
            contextMetadata: ctx
        )
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].id, "a")
        XCTAssertEqual(out[0].range, TextRange(start: 0, length: 3))
        let meta = NoteMetadata(schemaVersion: 2, noteID: ctx.noteID, blocks: out, spans: [])
        XCTAssertTrue(NoteIntegrity.check(document: NoteDocument(text: "aXY", metadata: meta)).isValid)
    }

    func testSingleBlockDeletionToZeroLengthWithNoSuccessorKeepsEmptyBlock() {
        // Only one block, delete all content → empty document.
        let blocks = [
            Block(id: "only", type: .paragraph, range: TextRange(start: 0, length: 5), level: nil, icon: nil)
        ]
        let ctx = NoteMetadata(schemaVersion: 2, noteID: UUID(), blocks: blocks, spans: [])
        let out = EditCommandEngine.adjustBlocks(
            blocks: blocks,
            replacedRange: TextRange(start: 0, length: 5),
            replacementUTF16Length: 0,
            text: "",
            contextMetadata: ctx
        )
        XCTAssertEqual(out.count, 1, "Single block stays even when empty (empty document)")
        XCTAssertEqual(out[0].id, "only")
        XCTAssertEqual(out[0].range, TextRange(start: 0, length: 0))
    }
}

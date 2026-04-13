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

    func testSingleBlockDeletionToZeroLengthPreservesEmptyBlock() {
        // Block A (0,5) "Hello" + Block B (5,3) "end"; delete all of B → "Hello" (len 5).
        // adjustBlocks intentionally preserves the now-empty Block B so that a subsequent
        // changeBlockType command in the same batch can still find it by ID.
        // Callers that need to remove an empty block (e.g. deleteBlock) do so explicitly.
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
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].id, "a")
        XCTAssertEqual(out[0].range, TextRange(start: 0, length: 5))
        XCTAssertEqual(out[1].id, "b")
        XCTAssertEqual(out[1].range, TextRange(start: 5, length: 0))
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

    // MARK: - splitBlock span/link constraining

    func testSplitBlockSplitsBoldSpanAtSplitPoint() {
        // "hello\nworld" with a bold span covering the entire first word + newline (0..<6)
        // After splitting at offset 6, the bold span must be clipped to the first block only.
        let text = "hello\nworld"
        let noteID = UUID()
        var doc = NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: 2,
                noteID: noteID,
                blocks: [
                    Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 11), level: nil, icon: nil)
                ],
                spans: [
                    Span(range: TextRange(start: 0, length: 6), style: .bold)
                ]
            )
        )
        doc = EditCommandEngine.apply(.splitBlock(blockID: "b0", atOffset: 6), to: doc)

        XCTAssertEqual(doc.metadata.blocks.count, 2, "split must produce two blocks")
        for span in doc.metadata.spans {
            let crossesBlock0End = span.range.end > doc.metadata.blocks[0].range.end
            XCTAssertFalse(crossesBlock0End, "No span should cross block boundary after split")
        }
        let report = NoteIntegrity.check(document: doc)
        XCTAssertTrue(report.isValid, "Document must be valid after split: \(report.issues)")
    }

    func testSplitBlockSplitsWikiLinkAtSplitPoint() {
        let text = "ab\ncd"
        let noteID = UUID()
        let targetID = UUID()
        var doc = NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: 2,
                noteID: noteID,
                blocks: [
                    Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 5), level: nil, icon: nil)
                ],
                spans: [],
                links: [
                    NoteLink(range: TextRange(start: 1, length: 3), targetNoteID: targetID)
                ]
            )
        )
        doc = EditCommandEngine.apply(.splitBlock(blockID: "b0", atOffset: 3), to: doc)

        XCTAssertEqual(doc.metadata.blocks.count, 2)
        for link in doc.metadata.links {
            let block = doc.metadata.blocks.first { $0.range.contains(link.range.start) }
            if let block {
                XCTAssertLessThanOrEqual(link.range.end, block.range.end, "Link must not extend beyond its block")
            }
        }
        let report = NoteIntegrity.check(document: doc)
        XCTAssertTrue(report.isValid, "\(report.issues)")
    }
}

import XCTest
@testable import MiranNotesCore

final class RangeNormalizerTests: XCTestCase {
    private let fixedNoteID = UUID()

    private func meta(
        blocks: [Block],
        spans: [Span] = [],
        links: [NoteLink] = [],
        artifacts: [EmbeddedArtifact] = [],
        databaseRowReferences: [DatabaseRowReference] = [],
        properties: [String: String] = [:]
    ) -> NoteMetadata {
        NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
            noteID: fixedNoteID,
            blocks: blocks,
            spans: spans,
            links: links,
            artifacts: artifacts,
            databaseRowReferences: databaseRowReferences,
            properties: properties
        )
    }

    // MARK: - Metadata field preservation

    func testNormalizePreservesDatabaseRowReferences() {
        let refs = [
            DatabaseRowReference(databaseID: UUID(), rowID: UUID(), blockID: "b0"),
            DatabaseRowReference(databaseID: UUID(), rowID: UUID())
        ]
        let m = meta(
            blocks: [Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 5), level: nil, icon: nil)],
            databaseRowReferences: refs
        )
        let result = RangeNormalizer.normalize(metadata: m, for: "hello")
        XCTAssertEqual(result.normalizedMetadata.databaseRowReferences, refs)
    }

    func testNormalizePreservesArtifacts() {
        let artifact = EmbeddedArtifact(id: UUID(), kind: .databaseView, relativePath: "views/foo.json")
        let m = meta(
            blocks: [Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 2), level: nil, icon: nil)],
            artifacts: [artifact]
        )
        let result = RangeNormalizer.normalize(metadata: m, for: "hi")
        XCTAssertEqual(result.normalizedMetadata.artifacts, [artifact])
    }

    func testNormalizePreservesProperties() {
        let m = meta(
            blocks: [Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 4), level: nil, icon: nil)],
            properties: ["status": "draft", "priority": "high"]
        )
        let result = RangeNormalizer.normalize(metadata: m, for: "test")
        XCTAssertEqual(result.normalizedMetadata.properties, ["status": "draft", "priority": "high"])
    }

    func testNormalizePreservesNoteID() {
        let m = meta(
            blocks: [Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil)]
        )
        let result = RangeNormalizer.normalize(metadata: m, for: "abc")
        XCTAssertEqual(result.normalizedMetadata.noteID, fixedNoteID)
    }

    // MARK: - Empty blocks → single paragraph

    func testNormalizeEmptyBlocksInsertsSingleParagraph() {
        let m = meta(blocks: [])
        let result = RangeNormalizer.normalize(metadata: m, for: "hello")
        XCTAssertEqual(result.normalizedMetadata.blocks.count, 1)
        XCTAssertEqual(result.normalizedMetadata.blocks[0].type, .paragraph)
        XCTAssertEqual(result.normalizedMetadata.blocks[0].range, TextRange(start: 0, length: 5))
        XCTAssertTrue(result.warnings.contains { $0.contains("No blocks found") })
    }

    func testNormalizeEmptyBlocksEmptyText() {
        let m = meta(blocks: [])
        let result = RangeNormalizer.normalize(metadata: m, for: "")
        XCTAssertEqual(result.normalizedMetadata.blocks.count, 1)
        XCTAssertEqual(result.normalizedMetadata.blocks[0].range, TextRange(start: 0, length: 0))
    }

    // MARK: - Gap closing

    func testNormalizeClosesGapBetweenBlocks() {
        let m = meta(blocks: [
            Block(id: "a", type: .heading, range: TextRange(start: 0, length: 2), level: 1, icon: nil),
            Block(id: "b", type: .paragraph, range: TextRange(start: 4, length: 1), level: nil, icon: nil)
        ])
        let result = RangeNormalizer.normalize(metadata: m, for: "abcde")
        XCTAssertTrue(RangeNormalizer.isValid(metadata: result.normalizedMetadata, for: "abcde"))
        XCTAssertTrue(result.warnings.contains { $0.contains("gap") || $0.contains("Expanded") })
    }

    func testNormalizeResolvesOverlappingBlocks() {
        let m = meta(blocks: [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 4), level: nil, icon: nil),
            Block(id: "b", type: .paragraph, range: TextRange(start: 2, length: 3), level: nil, icon: nil)
        ])
        let result = RangeNormalizer.normalize(metadata: m, for: "abcde")
        XCTAssertTrue(RangeNormalizer.isValid(metadata: result.normalizedMetadata, for: "abcde"))
        XCTAssertTrue(result.warnings.contains { $0.contains("overlapping") || $0.contains("Adjusted") })
    }

    func testNormalizeAdjustsTrailingBlockToEnd() {
        let m = meta(blocks: [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil)
        ])
        let result = RangeNormalizer.normalize(metadata: m, for: "abcde")
        XCTAssertEqual(result.normalizedMetadata.blocks[0].range.end, 5)
        XCTAssertTrue(RangeNormalizer.isValid(metadata: result.normalizedMetadata, for: "abcde"))
    }

    // MARK: - Span/link clamping

    func testNormalizeClampsOutOfBoundsSpan() {
        let m = meta(
            blocks: [Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil)],
            spans: [Span(range: TextRange(start: 0, length: 10), style: .bold)]
        )
        let result = RangeNormalizer.normalize(metadata: m, for: "abc")
        XCTAssertEqual(result.normalizedMetadata.spans.count, 1)
        XCTAssertEqual(result.normalizedMetadata.spans[0].range.end, 3)
    }

    func testNormalizeRemovesEmptySpanAfterClamping() {
        let m = meta(
            blocks: [Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil)],
            spans: [Span(range: TextRange(start: 5, length: 2), style: .italic)]
        )
        let result = RangeNormalizer.normalize(metadata: m, for: "abc")
        XCTAssertTrue(result.normalizedMetadata.spans.isEmpty)
    }

    func testNormalizeClampsOutOfBoundsLink() {
        let target = UUID()
        let m = meta(
            blocks: [Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil)],
            links: [NoteLink(range: TextRange(start: 1, length: 10), targetNoteID: target)]
        )
        let result = RangeNormalizer.normalize(metadata: m, for: "abc")
        XCTAssertEqual(result.normalizedMetadata.links.count, 1)
        XCTAssertEqual(result.normalizedMetadata.links[0].range.end, 3)
    }

    // MARK: - stripZeroLengthBlocks parameter

    func testStripZeroLengthBlocksTrueRemovesEmptyInteriorBlocks() {
        let m = meta(blocks: [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil),
            Block(id: "b", type: .heading, range: TextRange(start: 3, length: 0), level: 1, icon: nil),
            Block(id: "c", type: .paragraph, range: TextRange(start: 3, length: 2), level: nil, icon: nil)
        ])
        let result = RangeNormalizer.normalize(metadata: m, for: "abcde", stripZeroLengthBlocks: true)
        XCTAssertEqual(result.normalizedMetadata.blocks.count, 2)
        XCTAssertFalse(result.normalizedMetadata.blocks.contains { $0.id == "b" })
        XCTAssertTrue(RangeNormalizer.isValid(metadata: result.normalizedMetadata, for: "abcde"))
    }

    func testStripZeroLengthBlocksFalsePreservesEmptyInteriorBlocks() {
        let m = meta(blocks: [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 5), level: nil, icon: nil),
            Block(id: "b", type: .heading, range: TextRange(start: 5, length: 0), level: 1, icon: nil)
        ])
        let result = RangeNormalizer.normalize(metadata: m, for: "hello", stripZeroLengthBlocks: false)
        XCTAssertEqual(result.normalizedMetadata.blocks.count, 2)
        XCTAssertTrue(result.normalizedMetadata.blocks.contains { $0.id == "b" })
    }

    // MARK: - isValid

    func testIsValidReturnsFalseForGap() {
        let m = meta(blocks: [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 2), level: nil, icon: nil),
            Block(id: "b", type: .paragraph, range: TextRange(start: 3, length: 2), level: nil, icon: nil)
        ])
        XCTAssertFalse(RangeNormalizer.isValid(metadata: m, for: "abcde"))
    }

    func testIsValidReturnsFalseForOutOfBounds() {
        let m = meta(blocks: [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 10), level: nil, icon: nil)
        ])
        XCTAssertFalse(RangeNormalizer.isValid(metadata: m, for: "abc"))
    }

    func testIsValidReturnsFalseForShortCoverage() {
        let m = meta(blocks: [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil)
        ])
        XCTAssertFalse(RangeNormalizer.isValid(metadata: m, for: "abcde"))
    }

    func testIsValidReturnsFalseForEmptyBlocks() {
        let m = meta(blocks: [])
        XCTAssertFalse(RangeNormalizer.isValid(metadata: m, for: "abc"))
    }

    func testIsValidReturnsFalseForOutOfBoundsSpan() {
        let m = meta(
            blocks: [Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil)],
            spans: [Span(range: TextRange(start: 0, length: 5), style: .bold)]
        )
        XCTAssertFalse(RangeNormalizer.isValid(metadata: m, for: "abc"))
    }

    func testIsValidReturnsFalseForOutOfBoundsLink() {
        let m = meta(
            blocks: [Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil)],
            links: [NoteLink(range: TextRange(start: 0, length: 5), targetNoteID: UUID())]
        )
        XCTAssertFalse(RangeNormalizer.isValid(metadata: m, for: "abc"))
    }

    // MARK: - Idempotency

    func testNormalizeIsIdempotent() {
        let m = meta(
            blocks: [
                Block(id: "a", type: .heading, range: TextRange(start: 0, length: 2), level: 1, icon: nil),
                Block(id: "b", type: .paragraph, range: TextRange(start: 5, length: 3), level: nil, icon: nil)
            ],
            spans: [Span(range: TextRange(start: 0, length: 20), style: .bold)],
            databaseRowReferences: [DatabaseRowReference(databaseID: UUID(), rowID: UUID())],
            properties: ["key": "value"]
        )
        let text = "abcdefgh"
        let pass1 = RangeNormalizer.normalize(metadata: m, for: text)
        let pass2 = RangeNormalizer.normalize(metadata: pass1.normalizedMetadata, for: text)
        XCTAssertEqual(pass1.normalizedMetadata, pass2.normalizedMetadata)
    }

    // MARK: - Schema version bump

    func testNormalizeBumpsSchemaVersion() {
        var m = meta(blocks: [
            Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 3), level: nil, icon: nil)
        ])
        m.schemaVersion = 1
        let result = RangeNormalizer.normalize(metadata: m, for: "abc")
        XCTAssertEqual(result.normalizedMetadata.schemaVersion, NoteMetadata.currentSchemaVersion)
    }

    // MARK: - Block sorting

    func testNormalizeSortsUnsortedBlocks() {
        let m = meta(blocks: [
            Block(id: "b", type: .paragraph, range: TextRange(start: 3, length: 2), level: nil, icon: nil),
            Block(id: "a", type: .heading, range: TextRange(start: 0, length: 3), level: 1, icon: nil)
        ])
        let result = RangeNormalizer.normalize(metadata: m, for: "abcde")
        XCTAssertEqual(result.normalizedMetadata.blocks[0].id, "a")
        XCTAssertEqual(result.normalizedMetadata.blocks[1].id, "b")
        XCTAssertTrue(RangeNormalizer.isValid(metadata: result.normalizedMetadata, for: "abcde"))
    }
}

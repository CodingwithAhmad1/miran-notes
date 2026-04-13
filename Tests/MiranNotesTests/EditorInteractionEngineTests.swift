import XCTest
@testable import MiranNotesCore

/// Scenario-style coverage for the edit engine (mirrors user flows without AppKit).
final class EditorInteractionEngineTests: XCTestCase {
    private func applyAll(_ commands: [EditCommand], to document: NoteDocument) -> NoteDocument {
        commands.reduce(document) { doc, cmd in EditCommandEngine.apply(cmd, to: doc) }
    }

    private func baseline(noteID: UUID = UUID(), text: String, blockID: String = "b0") -> NoteDocument {
        NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: blockID, type: .paragraph, range: TextRange(start: 0, length: text.utf16.count), level: nil, icon: nil)
                ],
                spans: []
            )
        )
    }

    // MARK: - Split / merge (structural batches)

    func testNewlineSplitProducesTwoBlocksWithIntegrity() {
        var doc = baseline(text: "ab")
        doc = applyAll(
            [
                .replaceText(range: TextRange(start: 1, length: 0), replacement: "\n"),
                .splitBlock(blockID: "b0", atOffset: 2)
            ],
            to: doc
        )
        XCTAssertEqual(doc.metadata.blocks.count, 2)
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
        XCTAssertEqual(doc.text, "a\nb")
    }

    func testDuplicateBlockInsertsCopyAndKeepsIntegrity() {
        let noteID = UUID()
        var doc = NoteDocument(
            text: "a\nb",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 2), level: nil, icon: nil),
                    Block(id: "b1", type: .paragraph, range: TextRange(start: 2, length: 1), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        doc = EditCommandEngine.apply(.duplicateBlock(blockID: "b0"), to: doc)
        XCTAssertEqual(doc.text, "a\na\nb")
        XCTAssertEqual(doc.metadata.blocks.count, 3)
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
    }

    func testDeleteBlockRemovesRangeAndMergesMetadata() {
        let noteID = UUID()
        var doc = NoteDocument(
            text: "a\nb",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 2), level: nil, icon: nil),
                    Block(id: "b1", type: .paragraph, range: TextRange(start: 2, length: 1), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        doc = EditCommandEngine.apply(.deleteBlock(blockID: "b0"), to: doc)
        XCTAssertEqual(doc.text, "b")
        XCTAssertEqual(doc.metadata.blocks.count, 1)
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
    }

    func testMergeAtBlockStartDeletesNewlineAndMergesBlocks() {
        let noteID = UUID()
        var doc = NoteDocument(
            text: "a\nb",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 2), level: nil, icon: nil),
                    Block(id: "b1", type: .paragraph, range: TextRange(start: 2, length: 1), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        doc = applyAll(
            [
                .mergeWithPrevious(blockID: "b1"),
                .replaceText(range: TextRange(start: 1, length: 1), replacement: "")
            ],
            to: doc
        )
        XCTAssertEqual(doc.text, "ab")
        XCTAssertEqual(doc.metadata.blocks.count, 1)
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
    }

    // MARK: - Spans (bold / italic / code)

    func testToggleSpanStyleAddsAndRemovesBold() {
        var doc = baseline(text: "hello")
        doc = EditCommandEngine.apply(
            .toggleSpanStyle(range: TextRange(start: 0, length: 5), style: .bold),
            to: doc
        )
        XCTAssertEqual(doc.metadata.spans.count, 1)
        XCTAssertEqual(doc.metadata.spans[0].style, .bold)
        doc = EditCommandEngine.apply(
            .toggleSpanStyle(range: TextRange(start: 0, length: 5), style: .bold),
            to: doc
        )
        XCTAssertTrue(doc.metadata.spans.isEmpty)
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
    }

    func testEditAcrossSpanBoundaryMaintainsIntegrity() {
        var doc = baseline(text: "hello")
        doc.metadata.spans = [Span(range: TextRange(start: 0, length: 5), style: .italic)]
        doc = EditCommandEngine.apply(
            .replaceText(range: TextRange(start: 3, length: 0), replacement: "X"),
            to: doc
        )
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
        XCTAssertEqual(doc.text, "helXlo")
    }

    // MARK: - Wiki links

    func testReplaceInsideWikiLinkTokenAdjustsLinkRange() {
        let target = UUID()
        var doc = baseline(text: "hi")
        doc = EditCommandEngine.apply(
            .insertWikiLink(utf16Offset: 2, targetNoteID: target, displayText: "Other"),
            to: doc
        )
        XCTAssertTrue(doc.text.contains("[[Other]]"))
        doc = EditCommandEngine.apply(
            .replaceText(
                range: TextRange(start: doc.text.utf16.count - 3, length: 2),
                replacement: "er"
            ),
            to: doc
        )
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
        XCTAssertEqual(doc.metadata.links.count, 1)
        XCTAssertTrue(doc.metadata.links[0].range.length > 0)
    }

    func testSplitBlockThroughWikiLinkClipsSpanAndLink() {
        let target = UUID()
        var doc = baseline(text: "")
        doc = EditCommandEngine.apply(
            .insertWikiLink(utf16Offset: 0, targetNoteID: target, displayText: "Link"),
            to: doc
        )
        XCTAssertEqual(doc.text, "[[Link]]")
        let mid = doc.text.utf16.count / 2
        doc = applyAll(
            [
                .replaceText(range: TextRange(start: mid, length: 0), replacement: "\n"),
                .splitBlock(blockID: "b0", atOffset: mid + 1)
            ],
            to: doc
        )
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
        XCTAssertEqual(doc.metadata.blocks.count, 2)
    }

    // MARK: - Callouts

    func testCalloutBlockNewlineSplitMaintainsIntegrity() {
        var doc = baseline(text: "note")
        doc = EditCommandEngine.apply(
            .changeBlockType(blockID: "b0", type: .callout, headingLevel: nil),
            to: doc
        )
        doc = applyAll(
            [
                .replaceText(range: TextRange(start: 2, length: 0), replacement: "\n"),
                .splitBlock(blockID: "b0", atOffset: 3)
            ],
            to: doc
        )
        XCTAssertEqual(doc.metadata.blocks.count, 2)
        XCTAssertEqual(doc.metadata.blocks[0].type, .callout)
        XCTAssertEqual(doc.metadata.blocks[1].type, .callout)
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
    }

    // MARK: - replaceMetadataBlocks (full-buffer recovery batch)

    func testReplaceMetadataBlocksReconstrainsSpansAndKeepsIntegrity() {
        var doc = baseline(text: "ab")
        doc.metadata.spans = [Span(range: TextRange(start: 0, length: 2), style: .code)]
        let twoBlocks = [
            Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 1), level: nil, icon: nil),
            Block(id: "b1", type: .paragraph, range: TextRange(start: 1, length: 1), level: nil, icon: nil)
        ]
        doc = EditCommandEngine.apply(.replaceMetadataBlocks(blocks: twoBlocks), to: doc)
        XCTAssertTrue(NoteIntegrity.check(document: doc).isValid)
        XCTAssertEqual(doc.metadata.blocks.count, 2)
    }

    func testFullBufferBatchWithReconcileMatchesSinglePipeline() {
        let noteID = UUID()
        let doc = NoteDocument(
            text: "a\nb",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "x", type: .heading, range: TextRange(start: 0, length: 2), level: 1, icon: nil),
                    Block(id: "y", type: .paragraph, range: TextRange(start: 2, length: 1), level: nil, icon: nil)
                ],
                spans: [],
                links: []
            )
        )
        let oldBlocks = doc.metadata.blocks
        let replaceCmd = EditCommand.replaceText(
            range: TextRange(start: 0, length: doc.text.utf16.count),
            replacement: "a\nb"
        )
        let afterReplace = EditCommandEngine.apply(replaceCmd, to: doc)
        let reconciled = EditCommandEngine.reconcileBlocksFromText(document: afterReplace, oldText: doc.text, oldBlocks: oldBlocks)
        var commands: [EditCommand] = [replaceCmd]
        if reconciled.metadata.blocks != afterReplace.metadata.blocks {
            commands.append(.replaceMetadataBlocks(blocks: reconciled.metadata.blocks))
        }
        let merged = applyAll(commands, to: doc)
        XCTAssertTrue(NoteIntegrity.check(document: merged).isValid)
        XCTAssertEqual(merged.text, "a\nb")
    }

    // MARK: - reconcileBlocksFromText

    func testReconcileRecoversSingleHeadingAfterIdentityReplace() {
        let noteID = UUID()
        let doc = NoteDocument(
            text: "Title\nBody",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "h1", type: .heading, range: TextRange(start: 0, length: 6), level: 1, icon: nil),
                    Block(id: "p1", type: .paragraph, range: TextRange(start: 6, length: 4), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        let oldBlocks = doc.metadata.blocks
        let replaceCmd = EditCommand.replaceText(
            range: TextRange(start: 0, length: doc.text.utf16.count),
            replacement: "Title\nBody"
        )
        let afterReplace = EditCommandEngine.apply(replaceCmd, to: doc)
        let reconciled = EditCommandEngine.reconcileBlocksFromText(document: afterReplace, oldText: doc.text, oldBlocks: oldBlocks)

        XCTAssertEqual(reconciled.metadata.blocks.count, 2)
        XCTAssertEqual(reconciled.metadata.blocks[0].type, .heading)
        XCTAssertEqual(reconciled.metadata.blocks[0].level, 1)
        XCTAssertEqual(reconciled.metadata.blocks[0].id, "h1", "Stable ID preserved via content match")
        XCTAssertEqual(reconciled.metadata.blocks[1].type, .paragraph)
        XCTAssertTrue(NoteIntegrity.check(document: reconciled).isValid)
    }

    func testReconcileWithPastedExtraLines() {
        let noteID = UUID()
        let doc = NoteDocument(
            text: "A\nB",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "a", type: .heading, range: TextRange(start: 0, length: 2), level: 2, icon: nil),
                    Block(id: "b", type: .callout, range: TextRange(start: 2, length: 1), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        let oldBlocks = doc.metadata.blocks
        let newText = "A\nX\nY\nB"
        let replaceCmd = EditCommand.replaceText(
            range: TextRange(start: 0, length: doc.text.utf16.count),
            replacement: newText
        )
        let afterReplace = EditCommandEngine.apply(replaceCmd, to: doc)
        let reconciled = EditCommandEngine.reconcileBlocksFromText(document: afterReplace, oldText: doc.text, oldBlocks: oldBlocks)

        XCTAssertEqual(reconciled.metadata.blocks.count, 4)
        XCTAssertEqual(reconciled.metadata.blocks[0].type, .heading, "First line content matches old heading")
        XCTAssertEqual(reconciled.metadata.blocks[3].type, .callout, "Last line content matches old callout")
        XCTAssertEqual(reconciled.metadata.blocks[1].type, .paragraph, "New line X defaults to paragraph")
        XCTAssertEqual(reconciled.metadata.blocks[2].type, .paragraph, "New line Y defaults to paragraph")
        XCTAssertTrue(NoteIntegrity.check(document: reconciled).isValid)
    }

    func testReconcileWithRemovedLines() {
        let noteID = UUID()
        let doc = NoteDocument(
            text: "H\nA\nB\nC",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "h", type: .heading, range: TextRange(start: 0, length: 2), level: 1, icon: nil),
                    Block(id: "a", type: .paragraph, range: TextRange(start: 2, length: 2), level: nil, icon: nil),
                    Block(id: "b", type: .code, range: TextRange(start: 4, length: 2), level: nil, icon: nil),
                    Block(id: "c", type: .paragraph, range: TextRange(start: 6, length: 1), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        let oldBlocks = doc.metadata.blocks
        let newText = "H\nC"
        let replaceCmd = EditCommand.replaceText(
            range: TextRange(start: 0, length: doc.text.utf16.count),
            replacement: newText
        )
        let afterReplace = EditCommandEngine.apply(replaceCmd, to: doc)
        let reconciled = EditCommandEngine.reconcileBlocksFromText(document: afterReplace, oldText: doc.text, oldBlocks: oldBlocks)

        XCTAssertEqual(reconciled.metadata.blocks.count, 2)
        XCTAssertEqual(reconciled.metadata.blocks[0].type, .heading)
        XCTAssertEqual(reconciled.metadata.blocks[0].id, "h")
        XCTAssertEqual(reconciled.metadata.blocks[1].id, "c")
        XCTAssertTrue(NoteIntegrity.check(document: reconciled).isValid)
    }

    func testReconcileEmptyText() {
        let noteID = UUID()
        let doc = NoteDocument(
            text: "",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 0), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        let reconciled = EditCommandEngine.reconcileBlocksFromText(document: doc, oldText: doc.text, oldBlocks: doc.metadata.blocks)
        XCTAssertEqual(reconciled.metadata.blocks.count, 1)
        XCTAssertEqual(reconciled.metadata.blocks[0].range, TextRange(start: 0, length: 0))
        XCTAssertTrue(NoteIntegrity.check(document: reconciled).isValid)
    }

    func testReconcileSingleLineNoNewline() {
        let noteID = UUID()
        let doc = NoteDocument(
            text: "Hello",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "b0", type: .heading, range: TextRange(start: 0, length: 5), level: 1, icon: nil)
                ],
                spans: []
            )
        )
        let reconciled = EditCommandEngine.reconcileBlocksFromText(document: doc, oldText: doc.text, oldBlocks: doc.metadata.blocks)
        XCTAssertEqual(reconciled.metadata.blocks.count, 1)
        XCTAssertEqual(reconciled.metadata.blocks[0].type, .heading)
        XCTAssertEqual(reconciled.metadata.blocks[0].id, "b0")
        XCTAssertTrue(NoteIntegrity.check(document: reconciled).isValid)
    }

    func testReconcileMultipleHeadingTypes() {
        let noteID = UUID()
        let doc = NoteDocument(
            text: "H1\nH2\nH3",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "a", type: .heading, range: TextRange(start: 0, length: 3), level: 1, icon: nil),
                    Block(id: "b", type: .heading, range: TextRange(start: 3, length: 3), level: 2, icon: nil),
                    Block(id: "c", type: .heading, range: TextRange(start: 6, length: 2), level: 3, icon: nil)
                ],
                spans: []
            )
        )
        let oldBlocks = doc.metadata.blocks
        let replaceCmd = EditCommand.replaceText(
            range: TextRange(start: 0, length: doc.text.utf16.count),
            replacement: "H1\nH2\nH3"
        )
        let afterReplace = EditCommandEngine.apply(replaceCmd, to: doc)
        let reconciled = EditCommandEngine.reconcileBlocksFromText(document: afterReplace, oldText: doc.text, oldBlocks: oldBlocks)

        XCTAssertEqual(reconciled.metadata.blocks.count, 3)
        XCTAssertEqual(reconciled.metadata.blocks[0].level, 1)
        XCTAssertEqual(reconciled.metadata.blocks[1].level, 2)
        XCTAssertEqual(reconciled.metadata.blocks[2].level, 3)
        XCTAssertTrue(NoteIntegrity.check(document: reconciled).isValid)
    }

    // MARK: - Large document

    func testSequentialEndInsertsOnLargeBufferRemainValid() {
        let padding = String(repeating: "a", count: 50_000)
        var doc = baseline(text: padding)
        for i in 0..<20 {
            let loc = doc.text.utf16.count
            doc = EditCommandEngine.apply(
                .replaceText(range: TextRange(start: loc, length: 0), replacement: "\(i % 10)"),
                to: doc
            )
            XCTAssertTrue(NoteIntegrity.check(document: doc).isValid, "iteration \(i)")
        }
        XCTAssertGreaterThan(doc.text.utf16.count, 50_000)
    }
}

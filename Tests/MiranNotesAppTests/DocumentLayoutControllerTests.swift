import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class DocumentLayoutControllerTests: XCTestCase {
    private func singleBlockDocument(text: String) -> NoteDocument {
        let noteID = UUID()
        return NoteDocument(
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

    private func listItemDocument(text: String) -> NoteDocument {
        let noteID = UUID()
        return NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(
                        id: "list",
                        type: .listItem,
                        range: TextRange(start: 0, length: text.utf16.count),
                        level: nil,
                        icon: nil
                    )
                ],
                spans: []
            )
        )
    }

    func testNewlineInsertsSplitCommands() {
        let doc = singleBlockDocument(text: "ab")
        let cmds = DocumentLayoutController.commandsForEdit(
            document: doc,
            affectedRange: NSRange(location: 1, length: 0),
            replacement: "\n",
            selectedLocation: 1
        )
        XCTAssertEqual(cmds?.count, 2)
        guard let cmds, cmds.count == 2 else { return }
        guard case let .replaceText(r, rep) = cmds[0] else {
            XCTFail("expected replaceText")
            return
        }
        XCTAssertEqual(r, TextRange(start: 1, length: 0))
        XCTAssertEqual(rep, "\n")
        guard case let .splitBlock(id, at) = cmds[1] else {
            XCTFail("expected splitBlock")
            return
        }
        XCTAssertEqual(id, "b0")
        XCTAssertEqual(at, 2)
    }

    func testNewlineAtExistingBlockBoundaryInsertsOnlyNoSplit() {
        let text = "helloworld"
        let noteID = UUID()
        let doc = NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: 5), level: nil, icon: nil),
                    Block(id: "b1", type: .paragraph, range: TextRange(start: 5, length: 5), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        let cmds = DocumentLayoutController.commandsForEdit(
            document: doc,
            affectedRange: NSRange(location: 5, length: 0),
            replacement: "\n",
            selectedLocation: 5
        )
        XCTAssertEqual(cmds?.count, 1)
        guard let cmds, cmds.count == 1 else { return }
        guard case let .replaceText(r, rep) = cmds[0] else {
            XCTFail("expected replaceText only")
            return
        }
        XCTAssertEqual(r, TextRange(start: 5, length: 0))
        XCTAssertEqual(rep, "\n")
    }

    func testBackspaceAtBlockStartMergesWithPrevious() {
        let text = "a\nb"
        let noteID = UUID()
        let doc = NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "p", type: .paragraph, range: TextRange(start: 0, length: 2), level: nil, icon: nil),
                    Block(id: "c", type: .paragraph, range: TextRange(start: 2, length: 1), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        let cmds = DocumentLayoutController.commandsForEdit(
            document: doc,
            affectedRange: NSRange(location: 1, length: 1),
            replacement: "",
            selectedLocation: 2
        )
        XCTAssertEqual(cmds?.count, 2)
        guard let cmds, cmds.count == 2 else { return }
        guard case .mergeWithPrevious(blockID: "c") = cmds[0] else {
            XCTFail("expected mergeWithPrevious")
            return
        }
        guard case let .replaceText(r, rep) = cmds[1] else {
            XCTFail("expected replaceText delete")
            return
        }
        XCTAssertEqual(r, TextRange(start: 1, length: 1))
        XCTAssertEqual(rep, "")
    }

    func testNewlineInNonEmptyListItemContinuesListBySplit() {
        let doc = listItemDocument(text: "item")
        let cmds = DocumentLayoutController.commandsForEdit(
            document: doc,
            affectedRange: NSRange(location: 4, length: 0),
            replacement: "\n",
            selectedLocation: 4
        )
        XCTAssertEqual(cmds?.count, 2)
        guard let cmds, cmds.count == 2 else { return }
        guard case let .replaceText(r, rep) = cmds[0] else {
            XCTFail("expected replaceText")
            return
        }
        XCTAssertEqual(r, TextRange(start: 4, length: 0))
        XCTAssertEqual(rep, "\n")
        guard case let .splitBlock(id, at) = cmds[1] else {
            XCTFail("expected splitBlock")
            return
        }
        XCTAssertEqual(id, "list")
        XCTAssertEqual(at, 5)
    }

    func testNewlineInEmptyListItemExitsToParagraph() {
        let doc = listItemDocument(text: "")
        let cmds = DocumentLayoutController.commandsForEdit(
            document: doc,
            affectedRange: NSRange(location: 0, length: 0),
            replacement: "\n",
            selectedLocation: 0
        )
        XCTAssertEqual(cmds?.count, 1)
        guard let command = cmds?.first else {
            XCTFail("expected one command")
            return
        }
        guard case let .changeBlockType(blockID, type, level) = command else {
            XCTFail("expected changeBlockType")
            return
        }
        XCTAssertEqual(blockID, "list")
        XCTAssertEqual(type, .paragraph)
        XCTAssertNil(level)
    }

    // MARK: - Newline-commit slash commands

    func testNewlineCommitSlashH1ProducesSlashAndStructuralCommands() {
        // "/h1" (3 chars) + Enter at offset 3 should produce:
        //   1. replaceText(delete token "/h1")
        //   2. changeBlockType(heading 1)
        //   3. replaceText(insert "\n" at block start, since token was removed leaving block empty)
        //   4. splitBlock at block start + 1
        let doc = singleBlockDocument(text: "/h1")
        let cmds = DocumentLayoutController.commandsForEdit(
            document: doc,
            affectedRange: NSRange(location: 3, length: 0),
            replacement: "\n",
            selectedLocation: 3
        )
        XCTAssertNotNil(cmds, "Should produce slash + structural commands")
        guard let cmds else { return }
        XCTAssertEqual(cmds.count, 4, "Expected [deleteToken, changeBlockType, insertNewline, splitBlock]")

        guard case let .replaceText(deleteRange, deleteRep) = cmds[0] else {
            XCTFail("Expected replaceText to delete token"); return
        }
        XCTAssertEqual(deleteRange, TextRange(start: 0, length: 3))
        XCTAssertEqual(deleteRep, "")

        guard case let .changeBlockType(blockID, type, level) = cmds[1] else {
            XCTFail("Expected changeBlockType"); return
        }
        XCTAssertEqual(blockID, "b0")
        XCTAssertEqual(type, .heading)
        XCTAssertEqual(level, 1)

        guard case let .replaceText(nlRange, nlRep) = cmds[2] else {
            XCTFail("Expected replaceText for newline"); return
        }
        XCTAssertEqual(nlRange, TextRange(start: 0, length: 0))
        XCTAssertEqual(nlRep, "\n")

        guard case let .splitBlock(splitID, splitAt) = cmds[3] else {
            XCTFail("Expected splitBlock"); return
        }
        XCTAssertEqual(splitID, "b0")
        XCTAssertEqual(splitAt, 1)
    }

    func testNewlineCommitSlashH1InSecondBlockUsesCorrectBlockID() {
        let text = "Hello\n/h2"
        let noteID = UUID()
        let doc = NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(id: "first", type: .paragraph, range: TextRange(start: 0, length: 6), level: nil, icon: nil),
                    Block(id: "second", type: .paragraph, range: TextRange(start: 6, length: 3), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        let cmds = DocumentLayoutController.commandsForEdit(
            document: doc,
            affectedRange: NSRange(location: 9, length: 0),
            replacement: "\n",
            selectedLocation: 9
        )
        XCTAssertNotNil(cmds)
        guard let cmds else { return }
        XCTAssertEqual(cmds.count, 4)

        guard case let .replaceText(deleteRange, _) = cmds[0] else {
            XCTFail("Expected replaceText to delete token"); return
        }
        XCTAssertEqual(deleteRange, TextRange(start: 6, length: 3), "Token range should be within the second block")

        guard case let .changeBlockType(blockID, type, level) = cmds[1] else {
            XCTFail("Expected changeBlockType"); return
        }
        XCTAssertEqual(blockID, "second")
        XCTAssertEqual(type, .heading)
        XCTAssertEqual(level, 2)

        guard case let .splitBlock(splitID, _) = cmds[3] else {
            XCTFail("Expected splitBlock"); return
        }
        XCTAssertEqual(splitID, "second")
    }

    func testNewlineCommitUnknownSlashTokenProducesNormalStructuralCommands() {
        let doc = singleBlockDocument(text: "/xyz")
        let cmds = DocumentLayoutController.commandsForEdit(
            document: doc,
            affectedRange: NSRange(location: 4, length: 0),
            replacement: "\n",
            selectedLocation: 4
        )
        XCTAssertNotNil(cmds)
        guard let cmds else { return }
        // Unrecognized token: normal newline insert + split (no slash handling).
        XCTAssertEqual(cmds.count, 2)
        guard case let .replaceText(r, rep) = cmds[0] else {
            XCTFail("Expected replaceText"); return
        }
        XCTAssertEqual(r, TextRange(start: 4, length: 0))
        XCTAssertEqual(rep, "\n")
        guard case .splitBlock = cmds[1] else {
            XCTFail("Expected splitBlock"); return
        }
    }
}

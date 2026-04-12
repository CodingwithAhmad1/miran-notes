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
}

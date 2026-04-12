import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class DocumentLayoutControllerTests: XCTestCase {
    private func singleBlockDocument(text: String) -> NoteDocument {
        let noteID = UUID()
        return NoteDocument(
            id: noteID,
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
            id: noteID,
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
            id: noteID,
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
}

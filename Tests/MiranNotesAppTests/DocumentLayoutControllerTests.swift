import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class DocumentLayoutControllerTests: XCTestCase {
    private func singleBlockDocument(text: String) -> NoteDocument {
        NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
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

    func testBackspaceAtBlockStartMergesWithPrevious() {
        let text = "a\nb"
        let doc = NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
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

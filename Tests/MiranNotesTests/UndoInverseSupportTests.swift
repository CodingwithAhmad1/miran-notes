import XCTest
@testable import MiranNotesCore

final class UndoInverseSupportTests: XCTestCase {
    func testInverseOfSingleInsert() {
        let before = NoteDocument(text: "hi", metadata: .empty)
        let cmds: [EditCommand] = [.replaceText(range: TextRange(start: 2, length: 0), replacement: "!")]
        let inv = UndoInverseSupport.inverseCommands(for: cmds, documentBefore: before)
        XCTAssertEqual(inv?.count, 1)
        guard case let .replaceText(r, rep) = inv?.first else {
            return XCTFail("expected replaceText")
        }
        XCTAssertEqual(r.start, 2)
        XCTAssertEqual(r.length, 1)
        XCTAssertEqual(rep, "")
    }

    func testInverseNonReplaceReturnsNil() {
        let before = NoteDocument(text: "a", metadata: .empty)
        XCTAssertNil(UndoInverseSupport.inverseCommands(for: [.splitBlock(blockID: "x", atOffset: 1)], documentBefore: before))
    }

    func testReplaceTextChainRoundTrip() {
        let noteID = UUID()
        let text = "hello"
        let len = text.utf16.count
        var meta = NoteMetadata.empty
        meta.noteID = noteID
        meta.blocks = [
            Block(
                id: "b0",
                type: .paragraph,
                range: TextRange(start: 0, length: len),
                level: nil,
                icon: nil
            ),
        ]
        let before = NoteDocument(text: text, metadata: meta)
        let forward: [EditCommand] = [
            .replaceText(range: TextRange(start: 5, length: 0), replacement: " "),
            .replaceText(range: TextRange(start: 6, length: 0), replacement: "w"),
        ]
        guard let chain = UndoInverseSupport.replaceTextChainUndoCommands(forward: forward, documentBefore: before) else {
            return XCTFail("expected chain")
        }
        XCTAssertEqual(chain.after.text, "hello w")
        var undone = chain.after
        for c in chain.undoCommands {
            undone = EditCommandEngine.apply(c, to: undone)
        }
        XCTAssertEqual(undone.text, before.text)
    }
}

import MiranNotesCore
import XCTest

final class NoteDocumentUndoMemoryTests: XCTestCase {
    func testEstimatedUndoMemoryBytesScalesWithTextLength() {
        let small = NoteDocument(text: "hi", metadata: .empty)
        let big = NoteDocument(text: String(repeating: "z", count: 10_000), metadata: .empty)
        XCTAssertGreaterThan(big.estimatedUndoMemoryBytes, small.estimatedUndoMemoryBytes)
    }

    func testEstimatedUndoBytesForCheckpointsSumsDocuments() {
        let a = NoteDocument(text: "a", metadata: .empty)
        let b = NoteDocument(text: "ab", metadata: .empty)
        let sum = NoteDocument.estimatedUndoBytes(forCheckpoints: [a, b])
        XCTAssertEqual(sum, a.estimatedUndoMemoryBytes + b.estimatedUndoMemoryBytes)
    }
}

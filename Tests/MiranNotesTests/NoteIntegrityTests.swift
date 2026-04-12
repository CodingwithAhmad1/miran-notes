import XCTest
@testable import MiranNotesCore

final class NoteIntegrityTests: XCTestCase {
    func testValidEmptySingleBlock() {
        let doc = NoteDocument(
            text: "",
            metadata: NoteMetadata(
                schemaVersion: 1,
                blocks: [
                    Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 0), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        let report = NoteIntegrity.check(document: doc)
        XCTAssertTrue(report.isValid, "\(report.issues)")
    }

    func testDetectsBlocksNotSortedByDocumentOrder() {
        let doc = NoteDocument(
            text: "ab",
            metadata: NoteMetadata(
                schemaVersion: 1,
                blocks: [
                    Block(id: "second", type: .paragraph, range: TextRange(start: 1, length: 1), level: nil, icon: nil),
                    Block(id: "first", type: .paragraph, range: TextRange(start: 0, length: 1), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        let report = NoteIntegrity.check(document: doc)
        XCTAssertFalse(report.isValid)
        XCTAssertTrue(report.issues.contains(.blocksNotSorted))
    }

    func testDetectsGapBetweenBlocks() {
        let doc = NoteDocument(
            text: "ab",
            metadata: NoteMetadata(
                schemaVersion: 1,
                blocks: [
                    Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 1), level: nil, icon: nil),
                    Block(id: "b", type: .paragraph, range: TextRange(start: 2, length: 0), level: nil, icon: nil)
                ],
                spans: []
            )
        )
        let report = NoteIntegrity.check(document: doc)
        XCTAssertFalse(report.isValid)
        XCTAssertTrue(report.issues.contains { issue in
            if case .gapOrOverlap = issue { return true }
            return false
        })
    }

    func testDetectsSpanOutOfBounds() {
        let doc = NoteDocument(
            text: "hi",
            metadata: NoteMetadata(
                schemaVersion: 1,
                blocks: [
                    Block(id: "a", type: .paragraph, range: TextRange(start: 0, length: 2), level: nil, icon: nil)
                ],
                spans: [Span(range: TextRange(start: 0, length: 5), style: .bold)]
            )
        )
        let report = NoteIntegrity.check(document: doc)
        XCTAssertFalse(report.isValid)
        XCTAssertTrue(report.issues.contains { issue in
            if case .spanOutOfBounds = issue { return true }
            return false
        })
    }
}

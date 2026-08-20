import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class NoteFindControllerTests: XCTestCase {
    func testMatchesAreCaseInsensitiveAndOrdered() {
        let text = "Apple apple APPLE"
        let matches = NoteFindController.matches(of: "apple", in: text)
        XCTAssertEqual(matches.map(\.start), [0, 6, 12])
        XCTAssertEqual(matches.map(\.length), [5, 5, 5])
    }

    func testMatchesAreNonOverlapping() {
        let matches = NoteFindController.matches(of: "aa", in: "aaaa")
        XCTAssertEqual(matches.map(\.start), [0, 2])
    }

    func testEmptyQueryHasNoMatches() {
        XCTAssertTrue(NoteFindController.matches(of: "   ", in: "anything").isEmpty)
    }

    func testNextAndPreviousWrap() {
        let matches = NoteFindController.matches(of: "x", in: "x-x-x")
        XCTAssertEqual(NoteFindController.nextMatchIndex(matches: matches, fromCaret: 0), 0)
        XCTAssertEqual(NoteFindController.nextMatchIndex(matches: matches, fromCaret: 1), 1)
        XCTAssertEqual(NoteFindController.nextMatchIndex(matches: matches, fromCaret: 5), 0, "wraps to start")
        XCTAssertEqual(NoteFindController.previousMatchIndex(matches: matches, fromCaret: 5), 1)
        XCTAssertEqual(NoteFindController.previousMatchIndex(matches: matches, fromCaret: 0), 2, "wraps to end")
    }

    /// The classic replace-all bug: earlier replacements shifting later offsets. Back-to-front
    /// emission means applying the batch front-to-back through the engine stays correct.
    func testReplaceAllOffsetsSurviveLengthChanges() {
        let text = "cat and cat and cat"
        var metadata = NoteMetadata.empty
        metadata.blocks = [
            Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: text.utf16.count), level: nil, icon: nil)
        ]
        var doc = NoteDocument(text: text, metadata: metadata)

        let matches = NoteFindController.matches(of: "cat", in: text)
        let commands = NoteFindController.replacementCommands(matches: matches, replacement: "elephant")
        for command in commands {
            doc = EditCommandEngine.apply(command, to: doc)
        }
        XCTAssertEqual(doc.text, "elephant and elephant and elephant")
    }

    func testReplaceAllWithShorterReplacement() {
        let text = "longword longword"
        var metadata = NoteMetadata.empty
        metadata.blocks = [
            Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: text.utf16.count), level: nil, icon: nil)
        ]
        var doc = NoteDocument(text: text, metadata: metadata)
        let commands = NoteFindController.replacementCommands(
            matches: NoteFindController.matches(of: "longword", in: text),
            replacement: "x"
        )
        for command in commands {
            doc = EditCommandEngine.apply(command, to: doc)
        }
        XCTAssertEqual(doc.text, "x x")
    }
}

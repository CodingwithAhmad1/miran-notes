import XCTest

@testable import MiranNotesApp

final class SlashQueryDetectorTests: XCTestCase {
    func testSlashOnlyOpensEmptyQuery() {
        let m = SlashQueryDetector.match(text: "/", selectedRange: NSRange(location: 1, length: 0))
        XCTAssertEqual(m?.queryText, "")
        XCTAssertEqual(m?.queryRange, NSRange(location: 0, length: 1))
    }

    func testPartialSlashQueryMatches() {
        let m = SlashQueryDetector.match(text: "/bul", selectedRange: NSRange(location: 4, length: 0))
        XCTAssertEqual(m?.queryText, "bul")
        XCTAssertEqual(m?.queryRange, NSRange(location: 0, length: 4))
    }

    func testMultilineSlashMatchesLinePrefixOnly() {
        let text = "hello\n/ca"
        let m = SlashQueryDetector.match(text: text, selectedRange: NSRange(location: text.utf16.count, length: 0))
        XCTAssertEqual(m?.queryText, "ca")
        XCTAssertEqual(m?.queryRange, NSRange(location: 6, length: 3))
    }

    func testWhitespaceAfterSlashClosesQueryContext() {
        let m = SlashQueryDetector.match(text: "/doesnt work", selectedRange: NSRange(location: 11, length: 0))
        XCTAssertNil(m)
    }

    func testSelectionRangeDisablesQuery() {
        let m = SlashQueryDetector.match(text: "/h1", selectedRange: NSRange(location: 1, length: 1))
        XCTAssertNil(m)
    }
}

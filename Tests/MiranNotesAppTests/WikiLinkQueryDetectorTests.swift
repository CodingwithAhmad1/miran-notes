import Foundation
import XCTest

@testable import MiranNotesApp

final class WikiLinkQueryDetectorTests: XCTestCase {
    private func match(_ text: String, caret: Int) -> WikiLinkQueryMatch? {
        WikiLinkQueryDetector.match(text: text, selectedRange: NSRange(location: caret, length: 0))
    }

    func testBareOpenBracketsAtLineStart() {
        let m = match("[[", caret: 2)
        XCTAssertEqual(m, WikiLinkQueryMatch(fullRange: NSRange(location: 0, length: 2), queryText: ""))
    }

    func testQueryAfterBrackets() {
        let m = match("[[proj", caret: 6)
        XCTAssertEqual(m, WikiLinkQueryMatch(fullRange: NSRange(location: 0, length: 6), queryText: "proj"))
    }

    func testMidLineQuery() {
        let text = "see also [[idea"
        let m = match(text, caret: (text as NSString).length)
        XCTAssertEqual(m, WikiLinkQueryMatch(fullRange: NSRange(location: 9, length: 6), queryText: "idea"))
    }

    func testCaretInsideQueryUsesPrefixOnly() {
        // caret after "[[pr" in "[[proj" — query is what's typed so far before the caret
        let m = match("[[proj", caret: 4)
        XCTAssertEqual(m, WikiLinkQueryMatch(fullRange: NSRange(location: 0, length: 4), queryText: "pr"))
    }

    func testClosedPairDoesNotMatch() {
        let text = "[[done]]"
        XCTAssertNil(match(text, caret: (text as NSString).length))
    }

    func testStrayClosingBracketRejects() {
        XCTAssertNil(match("[[a]b", caret: 5))
    }

    func testSecondOpenPairWins() {
        let text = "[[first]] and [[sec"
        let m = match(text, caret: (text as NSString).length)
        XCTAssertEqual(m?.queryText, "sec")
        XCTAssertEqual(m?.fullRange, NSRange(location: 14, length: 5))
    }

    func testSingleBracketDoesNotMatch() {
        XCTAssertNil(match("[note", caret: 5))
    }

    func testNoMatchOnOtherLine() {
        let text = "[[open\nnext line"
        // caret on the second line: the unclosed [[ is on the previous line
        XCTAssertNil(match(text, caret: (text as NSString).length))
    }

    func testSelectionRangeRejects() {
        XCTAssertNil(WikiLinkQueryDetector.match(text: "[[abc", selectedRange: NSRange(location: 2, length: 3)))
    }

    func testTripleBracketMatchesInnerPair() {
        let m = match("[[[x", caret: 4)
        XCTAssertEqual(m?.queryText, "x")
        XCTAssertEqual(m?.fullRange, NSRange(location: 1, length: 3))
    }

    func testQueryWithSpaces() {
        let text = "[[my note title"
        let m = match(text, caret: (text as NSString).length)
        XCTAssertEqual(m?.queryText, "my note title")
    }

    func testEmojiBeforeBracketsKeepsUTF16OffsetsCorrect() {
        let text = "😀 [[x"
        let ns = text as NSString
        let m = match(text, caret: ns.length)
        XCTAssertEqual(m?.queryText, "x")
        // 😀 is 2 UTF-16 units + space = offset 3
        XCTAssertEqual(m?.fullRange, NSRange(location: 3, length: 3))
    }

    func testCaretBeforeBracketsDoesNotMatch() {
        XCTAssertNil(match("[[abc", caret: 1))
    }
}

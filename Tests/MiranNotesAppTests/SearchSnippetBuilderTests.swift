import XCTest

@testable import MiranNotesApp

final class SearchSnippetBuilderTests: XCTestCase {
    func testSnippetAroundFirstCaseInsensitiveMatch() {
        let text = "Hello world\nSECRET here"
        let s = SearchSnippetBuilder.snippet(for: "secret", in: text)
        XCTAssertTrue(s.contains("SECRET"), "expected match window: \(s)")
        XCTAssertFalse(s.contains("\n"))
    }

    func testEmptyQueryReturnsEmptySnippet() {
        XCTAssertEqual(SearchSnippetBuilder.snippet(for: "", in: "hello"), "")
    }
}

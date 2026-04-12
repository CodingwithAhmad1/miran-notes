import XCTest
@testable import MiranNotesCore

final class TextEditDiffTests: XCTestCase {
    func testSingleInsertionReturnsOneRegion() {
        let old = "hello"
        let new = "heXllo"
        let diff = TextEditDiff.singleUTF16Replacement(from: old, to: new)
        XCTAssertNotNil(diff)
        XCTAssertEqual(diff?.range.location, 2)
        XCTAssertEqual(diff?.range.length, 0)
        XCTAssertEqual(diff?.replacement, "X")
    }

    func testSingleReplacementReturnsOneRegion() {
        let old = "abc"
        let new = "ayc"
        let diff = TextEditDiff.singleUTF16Replacement(from: old, to: new)
        XCTAssertNotNil(diff)
        XCTAssertEqual(diff?.range.location, 1)
        XCTAssertEqual(diff?.range.length, 1)
        XCTAssertEqual(diff?.replacement, "y")
    }

    func testMiddleSubstringReplacementIsSingleRegion() {
        let old = "abcdef"
        let new = "abXXef"
        let diff = TextEditDiff.singleUTF16Replacement(from: old, to: new)
        XCTAssertNotNil(diff)
        XCTAssertEqual(diff?.range.location, 2)
        XCTAssertEqual(diff?.range.length, 2)
        XCTAssertEqual(diff?.replacement, "XX")
    }

    func testIdenticalStringsReturnNil() {
        XCTAssertNil(TextEditDiff.singleUTF16Replacement(from: "same", to: "same"))
    }

    func testEmojiSingleCodepointEdit() {
        let old = "hi😀"
        let new = "hi😁"
        let diff = TextEditDiff.singleUTF16Replacement(from: old, to: new)
        XCTAssertNotNil(diff)
        XCTAssertEqual(old.count, new.count)
        XCTAssertEqual(new, (old as NSString).replacingCharacters(in: diff!.range, with: diff!.replacement))
    }

    func testSurrogatePairLengthUsesUTF16() {
        let s = "a🐱b"
        let old = s
        let new = "a🐶b"
        let diff = TextEditDiff.singleUTF16Replacement(from: old, to: new)
        XCTAssertNotNil(diff)
        XCTAssertEqual((new as NSString).length, (old as NSString).length)
    }
}

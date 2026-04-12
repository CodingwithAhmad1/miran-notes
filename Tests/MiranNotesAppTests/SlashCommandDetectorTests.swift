import XCTest
@testable import MiranNotesApp
import MiranNotesCore

final class SlashCommandDetectorTests: XCTestCase {
    func testH1SpaceAtLineStart() {
        let model = "/h1"
        let storage = "/h1 "
        let diff = (NSRange(location: 3, length: 0), " ")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.lineStartUTF16, 0)
        XCTAssertEqual(m?.commitUTF16Index, 3)
        XCTAssertEqual(m?.tokenWithoutSlash, "h1")
    }

    func testH2NewlineCommit() {
        let model = "/h2"
        let storage = "/h2\n"
        let diff = (NSRange(location: 3, length: 0), "\n")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.tokenWithoutSlash, "h2")
    }

    func testParagraphSpace() {
        let model = "/p"
        let storage = "/p "
        let diff = (NSRange(location: 2, length: 0), " ")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.tokenWithoutSlash, "p")
    }

    func testCodeSpace() {
        let model = "/code"
        let storage = "/code "
        let diff = (NSRange(location: 5, length: 0), " ")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.tokenWithoutSlash, "code")
    }

    func testNotLineStartNoMatch() {
        let model = "x/h1"
        let storage = "x/h1 "
        let diff = (NSRange(location: 4, length: 0), " ")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNil(m)
    }

    func testPartialTokenNoMatchWithoutCommit() {
        let model = "/h"
        let storage = "/h"
        let diff = (NSRange(location: 2, length: 0), "")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNil(m)
    }

    func testRegistryProducesHeadingCommands() {
        let match = SlashCommitMatch(lineStartUTF16: 0, commitUTF16Index: 3, tokenWithoutSlash: "h1")
        let cmds = SlashCommandRegistry.editCommands(for: match, blockID: "b0")
        XCTAssertEqual(cmds?.count, 2)
        guard case let .replaceText(r, rep) = cmds?[0] else {
            XCTFail()
            return
        }
        XCTAssertEqual(rep, "")
        XCTAssertEqual(r, TextRange(start: 0, length: 3))
        guard case let .changeBlockType(_, type, level) = cmds?[1] else {
            XCTFail()
            return
        }
        XCTAssertEqual(type, .heading)
        XCTAssertEqual(level, 1)
    }
}

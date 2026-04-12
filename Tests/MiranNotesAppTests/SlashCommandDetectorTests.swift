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
        XCTAssertEqual(m?.commitCharacter, .space)
        XCTAssertEqual(m?.tokenWithoutSlash, "h1")
    }

    func testH2NewlineCommit() {
        let model = "/h2"
        let storage = "/h2\n"
        let diff = (NSRange(location: 3, length: 0), "\n")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.commitCharacter, .newline)
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
        let match = SlashCommitMatch(
            lineStartUTF16: 0,
            commitUTF16Index: 3,
            commitCharacter: .space,
            tokenWithoutSlash: "h1"
        )
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

    func testListSpaceAtLineStartProducesListItemBlockType() {
        let model = "/list"
        let storage = "/list "
        let diff = (NSRange(location: 5, length: 0), " ")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNotNil(m)
        let cmds = SlashCommandRegistry.editCommands(for: m!, blockID: "b1")
        XCTAssertEqual(cmds?.count, 2)
        guard case let .changeBlockType(_, type, _) = cmds?[1] else { XCTFail(); return }
        XCTAssertEqual(type, .listItem)
    }

    func testDividerSpaceAtLineStartProducesDividerBlockType() {
        let model = "/divider"
        let storage = "/divider "
        let diff = (NSRange(location: 8, length: 0), " ")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNotNil(m)
        let cmds = SlashCommandRegistry.editCommands(for: m!, blockID: "b2")
        XCTAssertEqual(cmds?.count, 2)
        guard case let .changeBlockType(_, type, _) = cmds?[1] else { XCTFail(); return }
        XCTAssertEqual(type, .divider)
    }

    func testBulletAliasSpaceAtLineStartProducesListItemBlockType() {
        let model = "/bullet"
        let storage = "/bullet "
        let diff = (NSRange(location: 7, length: 0), " ")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNotNil(m)
        let cmds = SlashCommandRegistry.editCommands(for: m!, blockID: "b4")
        XCTAssertEqual(cmds?.count, 2)
        guard case let .changeBlockType(_, type, _) = cmds?[1] else { XCTFail(); return }
        XCTAssertEqual(type, .listItem)
    }

    func testCalloutSpaceAtLineStartProducesCalloutBlockType() {
        let model = "/callout"
        let storage = "/callout "
        let diff = (NSRange(location: 8, length: 0), " ")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNotNil(m)
        let cmds = SlashCommandRegistry.editCommands(for: m!, blockID: "b3")
        XCTAssertEqual(cmds?.count, 2)
        guard case let .changeBlockType(_, type, _) = cmds?[1] else { XCTFail(); return }
        XCTAssertEqual(type, .callout)
    }

    func testPartialListTokenDoesNotCommitBeforeSpace() {
        let model = "/lis"
        let storage = "/lis"
        let diff = (NSRange(location: 4, length: 0), "")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNil(m, "/lis without commit character should not produce a match")
    }

    func testPartialDividerTokenDoesNotCommitBeforeSpace() {
        let model = "/divide"
        let storage = "/divider"
        let diff = (NSRange(location: 7, length: 0), "r")
        let m = SlashCommandDetector.match(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNil(m, "/divider without trailing space/return should not produce a match")
    }

    func testMarkdownBulletMarkerAtLineStartConvertsToListItemCommands() {
        let model = "-"
        let storage = "- "
        let diff = (NSRange(location: 1, length: 0), " ")
        let m = MarkdownCommandDetector.bulletMatch(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNotNil(m)
        let markerRange = TextRange(start: m!.lineStartUTF16, length: m!.commitUTF16Index - m!.lineStartUTF16)
        XCTAssertEqual(markerRange, TextRange(start: 0, length: 1))
    }

    func testMarkdownBulletMarkerNotAtLineStartDoesNotMatch() {
        let model = "x-"
        let storage = "x- "
        let diff = (NSRange(location: 2, length: 0), " ")
        let m = MarkdownCommandDetector.bulletMatch(modelText: model, storageText: storage, insertion: diff)
        XCTAssertNil(m)
    }

    func testCatalogResolveListCommandProducesListItemChange() {
        let tokenRange = TextRange(start: 0, length: 4)
        let commands = SlashCommandRegistry.resolveCatalogCommand(
            catalogID: "list",
            queryTokenRange: tokenRange,
            blockID: "b1",
            blockType: .paragraph
        )
        XCTAssertEqual(commands?.count, 2)
        guard case let .changeBlockType(_, type, _) = commands?[1] else { XCTFail(); return }
        XCTAssertEqual(type, .listItem)
    }
}

import XCTest

@testable import MiranNotesApp

@MainActor
final class SlashCommandMatcherTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SlashCommandRegistry.registerBuiltins()
    }

    func testEmptyQueryReturnsFullCatalog() {
        let catalog = SlashCommandRegistry.catalogItems()
        let matches = SlashCommandMatcher.filterAndRank(query: "", catalog: catalog)
        XCTAssertEqual(matches.count, catalog.count)
    }

    func testPrefixQueryRanksHeadingFirst() {
        let catalog = SlashCommandRegistry.catalogItems()
        let matches = SlashCommandMatcher.filterAndRank(query: "h1", catalog: catalog)
        XCTAssertEqual(matches.first?.item.id, "h1")
    }

    func testAliasQueryFindsListCommand() {
        let catalog = SlashCommandRegistry.catalogItems()
        let matches = SlashCommandMatcher.filterAndRank(query: "bullet", catalog: catalog)
        XCTAssertEqual(matches.first?.item.id, "list")
    }

    func testUnknownQueryReturnsNoMatches() {
        let catalog = SlashCommandRegistry.catalogItems()
        let matches = SlashCommandMatcher.filterAndRank(query: "doesntwork", catalog: catalog)
        XCTAssertTrue(matches.isEmpty)
    }
}

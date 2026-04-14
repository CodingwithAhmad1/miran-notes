import AppKit
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

/// Tests for `EditorVisualStyle.apply(to:document:)`.
/// All tests use `NSTextStorage` + `NSTextView` directly — no window is required.
@MainActor
final class EditorVisualStyleTests: XCTestCase {
    // MARK: - Helpers

    private func makeTextView(text: String) -> NSTextView {
        let tv = NSTextView(frame: .zero)
        tv.textStorage?.setAttributedString(NSAttributedString(string: text))
        return tv
    }

    private func makeDocument(
        text: String,
        blockType: BlockType,
        headingLevel: Int? = nil,
        spans: [Span] = [],
        links: [NoteLink] = []
    ) -> NoteDocument {
        let noteID = UUID()
        return NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(
                        id: "b0",
                        type: blockType,
                        range: TextRange(start: 0, length: text.utf16.count),
                        level: headingLevel,
                        icon: nil
                    )
                ],
                spans: spans,
                links: links
            )
        )
    }

    // MARK: - Block font tests

    func testHeadingLevel1GetsBoldFontSize30() {
        let doc = makeDocument(text: "Hello", blockType: .heading, headingLevel: 1)
        let tv = makeTextView(text: doc.text)
        EditorVisualStyle.apply(to: tv, document: doc)
        let font = tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertEqual(font?.pointSize ?? 0, 30, accuracy: 0.1)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true,
                      "Heading 1 must have bold font")
    }

    func testHeadingLevel2GetsBoldFontSize24() {
        let doc = makeDocument(text: "Hello", blockType: .heading, headingLevel: 2)
        let tv = makeTextView(text: doc.text)
        EditorVisualStyle.apply(to: tv, document: doc)
        let font = tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, 24, accuracy: 0.1)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    func testHeadingLevel3GetsBoldFontSize20() {
        let doc = makeDocument(text: "Hello", blockType: .heading, headingLevel: 3)
        let tv = makeTextView(text: doc.text)
        EditorVisualStyle.apply(to: tv, document: doc)
        let font = tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, 20, accuracy: 0.1)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    func testCodeBlockGetsMonospaceFont() {
        let doc = makeDocument(text: "let x = 1", blockType: .code)
        let tv = makeTextView(text: doc.text)
        EditorVisualStyle.apply(to: tv, document: doc)
        let font = tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
                      "Code block must use a monospace font")
    }

    func testBodyFontForParagraph() {
        let doc = makeDocument(text: "Body text", blockType: .paragraph)
        let tv = makeTextView(text: doc.text)
        EditorVisualStyle.apply(to: tv, document: doc)
        let font = tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, EditorVisualStyle.bodyPointSize, accuracy: 0.1)
    }

    func testBodyFontForListItem() {
        let doc = makeDocument(text: "List item", blockType: .listItem)
        let tv = makeTextView(text: doc.text)
        EditorVisualStyle.apply(to: tv, document: doc)
        let font = tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, EditorVisualStyle.bodyPointSize, accuracy: 0.1)
    }

    func testBodyFontForCallout() {
        let doc = makeDocument(text: "Callout text", blockType: .callout)
        let tv = makeTextView(text: doc.text)
        EditorVisualStyle.apply(to: tv, document: doc)
        let font = tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, EditorVisualStyle.bodyPointSize, accuracy: 0.1)
    }

    // MARK: - Span style tests

    func testBoldSpanGetsBoldAttribute() {
        let text = "hello"
        let doc = makeDocument(
            text: text,
            blockType: .paragraph,
            spans: [Span(range: TextRange(start: 0, length: 5), style: .bold)]
        )
        let tv = makeTextView(text: doc.text)
        EditorVisualStyle.apply(to: tv, document: doc)
        let font = tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true,
                      "Bold span must apply .boldFontMask")
    }

    func testItalicSpanGetsItalicAttribute() {
        let text = "hello"
        let doc = makeDocument(
            text: text,
            blockType: .paragraph,
            spans: [Span(range: TextRange(start: 0, length: 5), style: .italic)]
        )
        let tv = makeTextView(text: doc.text)
        EditorVisualStyle.apply(to: tv, document: doc)
        let font = tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.italic) == true,
                      "Italic span must apply .italicFontMask")
    }

    func testCodeSpanGetsMonospaceFont() {
        let text = "hello"
        let doc = makeDocument(
            text: text,
            blockType: .paragraph,
            spans: [Span(range: TextRange(start: 0, length: 5), style: .code)]
        )
        let tv = makeTextView(text: doc.text)
        EditorVisualStyle.apply(to: tv, document: doc)
        let font = tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
                      "Code span must use a monospace font")
    }

    func testLinkForegroundColorFollowsWikiPresentationPolicy() {
        let text = "[[link]]"
        let targetID = UUID()
        let doc = makeDocument(
            text: text,
            blockType: .paragraph,
            links: [NoteLink(range: TextRange(start: 0, length: text.utf16.count), targetNoteID: targetID)]
        )
        let tv = makeTextView(text: doc.text)
        EditorVisualStyle.apply(to: tv, document: doc)
        let color = tv.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color, "Link range must have a foreground color attribute")
        if WikiLinkPresentationPolicy.isFrontendEnabled {
            XCTAssertNotEqual(color, NSColor.textColor, "Link color must differ from default body text color")
        } else {
            XCTAssertEqual(color, NSColor.textColor, "When wiki link presentation is off, link spans use body color")
        }
    }

    // MARK: - SlashCommandRegistry

    func testBuiltinsRegisteredAtStartup() {
        // Simulate startup registration
        SlashCommandRegistry.registerBuiltins()
        let items = SlashCommandRegistry.catalogItems()
        let ids = Set(items.map(\.id))
        // Core block commands (8). Planning may register additional commands in the same static catalog.
        let coreBuiltinIDs = Set(["h1", "h2", "h3", "p", "code", "list", "divider", "callout"])
        XCTAssertEqual(ids.intersection(coreBuiltinIDs), coreBuiltinIDs, "All core built-in slash commands must be registered")
    }

    func testRegisterCustomDescriptorAppearsInCatalog() {
        SlashCommandRegistry.registerBuiltins()
        let customID = "custom-test-\(UUID().uuidString)"
        let descriptor = SlashCommandDescriptor(
            id: customID,
            title: "Custom",
            category: "Test",
            aliases: [],
            keywords: [],
            preview: "A custom test command.",
            commitPolicy: [.space],
            applicability: nil,
            produce: { _, _, _ in nil }
        )
        SlashCommandRegistry.register(descriptor)
        let ids = SlashCommandRegistry.catalogItems().map(\.id)
        XCTAssertTrue(ids.contains(customID), "Custom descriptor must appear in catalog after registration")
    }

    func testDuplicateRegistrationIsIdempotent() {
        SlashCommandRegistry.registerBuiltins()
        let countBefore = SlashCommandRegistry.catalogItems().count
        // Re-register a built-in — should be a no-op
        let dup = SlashCommandDescriptor(
            id: "h1",
            title: "Duplicate H1",
            category: "Test",
            aliases: [],
            keywords: [],
            preview: "Duplicate.",
            commitPolicy: [.space],
            applicability: nil,
            produce: { _, _, _ in nil }
        )
        SlashCommandRegistry.register(dup)
        let countAfter = SlashCommandRegistry.catalogItems().count
        XCTAssertEqual(countBefore, countAfter, "Duplicate registration must be idempotent")
    }
}

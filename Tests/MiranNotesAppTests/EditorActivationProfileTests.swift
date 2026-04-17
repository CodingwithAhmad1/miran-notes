import Foundation
@testable import MiranNotesApp
import MiranNotesCore
import Testing

@Suite("Editor activation profile")
struct EditorActivationProfileTests {
    @Test("shipping default is block native")
    func shippingDefault() {
        let p = EditorActivationProfile.shippingDefault
        #expect(p.editorKind == .blockNative)
        #expect(p.modules == .blockNativeDefault)
        #expect(p.effectiveModules == p.modules)
    }

    @Test("environment resolve maps markdown aliases")
    func resolveMarkdownAliases() {
        for raw in ["markdown", "Markdown", "plain", "plainMarkdown", "plain_markdown", "plainMarkdownSource"] {
            let p = EditorActivationProfile.resolve(kindRaw: raw)
            #expect(p.editorKind == .plainMarkdownSource)
            #expect(p.effectiveModules.blockChrome == false)
            #expect(p.effectiveModules.slashMenu == false)
            #expect(p.effectiveModules.layoutControllerNewlineRules == false)
        }
    }

    @Test("resolve empty falls back to shipping")
    func resolveEmpty() {
        #expect(EditorActivationProfile.resolve(kindRaw: nil) == .shippingDefault)
        #expect(EditorActivationProfile.resolve(kindRaw: "") == .shippingDefault)
        #expect(EditorActivationProfile.resolve(kindRaw: "   ") == .shippingDefault)
    }

    @Test("plain markdown effective modules allow opt-in markdown shortcuts")
    func plainMarkdownEffectiveModules() {
        var stored = EditorModuleFlags.plainMarkdownDefault
        stored.markdownShortcutDetector = true
        let p = EditorActivationProfile(editorKind: .plainMarkdownSource, modules: stored)
        #expect(p.effectiveModules.markdownShortcutDetector == true)
        #expect(p.effectiveModules.blockChrome == false)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = EditorActivationProfile(
            editorKind: .plainMarkdownSource,
            modules: EditorModuleFlags(
                blockChrome: false,
                slashMenu: true,
                markdownShortcutDetector: true,
                wikiLinkClickThrough: false,
                layoutControllerNewlineRules: false
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EditorActivationProfile.self, from: data)
        #expect(decoded == original)
    }

    @Test("replaceText edits with a single block normalize for save")
    func replaceTextNormalizationInvariant() throws {
        let noteID = UUID()
        var doc = NoteDocument(
            text: "hello",
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(
                        id: "b0",
                        type: .paragraph,
                        range: TextRange(start: 0, length: 5),
                        level: nil,
                        icon: nil
                    )
                ],
                spans: []
            )
        )
        doc = EditCommandEngine.apply(
            .replaceText(range: TextRange(start: 5, length: 0), replacement: "\nworld"),
            to: doc
        )
        let normalized = RangeNormalizer.normalize(metadata: doc.metadata, for: doc.text)
        #expect(doc.text.contains("world"))
        #expect(NoteIntegrity.check(document: NoteDocument(text: doc.text, metadata: normalized.normalizedMetadata)).isValid)
    }
}

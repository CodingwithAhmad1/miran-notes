import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class WikiLinkSyntaxReconcilerTests: XCTestCase {
    private func emptyMeta(noteID: UUID, text: String) -> NoteMetadata {
        let len = (text as NSString).length
        return NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
            noteID: noteID,
            blocks: [
                Block(
                    id: "b1",
                    type: .paragraph,
                    range: TextRange(start: 0, length: len),
                    level: nil,
                    icon: nil
                ),
            ],
            spans: [],
            links: []
        )
    }

    func testReconcilesWikiLinkMatchingDisplayTitle() {
        let targetID = UUID()
        let sourceID = UUID()
        var manifest = VaultManifest()
        manifest.upsert(noteID: targetID, relativePath: "topic/my-note", title: nil)

        let text = "Link to [[My Note]] here."
        let doc = NoteDocument(text: text, metadata: emptyMeta(noteID: sourceID, text: text))
        let out = WikiLinkSyntaxReconciler.reconciledDocument(document: doc, manifest: manifest)
        XCTAssertEqual(out?.metadata.links.count, 1)
        XCTAssertEqual(out?.metadata.links.first?.targetNoteID, targetID)
        XCTAssertEqual(out?.metadata.links.first?.range.start, (text as NSString).range(of: "[[My Note]]").location)
    }

    func testReconcilesPipeAliasForm() {
        let targetID = UUID()
        let sourceID = UUID()
        var manifest = VaultManifest()
        manifest.upsert(noteID: targetID, relativePath: "t/other", title: nil)

        let text = "[[see|Other]]"
        let doc = NoteDocument(text: text, metadata: emptyMeta(noteID: sourceID, text: text))
        let out = WikiLinkSyntaxReconciler.reconciledDocument(document: doc, manifest: manifest)
        XCTAssertEqual(out?.metadata.links.count, 1)
        XCTAssertEqual(out?.metadata.links.first?.targetNoteID, targetID)
        XCTAssertEqual(out?.metadata.links.first?.label, "see")
    }

    func testSkipsWhenLinksAlreadyPresent() {
        let id = UUID()
        var manifest = VaultManifest()
        manifest.upsert(noteID: id, relativePath: "a", title: nil)

        var meta = emptyMeta(noteID: UUID(), text: "[[A]]")
        meta.links = [NoteLink(range: TextRange(start: 0, length: 5), targetNoteID: id, label: nil)]
        let doc = NoteDocument(text: "[[A]]", metadata: meta)
        let out = WikiLinkSyntaxReconciler.reconciledDocument(document: doc, manifest: manifest)
        XCTAssertNil(out)
    }
}

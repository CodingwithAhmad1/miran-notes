import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class LinkResolverTests: XCTestCase {
    func testResolverReturnsBaseNameForNoteID() {
        let id = UUID()
        let manifest = VaultManifest(
            entries: [
                ManifestEntry(noteID: id, relativePath: "my-note", title: "My Note")
            ]
        )
        let resolver = LinkResolver(manifest: manifest)
        XCTAssertEqual(resolver.baseName(forTargetNoteID: id), "my-note")
        XCTAssertNil(resolver.baseName(forTargetNoteID: UUID()))
    }

    func testResolverNoteIDForBaseName() {
        let id = UUID()
        let manifest = VaultManifest(
            entries: [
                ManifestEntry(noteID: id, relativePath: "alpha", title: nil)
            ]
        )
        let resolver = LinkResolver(manifest: manifest)
        XCTAssertEqual(resolver.noteID(forBaseName: "alpha"), id)
        XCTAssertNil(resolver.noteID(forBaseName: "missing"))
    }
}

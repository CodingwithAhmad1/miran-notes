import XCTest

@testable import MiranNotesCore

final class InfrastructureContractTests: XCTestCase {
    func testTableColumnTypeValidation() {
        XCTAssertTrue(TableColumnType.number.accepts("42.5"))
        XCTAssertFalse(TableColumnType.number.accepts("abc"))
        XCTAssertTrue(TableColumnType.boolean.accepts("true"))
        XCTAssertFalse(TableColumnType.boolean.accepts("maybe"))
    }

    func testNoteDocumentIdDelegatestoMetadataNoteID() {
        let noteID = UUID()
        let meta = NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
            noteID: noteID,
            blocks: [],
            spans: []
        )
        let doc = NoteDocument(text: "hello", metadata: meta)
        XCTAssertEqual(doc.id, noteID, "NoteDocument.id must equal metadata.noteID — single identity source")
        XCTAssertEqual(doc.id, doc.metadata.noteID)
    }

    func testExtensionCompatibilityRequiresCapabilitiesAndVersion() {
        let descriptor = ExtensionDescriptor(
            id: "ext.sample",
            version: 1,
            capabilities: [.commandInterception, .commandProduction]
        )
        XCTAssertTrue(
            ExtensionCompatibility.supports(
                descriptor: descriptor,
                requiredVersion: .v1,
                requiredCapabilities: [.commandInterception]
            )
        )
        XCTAssertFalse(
            ExtensionCompatibility.supports(
                descriptor: descriptor,
                requiredVersion: .v1,
                requiredCapabilities: [.syncHooks]
            )
        )
    }
}

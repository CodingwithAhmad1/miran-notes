import XCTest

@testable import MiranNotesCore

/// Sidecars written by pre-cleanup builds may carry `artifacts` / `databaseRowReferences`.
/// Those keys are no longer modeled; decoding must ignore them rather than fail.
final class NoteMetadataLegacyKeysDecodingTests: XCTestCase {
    func testDecodingSidecarWithLegacyArtifactKeysSucceeds() throws {
        let noteID = UUID()
        let json = """
        {
          "schemaVersion": 2,
          "noteID": "\(noteID.uuidString)",
          "blocks": [
            {"id": "b0", "type": "paragraph", "range": {"start": 0, "length": 5}}
          ],
          "spans": [],
          "links": [],
          "artifacts": [
            {"id": "\(UUID().uuidString)", "kind": "databaseView", "relativePath": "views/foo.json"},
            {"id": "\(UUID().uuidString)", "kind": "table", "relativePath": "tables/bar.jsonl"}
          ],
          "databaseRowReferences": [
            {"databaseID": "\(UUID().uuidString)", "rowID": "\(UUID().uuidString)", "blockID": "b0"}
          ],
          "properties": {"status": "draft"}
        }
        """
        let metadata = try JSONDecoder().decode(NoteMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(metadata.noteID, noteID)
        XCTAssertEqual(metadata.blocks.count, 1)
        XCTAssertEqual(metadata.properties["status"], "draft")
    }

    func testEncodedSidecarOmitsLegacyKeys() throws {
        let data = try JSONEncoder().encode(NoteMetadata.empty)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["artifacts"])
        XCTAssertNil(object["databaseRowReferences"])
    }
}

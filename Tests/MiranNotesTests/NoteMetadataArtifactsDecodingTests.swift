import XCTest
@testable import MiranNotesCore

final class NoteMetadataArtifactsDecodingTests: XCTestCase {
    func testDecodingDropsLegacyTableArtifacts() throws {
        let json = """
        {
          "schemaVersion": 2,
          "noteID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "blocks": [],
          "spans": [],
          "links": [],
          "artifacts": [
            {"id":"11111111-2222-3333-4444-555555555555","kind":"table","relativePath":"tables/legacy.jsonl"},
            {"id":"66666666-7777-8888-9999-AAAAAAAAAAAA","kind":"databaseView","relativePath":"views/keep.json"}
          ],
          "databaseRowReferences": [],
          "properties": {}
        }
        """
        let data = Data(json.utf8)
        let meta = try JSONDecoder().decode(NoteMetadata.self, from: data)
        XCTAssertEqual(meta.artifacts.count, 1)
        XCTAssertEqual(meta.artifacts.first?.id, UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA"))
        XCTAssertEqual(meta.artifacts.first?.kind, .databaseView)
        XCTAssertEqual(meta.artifacts.first?.relativePath, "views/keep.json")
    }

    func testDecodingSkipsUnknownArtifactKinds() throws {
        let json = """
        {
          "schemaVersion": 2,
          "noteID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "blocks": [],
          "spans": [],
          "links": [],
          "artifacts": [
            {"id":"11111111-2222-3333-4444-555555555555","kind":"futureKind","relativePath":"x/y"}
          ],
          "databaseRowReferences": [],
          "properties": {}
        }
        """
        let data = Data(json.utf8)
        let meta = try JSONDecoder().decode(NoteMetadata.self, from: data)
        XCTAssertTrue(meta.artifacts.isEmpty)
    }
}

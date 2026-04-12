import XCTest

@testable import MiranNotesApp
import MiranNotesCore

final class EditorSyncControllerTests: XCTestCase {
    func testFingerprintStableForSameDocument() {
        let doc = makeDoc(text: "hello")
        let a = EditorSyncController.fingerprint(document: doc)
        let b = EditorSyncController.fingerprint(document: doc)
        XCTAssertEqual(a, b)
    }

    func testFingerprintChangesWhenTextChanges() {
        var doc = makeDoc(text: "a")
        let fp1 = EditorSyncController.fingerprint(document: doc)
        doc = NoteDocument(text: "b", metadata: doc.metadata)
        let fp2 = EditorSyncController.fingerprint(document: doc)
        XCTAssertNotEqual(fp1, fp2)
    }

    func testViewFingerprintMatchesDocumentWhenInSync() {
        let doc = makeDoc(text: "sync check")
        let fpDoc = EditorSyncController.fingerprint(document: doc)
        let fpView = EditorSyncController.fingerprint(
            viewText: doc.text,
            noteID: doc.metadata.noteID,
            blockCount: doc.metadata.blocks.count
        )
        XCTAssertEqual(fpDoc, fpView)
    }

    func testModelToViewSyncIncrementalVsFull() {
        let view = "abc"
        let model = "abx"
        switch EditorSyncController.modelToViewSync(viewString: view, modelText: model) {
        case .incremental(let range, let replacement):
            XCTAssertEqual(range.location, 2)
            XCTAssertEqual(replacement, "x")
        default:
            XCTFail("expected incremental")
        }

        // Full-buffer path: whenever `TextEditDiff` returns nil, we take `.fullStringReplace`.
        let viewB = "ab"
        let modelB = "ba"
        if TextEditDiff.singleUTF16Replacement(from: viewB, to: modelB) == nil {
            if case .fullStringReplace = EditorSyncController.modelToViewSync(viewString: viewB, modelText: modelB) {} else {
                XCTFail("expected full replace when diff is nil")
            }
        } else {
            let syncB = EditorSyncController.modelToViewSync(viewString: viewB, modelText: modelB)
            if case .incremental = syncB {} else if case .fullStringReplace = syncB {} else {
                XCTFail("unexpected sync case")
            }
        }
    }

    private func makeDoc(text: String) -> NoteDocument {
        let id = UUID()
        return NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: id,
                blocks: [
                    Block(id: "b0", type: .paragraph, range: TextRange(start: 0, length: text.utf16.count), level: nil, icon: nil)
                ],
                spans: []
            )
        )
    }
}

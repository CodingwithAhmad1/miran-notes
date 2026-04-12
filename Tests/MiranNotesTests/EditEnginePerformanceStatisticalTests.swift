import CoreFoundation
import XCTest
@testable import MiranNotesCore

/// CI-friendly statistical harness: median wall time over repeated iterations (no Xcode baseline files).
final class EditEnginePerformanceStatisticalTests: XCTestCase {
    private func makeDocument(text: String) -> NoteDocument {
        let noteID = UUID()
        return NoteDocument(
            text: text,
            metadata: NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(
                        id: "b0",
                        type: .paragraph,
                        range: TextRange(start: 0, length: text.utf16.count),
                        level: nil,
                        icon: nil
                    )
                ],
                spans: []
            )
        )
    }

    func testMedianSequentialInsertsUnderThreshold() {
        let longText = String(repeating: "a", count: 10_000)
        let iterations = 10
        let innerOps = 200
        var samples: [Double] = []
        samples.reserveCapacity(iterations)

        for _ in 0..<iterations {
            var doc = makeDocument(text: longText)
            let start = CFAbsoluteTimeGetCurrent()
            for i in 0..<innerOps {
                let len = doc.text.utf16.count
                let loc = len == 0 ? 0 : (i * 17_971 + 11) % (len + 1)
                doc = EditCommandEngine.apply(
                    .replaceText(range: TextRange(start: loc, length: 0), replacement: "x"),
                    to: doc
                )
            }
            samples.append(CFAbsoluteTimeGetCurrent() - start)
        }

        samples.sort()
        let median = samples[samples.count / 2]
        // Loose threshold (seconds) — tune per CI; fails only on large regressions.
        XCTAssertLessThan(median, 0.35, "Median edit-engine time too high: \(median)s")
    }
}

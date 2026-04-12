import Foundation
import MiranNotesCore

/// Line-start "- " marker committed with space and represented as a single insertion in storage.
struct MarkdownBulletCommitMatch: Equatable {
    var lineStartUTF16: Int
    /// UTF-16 index of the inserted commit space in `storageText`.
    var commitUTF16Index: Int
}

enum MarkdownCommandDetector {
    static func bulletMatch(
        modelText: String,
        storageText: String,
        insertion: (range: NSRange, replacement: String)
    ) -> MarkdownBulletCommitMatch? {
        let diff = insertion
        guard diff.range.length == 0 else { return nil }
        guard diff.replacement == " " else { return nil }

        guard let single = TextEditDiff.singleUTF16Replacement(from: modelText, to: storageText),
              NSEqualRanges(single.range, diff.range),
              single.replacement == diff.replacement else {
            return nil
        }

        let commitIndex = diff.range.location
        let nsStorage = storageText as NSString
        let len = nsStorage.length
        guard commitIndex >= 0, commitIndex < len else { return nil }

        let lineStart = nsStorage.lineRange(for: NSRange(location: commitIndex, length: 0)).location
        guard lineStart < len else { return nil }
        guard commitIndex >= lineStart else { return nil }

        let tokenLen = commitIndex - lineStart
        guard tokenLen == 1 else { return nil }
        let token = nsStorage.substring(with: NSRange(location: lineStart, length: tokenLen))
        guard token == "-" else { return nil }

        return MarkdownBulletCommitMatch(
            lineStartUTF16: lineStart,
            commitUTF16Index: commitIndex
        )
    }
}

import Foundation
import MiranNotesCore

/// Line-start `/token` committed with Space or Return (storage includes the commit char; model does not yet).
struct SlashCommitMatch: Equatable {
    enum CommitCharacter: Equatable {
        case space
        case newline
    }

    var lineStartUTF16: Int
    /// UTF-16 index of the commit character in `storageText`.
    var commitUTF16Index: Int
    var commitCharacter: CommitCharacter
    var tokenWithoutSlash: String
}

enum SlashCommandDetector {
    /// Returns a match when `insertion` is a single space/newline insert at line start `/…` and `storageText` matches that edit.
    static func match(
        modelText: String,
        storageText: String,
        insertion: (range: NSRange, replacement: String)
    ) -> SlashCommitMatch? {
        let diff = insertion
        guard diff.range.length == 0 else { return nil }
        let rep = diff.replacement
        guard rep == " " || rep == "\n" else { return nil }
        guard rep.utf16.count == 1 else { return nil }

        guard let single = TextEditDiff.singleUTF16Replacement(from: modelText, to: storageText),
              NSEqualRanges(single.range, diff.range),
              single.replacement == diff.replacement else {
            return nil
        }

        let commitIndex = diff.range.location
        let ns = storageText as NSString
        let len = ns.length
        guard commitIndex >= 0, commitIndex < len else { return nil }

        let lineStart = ns.lineRange(for: NSRange(location: commitIndex, length: 0)).location
        guard lineStart < len else { return nil }

        if lineStart > 0 {
            let prev = ns.substring(with: NSRange(location: lineStart - 1, length: 1))
            guard prev == "\n" else { return nil }
        }

        guard ns.substring(with: NSRange(location: lineStart, length: min(1, len - lineStart))) == "/" else {
            return nil
        }

        guard commitIndex >= lineStart else { return nil }
        let tokenLen = commitIndex - lineStart
        guard tokenLen >= 1 else { return nil }

        let tokenWithSlash = ns.substring(with: NSRange(location: lineStart, length: tokenLen))
        guard tokenWithSlash.hasPrefix("/") else { return nil }

        let tokenWithoutSlash = String(tokenWithSlash.dropFirst())
        guard !tokenWithoutSlash.isEmpty else { return nil }
        let commitCharacter: SlashCommitMatch.CommitCharacter = rep == " " ? .space : .newline

        return SlashCommitMatch(
            lineStartUTF16: lineStart,
            commitUTF16Index: commitIndex,
            commitCharacter: commitCharacter,
            tokenWithoutSlash: tokenWithoutSlash
        )
    }
}

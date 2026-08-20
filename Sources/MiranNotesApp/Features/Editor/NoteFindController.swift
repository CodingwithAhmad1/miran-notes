import Foundation
import MiranNotesCore

/// Pure find/replace math for the in-note find bar. Replacement goes through `EditCommand.replaceText`
/// batches (never `NSTextFinder`, which would bypass the engine and the `EditorSyncController` contract).
enum NoteFindController {
    /// Non-overlapping, case- and diacritic-insensitive matches in document order.
    static func matches(of query: String, in text: String) -> [MiranNotesCore.TextRange] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let ns = text as NSString
        let fullLength = ns.length
        var result: [MiranNotesCore.TextRange] = []
        var searchStart = 0
        while searchStart < fullLength {
            let r = ns.range(
                of: q,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: NSRange(location: searchStart, length: fullLength - searchStart)
            )
            guard r.location != NSNotFound, r.length > 0 else { break }
            result.append(MiranNotesCore.TextRange(start: r.location, length: r.length))
            searchStart = r.location + r.length
        }
        return result
    }

    /// Index of the match to jump to from `caret` going forward (wrapping), nil when there are no matches.
    static func nextMatchIndex(matches: [MiranNotesCore.TextRange], fromCaret caret: Int) -> Int? {
        guard !matches.isEmpty else { return nil }
        return matches.firstIndex(where: { $0.start >= caret }) ?? 0
    }

    /// Index of the match to jump to from `caret` going backward (wrapping), nil when there are no matches.
    static func previousMatchIndex(matches: [MiranNotesCore.TextRange], fromCaret caret: Int) -> Int? {
        guard !matches.isEmpty else { return nil }
        return matches.lastIndex(where: { $0.end < caret }) ?? (matches.count - 1)
    }

    /// One `replaceText` per match, emitted **back-to-front** so earlier offsets stay valid; apply
    /// as a single batch for one undo step.
    static func replacementCommands(matches: [MiranNotesCore.TextRange], replacement: String) -> [EditCommand] {
        matches
            .sorted { $0.start > $1.start }
            .map { .replaceText(range: $0, replacement: replacement) }
    }
}

import Foundation

/// In-progress `[[` note-link query (for example `[[`, `[[proj`, `mid-line text [[idea`).
struct WikiLinkQueryMatch: Equatable {
    /// UTF-16 range from the opening `[[` through the caret (brackets included, caret exclusive).
    var fullRange: NSRange
    /// Text typed after `[[` up to the caret.
    var queryText: String
}

/// Detects an unclosed `[[` before the caret on the current line. Unlike ``SlashQueryDetector``
/// (line-start only by contract), wiki-link autocomplete works anywhere in a line.
enum WikiLinkQueryDetector {
    static func match(text: String, selectedRange: NSRange) -> WikiLinkQueryMatch? {
        guard selectedRange.length == 0 else { return nil }
        let ns = text as NSString
        let len = ns.length
        let caret = selectedRange.location
        guard caret >= 0, caret <= len else { return nil }

        let lineRange = ns.lineRange(for: NSRange(location: min(caret, max(0, len - 1)), length: 0))
        let lineStart = lineRange.location
        guard caret >= lineStart, caret - lineStart >= 2 else { return nil }

        let linePrefix = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        guard let openIndex = lastOpenBracketPairIndex(in: linePrefix) else { return nil }

        let queryStart = linePrefix.index(openIndex, offsetBy: 2)
        let query = String(linePrefix[queryStart...])
        // Closed pairs, nested brackets, or a stray `]` mean this is not an in-progress link query.
        if query.contains("[") || query.contains("]") || query.contains(where: { $0.isNewline }) {
            return nil
        }

        let bracketUTF16Offset = linePrefix[..<openIndex].utf16.count
        let start = lineStart + bracketUTF16Offset
        return WikiLinkQueryMatch(
            fullRange: NSRange(location: start, length: caret - start),
            queryText: query
        )
    }

    /// Index of the last `[[` in `linePrefix`, or nil when there is none.
    private static func lastOpenBracketPairIndex(in linePrefix: String) -> String.Index? {
        guard let range = linePrefix.range(of: "[[", options: .backwards) else { return nil }
        return range.lowerBound
    }
}

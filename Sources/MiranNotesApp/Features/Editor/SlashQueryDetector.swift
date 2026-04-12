import Foundation

/// In-progress slash query for menu discovery (for example `/`, `/h`, `/bullet`).
struct SlashQueryMatch: Equatable {
    /// UTF-16 range from slash to current caret (exclusive of any trailing whitespace).
    var queryRange: NSRange
    /// Query text without the leading `/`.
    var queryText: String
}

enum SlashQueryDetector {
    static func match(
        text: String,
        selectedRange: NSRange
    ) -> SlashQueryMatch? {
        guard selectedRange.length == 0 else { return nil }
        let caret = selectedRange.location
        let ns = text as NSString
        let len = ns.length
        guard caret >= 0, caret <= len else { return nil }

        let lineRange = ns.lineRange(for: NSRange(location: min(caret, max(0, len - 1)), length: 0))
        let lineStart = lineRange.location
        guard caret >= lineStart else { return nil }

        let prefixLength = caret - lineStart
        guard prefixLength > 0 else { return nil }

        let linePrefix = ns.substring(with: NSRange(location: lineStart, length: prefixLength))
        guard linePrefix.hasPrefix("/") else { return nil }

        let queryText = String(linePrefix.dropFirst())
        if queryText.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return nil
        }

        return SlashQueryMatch(
            queryRange: NSRange(location: lineStart, length: prefixLength),
            queryText: queryText
        )
    }
}

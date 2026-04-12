import Foundation

enum SearchSnippetBuilder {
    /// Plain-text preview around the first case-insensitive occurrence of `query` in `text`. Newlines become spaces.
    static func snippet(for query: String, in text: String, contextUTF16: Int = 48) -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return "" }
        let ns = text as NSString
        let fullLen = ns.length
        guard fullLen > 0 else { return "" }
        let r = ns.range(of: q, options: [.caseInsensitive])
        guard r.location != NSNotFound else { return "" }
        let matchStart = r.location
        let matchEnd = r.location + r.length
        let winStart = Swift.max(0, matchStart - contextUTF16)
        let winEnd = Swift.min(fullLen, matchEnd + contextUTF16)
        let windowLen = winEnd - winStart
        var piece = ns.substring(with: NSRange(location: winStart, length: windowLen))
        if winStart > 0 { piece = "…" + piece }
        if winEnd < fullLen { piece += "…" }
        return piece.replacingOccurrences(of: "\n", with: " ")
    }
}

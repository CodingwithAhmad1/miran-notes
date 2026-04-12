import Foundation
import MiranNotesCore

enum BacklinkSnippetBuilder {
    /// A short plain-text preview around the link, using UTF-16 offsets. Newlines become spaces.
    static func snippet(around range: MiranNotesCore.TextRange, in text: String, contextUTF16: Int = 48) -> String {
        let ns = text as NSString
        let fullLen = ns.length
        guard fullLen > 0 else { return "" }
        let rStart = Swift.max(0, Swift.min(range.start, fullLen))
        let rEnd = Swift.max(rStart, Swift.min(range.end, fullLen))
        let winStart = Swift.max(0, rStart - contextUTF16)
        let winEnd = Swift.min(fullLen, rEnd + contextUTF16)
        let windowLen = winEnd - winStart
        var piece = ns.substring(with: NSRange(location: winStart, length: windowLen))
        if winStart > 0 { piece = "…" + piece }
        if winEnd < fullLen { piece += "…" }
        return piece.replacingOccurrences(of: "\n", with: " ")
    }
}

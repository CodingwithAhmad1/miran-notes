import Foundation

/// UTF-16–aligned diff helpers for reconciling `NSTextStorage` with the canonical document string.
public enum TextEditDiff {
    /// Returns a single contiguous UTF-16 edit that transforms `old` into `new`, or `nil` if more than one disjoint edit is required.
    public static func singleUTF16Replacement(from old: String, to new: String) -> (range: NSRange, replacement: String)? {
        if old == new { return nil }

        let o = old as NSString
        let n = new as NSString
        let oLen = o.length
        let nLen = n.length

        var start = 0
        while start < oLen && start < nLen && o.character(at: start) == n.character(at: start) {
            start += 1
        }

        var oEnd = oLen
        var nEnd = nLen
        while oEnd > start && nEnd > start && o.character(at: oEnd - 1) == n.character(at: nEnd - 1) {
            oEnd -= 1
            nEnd -= 1
        }

        let replacedLength = oEnd - start
        let replacement = n.substring(with: NSRange(location: start, length: nEnd - start))

        guard replacedLength >= 0, start + replacedLength <= oLen else { return nil }

        let merged = o.replacingCharacters(in: NSRange(location: start, length: replacedLength), with: replacement) as String
        guard merged == new else { return nil }

        return (NSRange(location: start, length: replacedLength), replacement)
    }
}

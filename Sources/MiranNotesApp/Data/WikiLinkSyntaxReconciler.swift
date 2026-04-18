import Foundation
import MiranNotesCore

/// Parses `[[…]]` wiki-style tokens from note bodies and aligns ``NoteMetadata/links`` when the sidecar has no links yet (e.g. imported `.md`).
enum WikiLinkSyntaxReconciler {
    private struct Token {
        var range: MiranNotesCore.TextRange
        var inner: String
    }

    static func shouldReconcile(document: NoteDocument) -> Bool {
        document.metadata.links.isEmpty
            && document.text.contains("[[")
            && document.text.contains("]]")
    }

    /// Returns a document with `metadata.links` populated for resolved tokens, or `nil` if nothing changed.
    static func reconciledDocument(document: NoteDocument, manifest: VaultManifest) -> NoteDocument? {
        guard shouldReconcile(document: document) else { return nil }
        let tokens = parseTokens(text: document.text)
        guard !tokens.isEmpty else { return nil }

        var newLinks: [NoteLink] = []
        newLinks.reserveCapacity(tokens.count)
        for t in tokens {
            guard let id = resolveTarget(inner: t.inner, manifest: manifest) else { continue }
            let label = displayLabelIfPiped(t.inner)
            newLinks.append(NoteLink(range: t.range, targetNoteID: id, label: label))
        }
        guard !newLinks.isEmpty else { return nil }

        var meta = document.metadata
        meta.links = newLinks
        let norm = RangeNormalizer.normalize(metadata: meta, for: document.text)
        let doc = NoteDocument(text: document.text, metadata: norm.normalizedMetadata)
        guard NoteIntegrity.check(document: doc).isValid else { return nil }
        return doc
    }

    // MARK: - Parse

    private static func parseTokens(text: String) -> [Token] {
        let ns = text as NSString
        let len = ns.length
        let lb = "[".utf16.first!
        let rb = "]".utf16.first!
        var i = 0
        var out: [Token] = []
        while i < len {
            if i + 1 < len, ns.character(at: i) == lb, ns.character(at: i + 1) == lb {
                let open = i
                var j = i + 2
                var closed = false
                while j + 1 < len {
                    if ns.character(at: j) == rb, ns.character(at: j + 1) == rb {
                        let innerStart = open + 2
                        let innerLen = j - innerStart
                        let inner = innerLen > 0 ? ns.substring(with: NSRange(location: innerStart, length: innerLen)) : ""
                        let fullLen = (j + 2) - open
                        out.append(Token(range: MiranNotesCore.TextRange(start: open, length: fullLen), inner: inner))
                        i = j + 2
                        closed = true
                        break
                    }
                    j += 1
                }
                if !closed {
                    i += 1
                }
            } else {
                i += 1
            }
        }
        return out
    }

    // MARK: - Resolve

    private static func displayLabelIfPiped(_ inner: String) -> String? {
        guard let r = inner.range(of: "|") else { return nil }
        let left = inner[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return left.isEmpty ? nil : String(left)
    }

    private static func linkKey(fromInner inner: String) -> String {
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = trimmed.range(of: "|", options: .backwards) {
            return String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    static func resolveTarget(inner: String, manifest: VaultManifest) -> UUID? {
        let key = linkKey(fromInner: inner)
        guard !key.isEmpty else { return nil }
        let keyLower = key.lowercased()

        for e in manifest.entries {
            if e.relativePath.lowercased() == keyLower {
                return e.noteID
            }
            let lastSeg = (e.relativePath as NSString).lastPathComponent
            if lastSeg.lowercased() == keyLower {
                return e.noteID
            }
            let title = (e.title?.isEmpty == false) ? e.title! : VaultPath.displayTitle(forRelativePath: lastSeg)
            if title.compare(key, options: .caseInsensitive) == .orderedSame {
                return e.noteID
            }
            let segDisplay = VaultPath.displayTitle(forRelativePath: lastSeg)
            if segDisplay.compare(key, options: .caseInsensitive) == .orderedSame {
                return e.noteID
            }
        }
        return nil
    }
}

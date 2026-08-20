import Foundation
import MiranNotesCore

/// Pure `NoteDocument` → Markdown conversion for File → Export. Blocks map to Markdown block
/// syntax; spans wrap their (block-clipped) ranges; wiki links stay literal (`[[Title]]` is
/// already the body text). `.md` notes export their body unchanged — see the call site.
enum NoteMarkdownExporter {
    static func markdown(for document: NoteDocument) -> String {
        let ns = document.text as NSString
        let blocks = document.metadata.blocks.sorted { $0.range.start < $1.range.start }
        guard !blocks.isEmpty else { return document.text }

        var pieces: [String] = []
        for block in blocks {
            let clamped = block.range.clamped(to: ns.length)
            let raw = clamped.length > 0 ? ns.substring(with: NSRange(location: clamped.start, length: clamped.length)) : ""
            let withSpans = applySpans(document.metadata.spans, blockRange: clamped, blockText: raw)
            let content = withSpans.trimmingCharacters(in: .newlines)

            switch block.type {
            case .divider:
                pieces.append("---")
            case .code:
                pieces.append("```\n\(content)\n```")
            case .heading:
                let level = max(1, min(6, block.level ?? 1))
                pieces.append(String(repeating: "#", count: level) + " " + content)
            case .listItem:
                pieces.append("- " + content)
            case .taskItem:
                pieces.append((block.isDone == true ? "- [x] " : "- [ ] ") + content)
            case .callout:
                let quoted = content
                    .components(separatedBy: "\n")
                    .map { "> " + $0 }
                    .joined(separator: "\n")
                pieces.append(quoted)
            case .paragraph:
                pieces.append(content)
            }
        }
        return pieces.joined(separator: "\n\n") + "\n"
    }

    /// Wraps span ranges intersecting the block with Markdown markers; insertions run
    /// back-to-front so earlier offsets stay valid.
    private static func applySpans(_ spans: [Span], blockRange: MiranNotesCore.TextRange, blockText: String) -> String {
        var insertions: [(offset: Int, marker: String)] = []
        for span in spans {
            let start = max(span.range.start, blockRange.start)
            let end = min(span.range.end, blockRange.end)
            guard end > start else { continue }
            let marker = markerText(span.style)
            insertions.append((start - blockRange.start, marker))
            insertions.append((end - blockRange.start, marker))
        }
        guard !insertions.isEmpty else { return blockText }
        let mutable = NSMutableString(string: blockText)
        for insertion in insertions.sorted(by: { $0.offset > $1.offset }) {
            let clamped = min(max(0, insertion.offset), mutable.length)
            mutable.insert(insertion.marker, at: clamped)
        }
        return mutable as String
    }

    private static func markerText(_ style: SpanStyle) -> String {
        switch style {
        case .bold: "**"
        case .italic: "*"
        case .code: "`"
        }
    }
}

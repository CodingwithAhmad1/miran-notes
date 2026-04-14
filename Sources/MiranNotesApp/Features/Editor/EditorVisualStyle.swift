import AppKit
import MiranNotesCore

/// Applies model-driven typography to `NSTextStorage`: block fonts, then span styles, then optional wiki-link color when enabled.
/// Order must stay stable; canonical text lives in `NoteDocument.text`.
enum EditorVisualStyle {
    static let bodyPointSize: CGFloat = 15

    static var bodyFont: NSFont { .systemFont(ofSize: bodyPointSize) }

    static func fontForBlock(_ block: Block) -> NSFont {
        switch block.type {
        case .heading:
            let level = min(max(block.level ?? 1, 1), 3)
            let size: CGFloat = [30, 24, 20][level - 1]
            return .systemFont(ofSize: size, weight: .bold)
        case .code:
            return .monospacedSystemFont(ofSize: 14, weight: .regular)
        case .divider:
            return .systemFont(ofSize: 13, weight: .medium)
        case .paragraph, .listItem, .callout:
            return bodyFont
        }
    }

    static func fontByApplyingSpan(base: NSFont, style: SpanStyle) -> NSFont {
        switch style {
        case .bold:
            return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        case .italic:
            return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        case .code:
            let size = base.pointSize
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    static func apply(to textView: NSTextView, document: NoteDocument) {
        guard let storage = textView.textStorage else { return }
        let len = storage.length
        let bodyColor = NSColor.textColor
        let linkColor = NSColor.linkColor

        textView.font = bodyFont
        var typing = textView.typingAttributes
        typing[.foregroundColor] = bodyColor
        // Clamp cursor to the document length before block lookup so that stale selection positions
        // from a previously-open note don't miss the block and fall back to body font.
        let docLength = (document.text as NSString).length
        let rawCursorLoc = textView.selectedRange().location
        let cursorLoc = min(rawCursorLoc, docLength)
        let cursorBlock = document.metadata.blocks.first { $0.range.contains(cursorLoc) || $0.range.end == cursorLoc }
        typing[.font] = cursorBlock.map { fontForBlock($0) } ?? bodyFont
        textView.typingAttributes = typing

        storage.beginEditing()
        defer { storage.endEditing() }

        if len == 0 { return }

        let fullRange = NSRange(location: 0, length: len)
        storage.removeAttribute(.foregroundColor, range: fullRange)
        storage.removeAttribute(.font, range: fullRange)

        storage.addAttribute(.foregroundColor, value: bodyColor, range: fullRange)

        let sortedBlocks = document.metadata.blocks.sorted { $0.range.start < $1.range.start }
        for block in sortedBlocks {
            let r = clampedNSRange(block.range, maxUTF16: len)
            guard r.length > 0 else { continue }
            storage.addAttribute(.font, value: fontForBlock(block), range: r)
        }

        let sortedSpans = document.metadata.spans.sorted { $0.range.start < $1.range.start }
        for span in sortedSpans {
            let r = clampedNSRange(span.range, maxUTF16: len)
            guard r.length > 0 else { continue }
            let base = (storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont) ?? bodyFont
            let font = fontByApplyingSpan(base: base, style: span.style)
            storage.addAttribute(.font, value: font, range: r)
        }

        if WikiLinkPresentationPolicy.isFrontendEnabled {
            for link in document.metadata.links {
                let r = clampedNSRange(link.range, maxUTF16: len)
                guard r.length > 0 else { continue }
                storage.addAttribute(.foregroundColor, value: linkColor, range: r)
            }
        }
    }

    private static func clampedNSRange(_ range: MiranNotesCore.TextRange, maxUTF16: Int) -> NSRange {
        let start = min(max(0, range.start), maxUTF16)
        let end = min(max(start, range.end), maxUTF16)
        return NSRange(location: start, length: end - start)
    }
}

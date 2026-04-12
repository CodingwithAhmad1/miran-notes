import AppKit
import MiranNotesCore

/// Non-interactive overlay (pass-through hit testing) that draws a minimal left gutter bar and drag-handle
/// affordance for the hovered and/or caret block. Geometry follows `NSLayoutManager` line fragments.
final class BlockChromeOverlayView: NSView {
    weak var textView: NSTextView?

    var hoveredBlockID: String?
    var focusedBlockID: String?
    var blocks: [Block] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let textView, let lm = textView.layoutManager, let tc = textView.textContainer else { return }

        let inset = textView.textContainerInset
        let accent = NSColor.controlAccentColor.withAlphaComponent(0.55)
        let hoverColor = NSColor.separatorColor.withAlphaComponent(0.9)
        let handleTint = NSColor.secondaryLabelColor

        let ids = Set([hoveredBlockID, focusedBlockID].compactMap { $0 })
        for id in ids {
            guard let block = blocks.first(where: { $0.id == id }) else { continue }
            let r = block.range
            guard r.length > 0 else { continue }
            let charRange = NSRange(location: r.start, length: r.length)
            let glyphRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            rect.origin.x += inset.width
            rect.origin.y += inset.height

            let isFocused = (id == focusedBlockID)
            let barColor = isFocused ? accent : hoverColor
            let barWidth: CGFloat = isFocused ? 3 : 2
            let barX: CGFloat = 1
            let barPath = NSBezierPath(roundedRect: NSRect(x: barX, y: rect.minY, width: barWidth, height: rect.height), xRadius: 1, yRadius: 1)
            barColor.setFill()
            barPath.fill()

            let handleX = barX + barWidth + 2
            let handleText = "⋮⋮" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: handleTint
            ]
            let textSize = handleText.size(withAttributes: attrs)
            let textRect = NSRect(
                x: handleX,
                y: rect.midY - textSize.height / 2,
                width: textSize.width + 2,
                height: textSize.height
            )
            handleText.draw(in: textRect, withAttributes: attrs)
        }
    }

    func invalidateGeometry() {
        needsDisplay = true
    }
}

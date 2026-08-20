import AppKit
import MiranNotesCore

/// Overlay that draws a minimal left gutter bar and drag-handle affordance for the hovered/caret
/// block, plus a checkbox for every `taskItem` block. Hit testing passes through except over
/// checkboxes, which toggle via ``onToggleTask``. Geometry follows `NSLayoutManager` line fragments.
final class BlockChromeOverlayView: NSView {
    weak var textView: NSTextView?

    var hoveredBlockID: String?
    var focusedBlockID: String?
    var blocks: [Block] = []
    /// `(blockID, newIsDone)` when a task checkbox is clicked.
    var onToggleTask: ((String, Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return taskBlock(atOverlayPoint: local) != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let block = taskBlock(atOverlayPoint: local) else {
            super.mouseDown(with: event)
            return
        }
        onToggleTask?(block.id, !(block.isDone ?? false))
    }

    private func taskBlock(atOverlayPoint point: NSPoint) -> Block? {
        for block in blocks where block.type == .taskItem {
            if let rect = taskCheckboxRect(for: block), rect.insetBy(dx: -3, dy: -3).contains(point) {
                return block
            }
        }
        return nil
    }

    /// Checkbox rect in overlay coordinates: first line fragment of the block, left gutter.
    private func taskCheckboxRect(for block: Block) -> NSRect? {
        guard let textView, let lm = textView.layoutManager else { return nil }
        guard lm.numberOfGlyphs > 0 || block.range.start == 0 else { return nil }
        let inset = textView.textContainerInset
        let charIndex = min(block.range.start, max(0, (textView.string as NSString).length - 1))
        let glyphIndex = lm.glyphIndexForCharacter(at: charIndex)
        var lineRect = lm.numberOfGlyphs > 0
            ? lm.lineFragmentRect(forGlyphAt: min(glyphIndex, lm.numberOfGlyphs - 1), effectiveRange: nil)
            : NSRect(x: 0, y: 0, width: 0, height: 18)
        lineRect.origin.y += inset.height
        let side: CGFloat = 14
        return NSRect(
            x: inset.width - side - 10,
            y: lineRect.midY - side / 2,
            width: side,
            height: side
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let textView, let lm = textView.layoutManager, let tc = textView.textContainer else { return }

        drawTaskCheckboxes()

        let inset = textView.textContainerInset
        let accent = NSColor.controlAccentColor.withAlphaComponent(0.55)
        let hoverColor = NSColor.separatorColor.withAlphaComponent(0.9)
        let handleTint = NSColor.secondaryLabelColor

        let ids = Set([hoveredBlockID, focusedBlockID].compactMap { $0 })
        for id in ids {
            guard let block = blocks.first(where: { $0.id == id }) else { continue }
            let r = block.range
            let rect: NSRect
            if r.length > 0 {
                let charRange = NSRange(location: r.start, length: r.length)
                let glyphRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
                var bounds = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
                bounds.origin.x += inset.width
                bounds.origin.y += inset.height
                rect = bounds
            } else {
                // Zero-length block (e.g. freshly created empty line): derive the rect from the
                // line fragment at the block's start position so the gutter bar is still visible.
                let glyphIndex = lm.glyphIndexForCharacter(at: min(r.start, lm.numberOfGlyphs > 0 ? lm.numberOfGlyphs - 1 : 0))
                var lineFragmentRect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                lineFragmentRect.origin.x += inset.width
                lineFragmentRect.origin.y += inset.height
                rect = lineFragmentRect
            }

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

    private func drawTaskCheckboxes() {
        for block in blocks where block.type == .taskItem {
            guard let rect = taskCheckboxRect(for: block) else { continue }
            let done = block.isDone == true
            let path = NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5)
            path.lineWidth = 1.2
            if done {
                NSColor.controlAccentColor.setFill()
                path.fill()
                let check = NSBezierPath()
                check.lineWidth = 1.6
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.move(to: NSPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.52))
                check.line(to: NSPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.72))
                check.line(to: NSPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.30))
                NSColor.white.setStroke()
                check.stroke()
            } else {
                NSColor.tertiaryLabelColor.setStroke()
                path.stroke()
            }
        }
    }

    func invalidateGeometry() {
        needsDisplay = true
    }
}

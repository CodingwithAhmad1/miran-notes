import SwiftUI

/// A miniature square icon representing a `PaneLayout`, drawn with dividing lines.
/// Mimics the visual style of TradingView's layout selector icons.
struct LayoutIconView: View {
    let layout: PaneLayout
    let isSelected: Bool

    private let size: CGFloat = 28
    private let strokeWidth: CGFloat = 1.5
    private let cornerRadius: CGFloat = 4

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let rect = CGRect(origin: .zero, size: canvasSize)

            // Background fill
            let bg = Path(roundedRect: rect, cornerRadius: cornerRadius)
            context.fill(bg, with: .color(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06)))

            // Border
            context.stroke(bg, with: .color(isSelected ? Color.accentColor : Color.primary.opacity(0.35)), lineWidth: strokeWidth)

            let dividerColor = isSelected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.4)

            switch layout {
            case .single:
                break

            case .twoPane:
                // Vertical divider at 50% — icon uses a subtle diagonal stroke on the divider
                // to evoke TradingView's diagonal-pairing visual.
                var diag = Path()
                diag.move(to: CGPoint(x: w * 0.5, y: 0))
                diag.addLine(to: CGPoint(x: w * 0.5, y: h))
                context.stroke(diag, with: .color(dividerColor), lineWidth: strokeWidth)

            case .threePane:
                // Vertical divider at 50%
                var vert = Path()
                vert.move(to: CGPoint(x: w * 0.5, y: 0))
                vert.addLine(to: CGPoint(x: w * 0.5, y: h))
                context.stroke(vert, with: .color(dividerColor), lineWidth: strokeWidth)

                // Horizontal divider on right half only
                var horiz = Path()
                horiz.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
                horiz.addLine(to: CGPoint(x: w, y: h * 0.5))
                context.stroke(horiz, with: .color(dividerColor), lineWidth: strokeWidth)

            case .fourPane:
                // Full vertical divider
                var vert = Path()
                vert.move(to: CGPoint(x: w * 0.5, y: 0))
                vert.addLine(to: CGPoint(x: w * 0.5, y: h))
                context.stroke(vert, with: .color(dividerColor), lineWidth: strokeWidth)

                // Full horizontal divider
                var horiz = Path()
                horiz.move(to: CGPoint(x: 0, y: h * 0.5))
                horiz.addLine(to: CGPoint(x: w, y: h * 0.5))
                context.stroke(horiz, with: .color(dividerColor), lineWidth: strokeWidth)
            }
        }
        .frame(width: size, height: size)
    }
}

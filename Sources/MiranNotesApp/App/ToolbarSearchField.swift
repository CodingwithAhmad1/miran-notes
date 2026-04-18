import AppKit
import SwiftUI

/// Wraps the text field so the toolbar search pill is **one** filled rounded rect from AppKit.
/// A SwiftUI `Capsule` behind `NSViewRepresentable` can leave lighter “caps” at the ends because the hosted
/// `NSTextField` composites a darker rectangle over the centre.
private final class ToolbarSearchFieldContainer: NSView {
    let textField: NSTextField

    init(textField: NSTextField) {
        self.textField = textField
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        applyFillColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard let layer else { return }
        let halfHeight = bounds.height / 2
        layer.cornerRadius = halfHeight.isFinite ? halfHeight : 0
        layer.masksToBounds = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyFillColor()
    }

    private func applyFillColor() {
        layer?.backgroundColor = NSColor.tertiarySystemFill.cgColor
    }
}

/// Single-line toolbar search without NSTextField’s default bezel, so custom capsule styling is not doubled.
struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let textField = NSTextField(string: text)
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        if let cell = textField.cell as? NSTextFieldCell {
            cell.drawsBackground = false
        }
        textField.focusRingType = .none
        textField.placeholderString = placeholder
        textField.textColor = .labelColor
        textField.delegate = context.coordinator
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let container = ToolbarSearchFieldContainer(textField: textField)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? ToolbarSearchFieldContainer else { return }
        let textField = container.textField

        context.coordinator.parent = self

        if textField.placeholderString != placeholder {
            textField.placeholderString = placeholder
        }

        textField.textColor = .labelColor

        if textField.stringValue != text {
            textField.stringValue = text
        }

        let fieldIsFirstResponder = Self.isToolbarFieldActiveFirstResponder(textField)
        if isFocused, !fieldIsFirstResponder {
            DispatchQueue.main.async {
                textField.window?.makeFirstResponder(textField)
            }
        } else if !isFocused, fieldIsFirstResponder {
            DispatchQueue.main.async {
                textField.window?.makeFirstResponder(nil)
            }
        }
    }

    /// While editing, AppKit makes the shared field-editor `NSTextView` the window first responder, not the `NSTextField`.
    private static func isToolbarFieldActiveFirstResponder(_ textField: NSTextField) -> Bool {
        guard let fr = textField.window?.firstResponder else { return false }
        if fr === textField { return true }
        if let editor = textField.currentEditor(), fr === editor { return true }
        return false
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ToolbarSearchField

        init(_ parent: ToolbarSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            if parent.text != textField.stringValue {
                parent.$text.wrappedValue = textField.stringValue
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if let textField = notification.object as? NSTextField,
               let editor = textField.currentEditor() as? NSTextView {
                editor.drawsBackground = false
                editor.backgroundColor = .clear
            }
            if !parent.isFocused {
                parent.$isFocused.wrappedValue = true
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.$isFocused.wrappedValue = false
            }
        }
    }
}

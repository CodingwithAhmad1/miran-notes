import AppKit
import SwiftUI

/// Single-line field for a Today’s Tasks row line: Return inserts a detail line; Backspace on an empty detail line merges upward.
struct TodaysTaskLineTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var isDone: Bool
    var placeholder: String
    var lineIndex: Int
    var onNewLine: () -> Void
    var onMergeDetailLineUp: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .default
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        Self.applyStyle(to: textField, isDone: isDone)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if textField.placeholderString != placeholder {
            textField.placeholderString = placeholder
        }

        if textField.stringValue != text {
            textField.stringValue = text
            Self.applyStyle(to: textField, isDone: isDone)
        } else {
            Self.applyStyle(to: textField, isDone: isDone)
        }

        let fieldIsFirstResponder = Self.isFieldActiveFirstResponder(textField)
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

    private static func isFieldActiveFirstResponder(_ textField: NSTextField) -> Bool {
        guard let fr = textField.window?.firstResponder else { return false }
        if fr === textField { return true }
        if let editor = textField.currentEditor(), fr === editor { return true }
        return false
    }

    static func applyStyle(to textField: NSTextField, isDone: Bool) {
        let s = textField.stringValue
        if s.isEmpty {
            textField.attributedStringValue = NSAttributedString()
            textField.textColor = isDone ? .secondaryLabelColor : .labelColor
            return
        }
        let m = NSMutableAttributedString(string: s)
        let range = NSRange(location: 0, length: m.length)
        m.addAttribute(.foregroundColor, value: isDone ? NSColor.secondaryLabelColor : NSColor.labelColor, range: range)
        m.addAttribute(.font, value: NSFont.systemFont(ofSize: NSFont.systemFontSize), range: range)
        if isDone {
            m.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        textField.attributedStringValue = m
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TodaysTaskLineTextField

        init(_ parent: TodaysTaskLineTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            let next = textField.stringValue
            if parent.text != next {
                parent.$text.wrappedValue = next
            }
                       TodaysTaskLineTextField.applyStyle(to: textField, isDone: parent.isDone)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.$isFocused.wrappedValue = true
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.$isFocused.wrappedValue = false
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onNewLine()
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)),
                parent.lineIndex > 0,
                textView.string.isEmpty {
                parent.onMergeDetailLineUp()
                return true
            }
            return false
        }
    }
}

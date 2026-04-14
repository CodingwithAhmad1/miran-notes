import AppKit
import SwiftUI

/// Single-line toolbar search without NSTextField’s default bezel, so custom capsule styling is not doubled.
struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if textField.placeholderString != placeholder {
            textField.placeholderString = placeholder
        }

        if textField.stringValue != text {
            textField.stringValue = text
        }

        if isFocused, textField.window?.firstResponder !== textField {
            DispatchQueue.main.async {
                textField.window?.makeFirstResponder(textField)
            }
        } else if !isFocused, textField.window?.firstResponder as AnyObject? === textField {
            DispatchQueue.main.async {
                textField.window?.makeFirstResponder(nil)
            }
        }
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

import AppKit
import MiranNotesCore
import SwiftUI

/// Activates the app on click and routes clicks on wiki-link ranges before editing.
private final class WikiLinkTextView: NSTextView {
    var wikiLinks: [NoteLink] = []
    var linkHitHandler: ((UUID) -> Void)?

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(self)
        let local = convert(event.locationInWindow, from: nil)
        let idx = characterIndex(for: local)
        if idx != NSNotFound {
            for link in wikiLinks {
                let r = NSRange(location: link.range.start, length: link.range.length)
                guard r.length > 0 else { continue }
                if NSLocationInRange(idx, r) {
                    linkHitHandler?(link.targetNoteID)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}

private enum EditorTypography {
    static let bodyPointSize: CGFloat = 15
    static var bodyFont: NSFont { .systemFont(ofSize: bodyPointSize) }

    /// Programmatic `string` / `replaceCharacters` updates often install the field editor’s default font (~13pt).
    /// Reapply our body font to the full storage and typing attributes so typing stays the same size after Return, etc.
    static func applyBodyStyle(to textView: NSTextView) {
        let font = bodyFont
        textView.font = font
        var attrs = textView.typingAttributes
        attrs[.font] = font
        if attrs[.foregroundColor] == nil {
            attrs[.foregroundColor] = NSColor.textColor
        }
        textView.typingAttributes = attrs
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }
        storage.beginEditing()
        storage.addAttribute(.font, value: font, range: fullRange)
        storage.endEditing()
    }

    static func applyWikiLinkHighlight(_ textView: NSTextView, links: [NoteLink]) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let font = bodyFont
        let bodyColor = NSColor.textColor
        let linkColor = NSColor.linkColor
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: bodyColor, range: fullRange)
        for link in links {
            let r = NSRange(location: link.range.start, length: link.range.length)
            guard r.location + r.length <= storage.length else { continue }
            guard r.length > 0 else { continue }
            storage.addAttribute(.font, value: font, range: r)
            storage.addAttribute(.foregroundColor, value: linkColor, range: r)
        }
        storage.endEditing()
    }
}

struct SingleSurfaceNoteEditor: NSViewRepresentable {
    @Binding var document: NoteDocument
    var onCommands: ([EditCommand]) -> Void
    var onWikiLinkClick: ((UUID) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = WikiLinkTextView()
        textView.isEditable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        EditorTypography.applyBodyStyle(to: textView)
        textView.textContainerInset = NSSize(width: 8, height: 10)
        // Document-level undo is handled by the window `UndoManager` in `AppModel`; disable `NSTextView`’s separate stack.
        textView.allowsUndo = false
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        let coordinator = context.coordinator
        coordinator.textView = textView
        textView.linkHitHandler = { [weak coordinator] id in
            coordinator?.parent.onWikiLinkClick?(id)
        }
        coordinator.applyDocumentText()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let tv = nsView.documentView as? WikiLinkTextView {
            let coordinator = context.coordinator
            tv.linkHitHandler = { [weak coordinator] id in
                coordinator?.parent.onWikiLinkClick?(id)
            }
        }
        context.coordinator.applyDocumentText()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: SingleSurfaceNoteEditor
        weak var textView: NSTextView?
        private var isApplyingModelUpdate = false
        private var pendingSelection: NSRange?
        private var pendingCommands: [EditCommand]?

        init(_ parent: SingleSurfaceNoteEditor) {
            self.parent = parent
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            _ = editedMask
            _ = editedRange
            _ = delta

            guard !isApplyingModelUpdate else { return }
            guard let textView else { return }
            guard textView.textStorage === textStorage else { return }
            if textView.hasMarkedText() { return }

            let storageString = textStorage.string
            if storageString == parent.document.text { return }

            if let diff = TextEditDiff.singleUTF16Replacement(from: parent.document.text, to: storageString) {
                parent.onCommands([
                    .replaceText(
                        range: TextRange(start: diff.range.location, length: diff.range.length),
                        replacement: diff.replacement
                    )
                ])
            } else {
                let previous = parent.document.text
                parent.onCommands([
                    .replaceText(
                        range: TextRange(start: 0, length: previous.utf16.count),
                        replacement: storageString
                    )
                ])
            }
        }

        func applyDocumentText() {
            guard let textView else { return }
            // Avoid clobbering an in-flight IME composition when the model updates (e.g. external reload).
            if textView.hasMarkedText() { return }

            if textView.string == parent.document.text {
                refreshWikiLinkChrome(textView: textView)
                applyPendingSelectionIfNeeded()
                return
            }

            if let commands = pendingCommands,
               applyPendingCommandsIfConsistent(commands, textView: textView) {
                pendingCommands = nil
                EditorTypography.applyBodyStyle(to: textView)
                refreshWikiLinkChrome(textView: textView)
                applyPendingSelectionIfNeeded()
                return
            }

            pendingCommands = nil

            if let diff = TextEditDiff.singleUTF16Replacement(from: textView.string, to: parent.document.text) {
                isApplyingModelUpdate = true
                textView.textStorage?.replaceCharacters(in: diff.range, with: diff.replacement)
                isApplyingModelUpdate = false
                EditorTypography.applyBodyStyle(to: textView)
                refreshWikiLinkChrome(textView: textView)
                applyPendingSelectionIfNeeded()
                return
            }

            let savedSelection = textView.selectedRange()
            isApplyingModelUpdate = true
            textView.string = parent.document.text
            isApplyingModelUpdate = false
            EditorTypography.applyBodyStyle(to: textView)
            refreshWikiLinkChrome(textView: textView)
            restoreSelectionClamped(savedSelection)
            applyPendingSelectionIfNeeded()
        }

        private func refreshWikiLinkChrome(textView: NSTextView) {
            EditorTypography.applyWikiLinkHighlight(textView, links: parent.document.metadata.links)
            if let w = textView as? WikiLinkTextView {
                w.wikiLinks = parent.document.metadata.links
            }
        }

        private func restoreSelectionClamped(_ range: NSRange) {
            guard let textView else { return }
            let maxLen = textView.string.utf16.count
            let loc = min(max(0, range.location), maxLen)
            let len = min(range.length, max(0, maxLen - loc))
            textView.setSelectedRange(NSRange(location: loc, length: len))
        }

        private func applyPendingCommandsIfConsistent(_ commands: [EditCommand], textView: NSTextView) -> Bool {
            var mutable = textView.string
            for command in commands {
                guard case let .replaceText(range, replacement) = command else { continue }
                let textRange = TextRange(start: range.start, length: range.length)
                guard let swiftRange = nsRangeToStringRange(textRange, in: mutable) else {
                    return false
                }
                mutable.replaceSubrange(swiftRange, with: replacement)
            }

            guard mutable == parent.document.text else {
                return false
            }

            isApplyingModelUpdate = true
            textView.string = mutable
            isApplyingModelUpdate = false
            return textView.string == parent.document.text
        }

        private func nsRangeToStringRange(_ range: MiranNotesCore.TextRange, in text: String) -> Range<String.Index>? {
            let nsRange = NSRange(location: range.start, length: range.length)
            return Range(nsRange, in: text)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if isApplyingModelUpdate {
                return true
            }

            let replacement = replacementString ?? ""
            let selectedLocation = textView.selectedRange().location

            if let structural = DocumentLayoutController.commandsForEdit(
                document: parent.document,
                affectedRange: affectedCharRange,
                replacement: replacement,
                selectedLocation: selectedLocation
            ) {
                pendingSelection = NSRange(location: affectedCharRange.location + replacement.utf16.count, length: 0)
                pendingCommands = structural
                parent.onCommands(structural)
                return false
            }

            return true
        }

        private func applyPendingSelectionIfNeeded() {
            guard let textView, let pendingSelection else { return }
            let maxOffset = textView.string.utf16.count
            let clampedLocation = min(max(0, pendingSelection.location), maxOffset)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
            self.pendingSelection = nil
        }
    }
}

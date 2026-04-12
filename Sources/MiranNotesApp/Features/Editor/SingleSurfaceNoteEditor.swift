import AppKit
import MiranNotesCore
import SwiftUI

/// Activates the app on click and routes clicks on wiki-link ranges before editing.
private final class WikiLinkTextView: NSTextView {
    var wikiLinks: [NoteLink] = []
    var linkHitHandler: ((UUID) -> Void)?
    var formattingCommandHandler: ((SpanStyle) -> Void)?

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

    override func doCommand(by selector: Selector) {
        // Standard key bindings use these selectors (not exposed as Swift `#selector` on `NSTextView`).
        switch selector {
        case Selector(("toggleBold:")):
            formattingCommandHandler?(.bold)
        case Selector(("toggleItalic:")):
            formattingCommandHandler?(.italic)
        default:
            super.doCommand(by: selector)
        }
    }

    /// Format menu and Cmd+Shift+C; avoids Cmd+` (reserved for window cycling on macOS).
    @objc func toggleCodeSpan(_ sender: Any?) {
        formattingCommandHandler?(.code)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.modifierFlags.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            formattingCommandHandler?(.code)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct SingleSurfaceNoteEditor: NSViewRepresentable {
    @Binding var document: NoteDocument
    /// Updated on every selection change so callers (e.g. insertWikiLink) know the cursor position.
    @Binding var cursorOffset: Int
    /// Returns the resulting NoteDocument synchronously so the coordinator can apply styling immediately,
    /// eliminating the brief lag between command dispatch and the next SwiftUI render cycle.
    var onCommands: ([EditCommand]) -> NoteDocument
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
        textView.usesFontPanel = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        // Document-level undo is handled by the window `UndoManager` in `AppModel`; disable `NSTextView`'s separate stack.
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
        textView.formattingCommandHandler = { [weak coordinator] style in
            coordinator?.toggleSpanStyle(style)
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
            tv.formattingCommandHandler = { [weak coordinator] style in
                coordinator?.toggleSpanStyle(style)
            }
        }
        context.coordinator.applyDocumentText()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: SingleSurfaceNoteEditor
        weak var textView: NSTextView?
        private var isApplyingModelUpdate = false
        private var pendingSelection: NSRange?

        init(_ parent: SingleSurfaceNoteEditor) {
            self.parent = parent
        }

        func toggleSpanStyle(_ style: SpanStyle) {
            guard let textView else { return }
            guard !textView.hasMarkedText() else { return }
            let r = textView.selectedRange()
            guard r.length > 0 else { return }
            let newDoc = parent.onCommands([
                .toggleSpanStyle(range: TextRange(start: r.location, length: r.length), style: style)
            ])
            refreshVisualChrome(textView: textView, document: newDoc)
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
                if let slashMatch = SlashCommandDetector.match(
                    modelText: parent.document.text,
                    storageText: storageString,
                    insertion: (diff.range, diff.replacement)
                ),
                    let blockIndex = DocumentLayoutController.blockIndex(
                        at: diff.range.location,
                        blocks: parent.document.metadata.blocks
                    ) {
                    let blockID = parent.document.metadata.blocks[blockIndex].id
                    if let slashCommands = SlashCommandRegistry.editCommands(for: slashMatch, blockID: blockID) {
                        let newDoc = parent.onCommands(slashCommands)
                        refreshVisualChrome(textView: textView, document: newDoc)
                        return
                    }
                }

                let newDoc = parent.onCommands([
                    .replaceText(
                        range: TextRange(start: diff.range.location, length: diff.range.length),
                        replacement: diff.replacement
                    )
                ])
                refreshVisualChrome(textView: textView, document: newDoc)
            } else {
                let previous = parent.document.text
                let newDoc = parent.onCommands([
                    .replaceText(
                        range: TextRange(start: 0, length: previous.utf16.count),
                        replacement: storageString
                    )
                ])
                refreshVisualChrome(textView: textView, document: newDoc)
            }
        }

        func applyDocumentText() {
            guard let textView else { return }
            // Avoid clobbering an in-flight IME composition when the model updates (e.g. external reload).
            if textView.hasMarkedText() { return }

            if textView.string == parent.document.text {
                refreshVisualChrome(textView: textView, document: parent.document)
                applyPendingSelectionIfNeeded()
                return
            }

            if let diff = TextEditDiff.singleUTF16Replacement(from: textView.string, to: parent.document.text) {
                isApplyingModelUpdate = true
                textView.textStorage?.replaceCharacters(in: diff.range, with: diff.replacement)
                isApplyingModelUpdate = false
                refreshVisualChrome(textView: textView, document: parent.document)
                applyPendingSelectionIfNeeded()
                return
            }

            let savedSelection = textView.selectedRange()
            isApplyingModelUpdate = true
            textView.string = parent.document.text
            isApplyingModelUpdate = false
            refreshVisualChrome(textView: textView, document: parent.document)
            restoreSelectionClamped(savedSelection)
            applyPendingSelectionIfNeeded()
        }

        private func refreshVisualChrome(textView: NSTextView, document: NoteDocument) {
            EditorVisualStyle.apply(to: textView, document: document)
            if let w = textView as? WikiLinkTextView {
                w.wikiLinks = document.metadata.links
            }
        }

        private func restoreSelectionClamped(_ range: NSRange) {
            guard let textView else { return }
            let maxLen = textView.string.utf16.count
            let loc = min(max(0, range.location), maxLen)
            let len = min(range.length, max(0, maxLen - loc))
            textView.setSelectedRange(NSRange(location: loc, length: len))
        }

        private func applyPendingSelectionIfNeeded() {
            guard let textView, let pendingSelection else { return }
            let maxOffset = textView.string.utf16.count
            let clampedLocation = min(max(0, pendingSelection.location), maxOffset)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
            self.pendingSelection = nil
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
                let newDoc = parent.onCommands(structural)
                // Apply the new text from the model immediately (avoids the full-replace path in applyDocumentText).
                isApplyingModelUpdate = true
                if let diff = TextEditDiff.singleUTF16Replacement(from: textView.string, to: newDoc.text) {
                    textView.textStorage?.replaceCharacters(in: diff.range, with: diff.replacement)
                } else {
                    textView.string = newDoc.text
                }
                isApplyingModelUpdate = false
                refreshVisualChrome(textView: textView, document: newDoc)
                applyPendingSelectionIfNeeded()
                return false
            }

            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let loc = tv.selectedRange().location
            if parent.cursorOffset != loc {
                parent.cursorOffset = loc
            }
        }
    }
}

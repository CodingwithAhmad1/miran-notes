// Experimental multi-block editor surface; the shipping window uses `SingleSurfaceNoteEditor` instead.
import AppKit
import MiranNotesCore
import SwiftUI

struct TextKit2BlockEditor: NSViewRepresentable {
    let block: Block
    @Binding var document: NoteDocument
    var onCommand: (EditCommand) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.allowsUndo = false
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        context.coordinator.textView = textView
        applyCurrentBlockText(to: textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textView.font = font(for: block)
        applyCurrentBlockText(to: textView, coordinator: context.coordinator)
    }

    private func applyCurrentBlockText(to textView: NSTextView, coordinator: Coordinator) {
        if textView.hasMarkedText() { return }
        let blockText = blockTextSlice()
        if textView.string == blockText {
            return
        }
        if let diff = TextEditDiff.singleUTF16Replacement(from: textView.string, to: blockText) {
            coordinator.isApplyingExternalUpdate = true
            textView.textStorage?.replaceCharacters(in: diff.range, with: diff.replacement)
            coordinator.isApplyingExternalUpdate = false
            return
        }
        coordinator.isApplyingExternalUpdate = true
        textView.string = blockText
        coordinator.isApplyingExternalUpdate = false
    }

    private func blockTextSlice() -> String {
        let total = document.text.utf16.count
        let clamped = block.range.clamped(to: total)
        if clamped != block.range {
            NoteIntegrity.logIfInvalid(document: document)
        }
        let ns = document.text as NSString
        let len = ns.length
        let start = min(max(0, clamped.start), len)
        let end = min(max(start, clamped.end), len)
        let bound = NSRange(location: start, length: end - start)
        if bound.length > 0, Range(bound, in: document.text) == nil {
            NoteIntegrity.logIfInvalid(document: document)
        }
        return ns.substring(with: bound)
    }

    private func font(for block: Block) -> NSFont {
        switch block.type {
        case .heading:
            let level = min(max(block.level ?? 1, 1), 3)
            let size: CGFloat = [30, 24, 20][level - 1]
            return .systemFont(ofSize: size, weight: .bold)
        case .code:
            return .monospacedSystemFont(ofSize: 14, weight: .regular)
        default:
            return .systemFont(ofSize: 15)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: TextKit2BlockEditor
        weak var textView: NSTextView?
        var isApplyingExternalUpdate = false

        init(_ parent: TextKit2BlockEditor) {
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

            guard !isApplyingExternalUpdate else { return }
            guard let textView else { return }
            guard textView.textStorage === textStorage else { return }
            if textView.hasMarkedText() { return }

            let replacement = textView.string
            let command = EditCommand.insertText(range: parent.block.range, text: replacement)
            parent.onCommand(command)
        }
    }
}

import AppKit
import MiranNotesCore

/// Shared `NSTextView` selection and scroll helpers for editor surfaces; model→view text sync stays on ``EditorSyncController``.
@MainActor
enum NoteEditorNSTextViewSynchronizer {
    static func restoreSelectionClamped(_ range: NSRange, textView: NSTextView) {
        let maxLen = textView.string.utf16.count
        let loc = min(max(0, range.location), maxLen)
        let len = min(range.length, max(0, maxLen - loc))
        textView.setSelectedRange(NSRange(location: loc, length: len))
    }

    static func applyPendingEditorScroll(
        textView: NSTextView,
        pending: PendingEditorScroll?,
        documentNoteID: UUID,
        onConsumed: () -> Void
    ) {
        guard let p = pending,
              p.noteID == documentNoteID,
              !p.range.isEmpty
        else { return }
        let maxLen = (textView.string as NSString).length
        let clamped = p.range.clamped(to: maxLen)
        guard clamped.length > 0 else {
            onConsumed()
            return
        }
        let nsr = NSRange(location: clamped.start, length: clamped.length)
        textView.setSelectedRange(nsr)
        textView.scrollRangeToVisible(nsr)
        onConsumed()
    }
}

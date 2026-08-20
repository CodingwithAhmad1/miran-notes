import AppKit
import SwiftUI

/// Owns the `[[` autocomplete popover for one editor surface. Both editor backends
/// (`SingleSurfaceNoteEditor`, `PlainMarkdownNoteEditor`) host one and route keyboard
/// commands through it before the slash menu fallback; commit semantics differ per backend
/// (block editor emits `insertWikiLink`, markdown inserts plain `[[Title]]` text).
@MainActor
final class WikiLinkMenuController {
    /// Note lookup for the query text; capped/ranked by the model.
    var candidates: ((String) -> [WikiLinkMenuEntry])?
    /// Perform the buffer mutation for the chosen entry, then the controller closes.
    var onCommit: ((WikiLinkMenuEntry, WikiLinkQueryMatch) -> Void)?

    private(set) var currentQuery: WikiLinkQueryMatch?
    private var entries: [WikiLinkMenuEntry] = []
    private var highlightedIndex = 0
    private var popover: NSPopover?
    private var host: NSHostingController<EditorWikiLinkMenuView>?

    var isPresenting: Bool { currentQuery != nil }

    /// Re-evaluates the query at the caret; shows, moves, or closes the popover.
    func refresh(textView: NSTextView) {
        guard WikiLinkPresentationPolicy.isAutocompleteEnabled, !textView.hasMarkedText(), textView.window != nil else {
            close()
            return
        }
        guard let query = WikiLinkQueryDetector.match(text: textView.string, selectedRange: textView.selectedRange()) else {
            close()
            return
        }

        let previousQueryText = currentQuery?.queryText
        currentQuery = query
        entries = candidates?(query.queryText) ?? []
        if previousQueryText != query.queryText {
            highlightedIndex = 0
        } else if highlightedIndex >= entries.count {
            highlightedIndex = max(0, entries.count - 1)
        }

        ensureInitialized()
        refreshMenuUI()
        guard let popover else { return }
        let anchor = caretAnchorRect(in: textView)
        if !popover.isShown {
            popover.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
        } else {
            popover.positioningRect = anchor
        }
    }

    /// Keyboard routing shared with the slash menu contract (Up/Down/Enter/Tab/Esc).
    func handleMenuCommand(_ command: NoteEditorSlashMenuCommand) -> Bool {
        guard isPresenting else { return false }
        switch command {
        case .moveUp:
            guard !entries.isEmpty else { return true }
            highlightedIndex = max(0, highlightedIndex - 1)
            refreshMenuUI()
            return true
        case .moveDown:
            guard !entries.isEmpty else { return true }
            highlightedIndex = min(entries.count - 1, highlightedIndex + 1)
            refreshMenuUI()
            return true
        case .close:
            close()
            return true
        case .commitSelection:
            guard entries.indices.contains(highlightedIndex) else { return false }
            return commit(at: highlightedIndex)
        }
    }

    func close() {
        currentQuery = nil
        entries = []
        highlightedIndex = 0
        popover?.performClose(nil)
    }

    private func commit(at index: Int) -> Bool {
        guard let query = currentQuery, entries.indices.contains(index) else { return false }
        let entry = entries[index]
        onCommit?(entry, query)
        close()
        return true
    }

    private func ensureInitialized() {
        guard popover == nil else { return }
        let host = NSHostingController(rootView: EditorWikiLinkMenuView(
            entries: [],
            highlightedIndex: 0,
            hasQuery: false,
            onSelect: { _ in }
        ))
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = false
        popover.contentViewController = host
        self.popover = popover
        self.host = host
    }

    private func refreshMenuUI() {
        guard let host else { return }
        host.rootView = EditorWikiLinkMenuView(
            entries: entries,
            highlightedIndex: highlightedIndex,
            hasQuery: !(currentQuery?.queryText.isEmpty ?? true),
            onSelect: { [weak self] index in
                self?.highlightedIndex = index
                _ = self?.commit(at: index)
            }
        )
        host.view.invalidateIntrinsicContentSize()
    }

    /// Caret-anchored rect (same geometry approach as the slash menu anchor).
    private func caretAnchorRect(in textView: NSTextView) -> NSRect {
        let selected = textView.selectedRange()
        let location = max(0, selected.location)
        let oneChar = NSRange(location: location, length: 0)
        if let lm = textView.layoutManager, let tc = textView.textContainer {
            let glyphRange = lm.glyphRange(forCharacterRange: oneChar, actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height
            if rect.width < 8 { rect.size.width = 12 }
            if rect.height < 8 { rect.size.height = 16 }
            return rect
        }
        return NSRect(x: textView.textContainerInset.width, y: textView.textContainerInset.height, width: 12, height: 16)
    }
}

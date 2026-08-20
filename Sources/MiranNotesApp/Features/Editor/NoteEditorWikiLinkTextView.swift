import AppKit
import MiranNotesCore

enum NoteEditorSlashMenuCommand {
    case moveUp
    case moveDown
    case commitSelection
    case close
}

/// Text view that routes mouse clicks on wiki-link and attachment-token ranges before editing,
/// and accepts file drops as attachments (`attachmentDropHandler`).
final class NoteEditorWikiLinkTextView: NSTextView {
    var wikiLinks: [NoteLink] = []
    var linkHitHandler: ((UUID) -> Void)?
    /// `[attachment: name]` token ranges (kept fresh by the coordinator's visual-chrome pass).
    var attachmentTokens: [AttachmentTokenScanner.Token] = []
    var attachmentHitHandler: ((String) -> Void)?
    /// File-URL drop → attach: `(urls, utf16InsertionIndex)`; return `true` when handled.
    var attachmentDropHandler: (([URL], Int) -> Bool)?
    var formattingCommandHandler: ((SpanStyle) -> Void)?
    var slashMenuCommandHandler: ((NoteEditorSlashMenuCommand) -> Bool)?
    /// When non-nil, invoked on right-click; return `true` if the event was handled (default menu suppressed).
    var blockContextMenuHandler: ((NSEvent) -> Bool)?

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
            if attachmentHitHandler != nil {
                for token in attachmentTokens where NSLocationInRange(idx, token.range) {
                    attachmentHitHandler?(token.filename)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: - File drops become attachments (before NSTextView pastes the URL as text)

    private func fileURLs(from draggingInfo: NSDraggingInfo) -> [URL] {
        (draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if attachmentDropHandler != nil, !fileURLs(from: sender).isEmpty {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if attachmentDropHandler != nil, !fileURLs(from: sender).isEmpty {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let handler = attachmentDropHandler {
            let urls = fileURLs(from: sender)
            if !urls.isEmpty {
                let local = convert(sender.draggingLocation, from: nil)
                let idx = characterIndex(for: local)
                let insertionIndex = idx == NSNotFound ? (string as NSString).length : idx
                if handler(urls, insertionIndex) {
                    return true
                }
            }
        }
        return super.performDragOperation(sender)
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case Selector(("toggleBold:")):
            formattingCommandHandler?(.bold)
        case Selector(("toggleItalic:")):
            formattingCommandHandler?(.italic)
        case Selector(("moveUp:")):
            if slashMenuCommandHandler?(.moveUp) == true { return }
            super.doCommand(by: selector)
        case Selector(("moveDown:")):
            if slashMenuCommandHandler?(.moveDown) == true { return }
            super.doCommand(by: selector)
        case Selector(("insertNewline:")), Selector(("insertTab:")):
            if slashMenuCommandHandler?(.commitSelection) == true { return }
            super.doCommand(by: selector)
        case Selector(("cancelOperation:")):
            if slashMenuCommandHandler?(.close) == true { return }
            super.doCommand(by: selector)
        default:
            super.doCommand(by: selector)
        }
    }

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

    override func rightMouseDown(with event: NSEvent) {
        if blockContextMenuHandler?(event) == true { return }
        super.rightMouseDown(with: event)
    }
}

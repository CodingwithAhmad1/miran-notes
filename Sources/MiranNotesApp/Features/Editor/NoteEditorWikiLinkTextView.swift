import AppKit
import MiranNotesCore

enum NoteEditorSlashMenuCommand {
    case moveUp
    case moveDown
    case commitSelection
    case close
}

/// Text view that can route mouse clicks on wiki-link ranges before editing when `WikiLinkPresentationPolicy.isFrontendEnabled` is true.
final class NoteEditorWikiLinkTextView: NSTextView {
    var wikiLinks: [NoteLink] = []
    var linkHitHandler: ((UUID) -> Void)?
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
        }
        super.mouseDown(with: event)
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

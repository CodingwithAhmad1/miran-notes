import AppKit
import MiranNotesCore
import SwiftUI

private enum SlashMenuCommand {
    case moveUp
    case moveDown
    case commitSelection
    case close
}

/// Activates the app on click and routes clicks on wiki-link ranges before editing.
private final class WikiLinkTextView: NSTextView {
    var wikiLinks: [NoteLink] = []
    var linkHitHandler: ((UUID) -> Void)?
    var formattingCommandHandler: ((SpanStyle) -> Void)?
    var slashMenuCommandHandler: ((SlashMenuCommand) -> Bool)?

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

private struct SlashCommandMenuView: View {
    let matches: [SlashCommandMatch]
    let highlightedIndex: Int
    let hasQuery: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if matches.isEmpty {
                Text(hasQuery ? "No commands found" : "Type to search commands")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(matches.enumerated()), id: \.element.item.id) { index, match in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.item.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text("/\(match.item.id)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(match.item.category)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(index == highlightedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(index) }
                }
            }
        }
        .frame(width: 320)
        .padding(.vertical, 4)
        .background(.regularMaterial)
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
    /// Called when the incremental diff fails and a full-buffer replace fallback fires (block structure may be partially lost).
    var onFullReplaceWarning: (() -> Void)?
    /// Called when a typed insertion would push the note past the 1 MB UTF-16 size limit.
    var onSizeLimitExceeded: (() -> Void)?

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
        textView.slashMenuCommandHandler = { [weak coordinator] command in
            coordinator?.handleSlashMenuCommand(command) ?? false
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
            tv.slashMenuCommandHandler = { [weak coordinator] command in
                coordinator?.handleSlashMenuCommand(command) ?? false
            }
        }
        context.coordinator.applyDocumentText()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: SingleSurfaceNoteEditor
        weak var textView: NSTextView?
        private var isApplyingModelUpdate = false
        private var pendingSelection: NSRange?
        private var currentSlashQuery: SlashQueryMatch?
        private var slashMatches: [SlashCommandMatch] = []
        private var highlightedSlashIndex = 0
        private var slashMenuPopover: NSPopover?
        private var slashMenuHost: NSHostingController<SlashCommandMenuView>?
        /// Last document identity for which `EditorVisualStyle.apply` ran, used to skip unchanged redraws.
        private var lastStyledDocumentID: UUID?
        private var lastStyledDocumentText: String?

        init(_ parent: SingleSurfaceNoteEditor) {
            self.parent = parent
        }

        func toggleSpanStyle(_ style: SpanStyle) {
            guard let textView else { return }
            guard !textView.hasMarkedText() else { return }
            let r = textView.selectedRange()
            guard r.length > 0 else { return }
            _ = runCommandSession(
                textView: textView,
                commands: [
                .toggleSpanStyle(range: TextRange(start: r.location, length: r.length), style: style)
                ]
            )
        }

        fileprivate func handleSlashMenuCommand(_ command: SlashMenuCommand) -> Bool {
            guard currentSlashQuery != nil else { return false }
            switch command {
            case .moveUp:
                guard !slashMatches.isEmpty else { return true }
                highlightedSlashIndex = max(0, highlightedSlashIndex - 1)
                refreshSlashMenuUI()
                return true
            case .moveDown:
                guard !slashMatches.isEmpty else { return true }
                highlightedSlashIndex = min(slashMatches.count - 1, highlightedSlashIndex + 1)
                refreshSlashMenuUI()
                return true
            case .close:
                closeSlashMenu()
                return true
            case .commitSelection:
                guard !slashMatches.isEmpty else { return false }
                return commitHighlightedSlashCommand()
            }
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
            refreshSlashMenuState(for: textView)

            if let diff = TextEditDiff.singleUTF16Replacement(from: parent.document.text, to: storageString) {
                if let triggerCommands = inlineTriggerCommands(storageText: storageString, insertion: diff) {
                    _ = runCommandSession(textView: textView, commands: triggerCommands)
                    return
                }

                _ = runCommandSession(
                    textView: textView,
                    commands: [
                    .replaceText(
                        range: TextRange(start: diff.range.location, length: diff.range.length),
                        replacement: diff.replacement
                    )
                    ]
                )
            } else {
                // Full-buffer fallback: diff could not be reduced to a single region.
                // Block structure may be partially collapsed, so attempt best-effort recovery.
                let previous = parent.document.text
                let oldBlocks = parent.document.metadata.blocks
                let afterReplace = runCommandSession(
                    textView: textView,
                    commands: [
                    .replaceText(
                        range: TextRange(start: 0, length: previous.utf16.count),
                        replacement: storageString
                    )
                    ]
                )
                let reconciled = EditCommandEngine.reconcileBlocksFromText(document: afterReplace, oldBlocks: oldBlocks)
                if reconciled != afterReplace {
                    _ = parent.onCommands([.repairMetadata])
                }
                parent.onFullReplaceWarning?()
            }
        }

        private func inlineTriggerCommands(
            storageText: String,
            insertion: (range: NSRange, replacement: String)
        ) -> [EditCommand]? {
            guard
                let blockIndex = DocumentLayoutController.blockIndex(
                    at: insertion.range.location,
                    blocks: parent.document.metadata.blocks
                )
            else { return nil }

            let block = parent.document.metadata.blocks[blockIndex]
            if let bulletMatch = MarkdownCommandDetector.bulletMatch(
                modelText: parent.document.text,
                storageText: storageText,
                insertion: insertion
            ) {
                let markerRange = TextRange(
                    start: bulletMatch.lineStartUTF16,
                    length: bulletMatch.commitUTF16Index - bulletMatch.lineStartUTF16
                )
                return [
                    .replaceText(range: markerRange, replacement: ""),
                    .changeBlockType(blockID: block.id, type: .listItem, headingLevel: nil)
                ]
            }

            if let slashMatch = SlashCommandDetector.match(
                modelText: parent.document.text,
                storageText: storageText,
                insertion: insertion
            ), let commands = SlashCommandRegistry.editCommands(
                for: slashMatch, blockID: block.id, blockType: block.type
            ) {
                return commands
            }

            return nil
        }

        private func refreshSlashMenuState(for textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard let query = SlashQueryDetector.match(text: textView.string, selectedRange: selectedRange) else {
                closeSlashMenu()
                return
            }

            let catalog = SlashCommandRegistry.catalogItems()
            let matches = SlashCommandMatcher.filterAndRank(query: query.queryText, catalog: catalog)
            let previousQuery = currentSlashQuery?.queryText
            currentSlashQuery = query
            slashMatches = matches
            if previousQuery != query.queryText {
                highlightedSlashIndex = 0
            } else if highlightedSlashIndex >= matches.count {
                highlightedSlashIndex = max(0, matches.count - 1)
            }

            showOrUpdateSlashMenu(relativeTo: textView, hasQuery: !query.queryText.isEmpty)
        }

        private func showOrUpdateSlashMenu(relativeTo textView: NSTextView, hasQuery: Bool) {
            ensureSlashMenuInitialized()
            refreshSlashMenuUI(hasQuery: hasQuery)
            guard let popover = slashMenuPopover else { return }
            let anchor = slashAnchorRect(in: textView)
            if !popover.isShown {
                popover.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
            } else {
                popover.positioningRect = anchor
            }
        }

        private func ensureSlashMenuInitialized() {
            if slashMenuPopover != nil {
                return
            }
            let host = NSHostingController(rootView: SlashCommandMenuView(
                matches: [],
                highlightedIndex: 0,
                hasQuery: false,
                onSelect: { _ in }
            ))
            let popover = NSPopover()
            popover.behavior = .semitransient
            popover.animates = false
            popover.contentViewController = host
            slashMenuPopover = popover
            slashMenuHost = host
        }

        private func refreshSlashMenuUI(hasQuery: Bool? = nil) {
            guard let host = slashMenuHost else { return }
            host.rootView = SlashCommandMenuView(
                matches: slashMatches,
                highlightedIndex: highlightedSlashIndex,
                hasQuery: hasQuery ?? !(currentSlashQuery?.queryText.isEmpty ?? true),
                onSelect: { [weak self] index in
                    self?.highlightedSlashIndex = index
                    _ = self?.commitHighlightedSlashCommand()
                }
            )
            host.view.invalidateIntrinsicContentSize()
        }

        private func slashAnchorRect(in textView: NSTextView) -> NSRect {
            let selected = textView.selectedRange()
            let location = max(0, selected.location)
            let oneChar = NSRange(location: location, length: 0)
            if let lm = textView.layoutManager, let tc = textView.textContainer {
                let glyphRange = lm.glyphRange(forCharacterRange: oneChar, actualCharacterRange: nil)
                var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
                rect.origin.x += textView.textContainerInset.width
                rect.origin.y += textView.textContainerInset.height
                if rect.width < 8 {
                    rect.size.width = 12
                }
                if rect.height < 8 {
                    rect.size.height = 16
                }
                return rect
            }
            return NSRect(x: textView.textContainerInset.width, y: textView.textContainerInset.height, width: 12, height: 16)
        }

        private func closeSlashMenu() {
            currentSlashQuery = nil
            slashMatches = []
            highlightedSlashIndex = 0
            slashMenuPopover?.performClose(nil)
        }

        @discardableResult
        private func commitHighlightedSlashCommand() -> Bool {
            guard let textView, let query = currentSlashQuery else { return false }
            guard slashMatches.indices.contains(highlightedSlashIndex) else { return false }
            guard
                let blockIndex = DocumentLayoutController.blockIndex(
                    at: query.queryRange.location,
                    blocks: parent.document.metadata.blocks
                )
            else { return false }

            let block = parent.document.metadata.blocks[blockIndex]
            let selected = slashMatches[highlightedSlashIndex]
            let tokenRange = TextRange(start: query.queryRange.location, length: query.queryRange.length)
            guard let commands = SlashCommandRegistry.resolveCatalogCommand(
                catalogID: selected.item.id,
                queryTokenRange: tokenRange,
                blockID: block.id,
                blockType: block.type
            ) else { return false }

            let targetSelection = NSRange(location: query.queryRange.location, length: 0)
            _ = runCommandSession(textView: textView, commands: commands, pendingSelection: targetSelection)
            closeSlashMenu()
            return true
        }

        func applyDocumentText() {
            guard let textView else { return }
            // Avoid clobbering an in-flight IME composition when the model updates (e.g. external reload).
            if textView.hasMarkedText() { return }

            if textView.string == parent.document.text {
                refreshVisualChrome(textView: textView, document: parent.document)
                applyPendingSelectionIfNeeded()
                refreshSlashMenuState(for: textView)
                return
            }

            if let diff = TextEditDiff.singleUTF16Replacement(from: textView.string, to: parent.document.text) {
                isApplyingModelUpdate = true
                textView.textStorage?.replaceCharacters(in: diff.range, with: diff.replacement)
                isApplyingModelUpdate = false
                refreshVisualChrome(textView: textView, document: parent.document)
                applyPendingSelectionIfNeeded()
                refreshSlashMenuState(for: textView)
                return
            }

            let savedSelection = textView.selectedRange()
            isApplyingModelUpdate = true
            textView.string = parent.document.text
            isApplyingModelUpdate = false
            refreshVisualChrome(textView: textView, document: parent.document)
            restoreSelectionClamped(savedSelection)
            applyPendingSelectionIfNeeded()
            refreshSlashMenuState(for: textView)
        }

        private func refreshVisualChrome(textView: NSTextView, document: NoteDocument) {
            // Skip full redraw if the document identity and text are unchanged since last apply.
            if lastStyledDocumentID == document.id, lastStyledDocumentText == document.text {
                return
            }
            EditorVisualStyle.apply(to: textView, document: document)
            lastStyledDocumentID = document.id
            lastStyledDocumentText = document.text
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

            // 1 MB UTF-16 unit guard — reject insertions that would overflow.
            let newLength = (textView.string.utf16.count - affectedCharRange.length) + replacement.utf16.count
            if newLength > 1_048_576 {
                parent.onSizeLimitExceeded?()
                return false
            }

            let selectedLocation = textView.selectedRange().location

            if let structural = DocumentLayoutController.commandsForEdit(
                document: parent.document,
                affectedRange: affectedCharRange,
                replacement: replacement,
                selectedLocation: selectedLocation
            ) {
                let targetSelection = NSRange(location: affectedCharRange.location + replacement.utf16.count, length: 0)
                _ = runCommandSession(
                    textView: textView,
                    commands: structural,
                    pendingSelection: targetSelection
                )
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
            refreshSlashMenuState(for: tv)
        }

        @discardableResult
        private func runCommandSession(
            textView: NSTextView,
            commands: [EditCommand],
            pendingSelection: NSRange? = nil
        ) -> NoteDocument {
            if let pendingSelection {
                self.pendingSelection = pendingSelection
            }
            let newDoc = parent.onCommands(commands)

            // Apply the canonical model text immediately so both mutation paths stay ordered.
            isApplyingModelUpdate = true
            if let diff = TextEditDiff.singleUTF16Replacement(from: textView.string, to: newDoc.text) {
                textView.textStorage?.replaceCharacters(in: diff.range, with: diff.replacement)
            } else if textView.string != newDoc.text {
                textView.string = newDoc.text
            }
            isApplyingModelUpdate = false

            refreshVisualChrome(textView: textView, document: newDoc)
            applyPendingSelectionIfNeeded()
            refreshSlashMenuState(for: textView)
            return newDoc
        }
    }
}

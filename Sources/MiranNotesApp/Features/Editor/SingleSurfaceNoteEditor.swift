import AppKit
import MiranNotesCore
import SwiftUI

private enum SlashMenuCommand {
    case moveUp
    case moveDown
    case commitSelection
    case close
}

/// Text view that can route mouse clicks on wiki-link ranges before editing when `WikiLinkPresentationPolicy.isFrontendEnabled` is true.
private final class WikiLinkTextView: NSTextView {
    var wikiLinks: [NoteLink] = []
    var linkHitHandler: ((UUID) -> Void)?
    var formattingCommandHandler: ((SpanStyle) -> Void)?
    var slashMenuCommandHandler: ((SlashMenuCommand) -> Bool)?
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

    override func rightMouseDown(with event: NSEvent) {
        if blockContextMenuHandler?(event) == true { return }
        super.rightMouseDown(with: event)
    }
}

private final class BlockTypeMenuRep: NSObject {
    let blockID: String
    let type: BlockType
    let headingLevel: Int?

    init(blockID: String, type: BlockType, headingLevel: Int?) {
        self.blockID = blockID
        self.type = type
        self.headingLevel = headingLevel
    }
}

@MainActor
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
    /// Updated on every selection change so the model knows the caret position for cursor-aware edits.
    @Binding var cursorOffset: Int
    /// Full UTF-16 selection (caret when `length == 0`) for `CommandContext` and extensions.
    @Binding var editorTextSelection: MiranNotesCore.TextRange
    /// Bound to the detail column search field in editor mode; selects the first match from the caret (wrapping).
    @Binding var editorFindQuery: String
    /// When set for the current document’s `noteID`, the coordinator scrolls to `range` once then calls `onPendingEditorScrollConsumed`.
    var pendingEditorScroll: PendingEditorScroll?
    var onPendingEditorScrollConsumed: (() -> Void)?
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
        textView.textContainerInset = NSSize(width: 48, height: 24)
        // Document-level undo is handled by the window `UndoManager` in `AppModel`; disable `NSTextView`'s separate stack.
        textView.allowsUndo = false
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator.textStorageDelegateBridge

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
        textView.blockContextMenuHandler = { [weak coordinator] event in
            coordinator?.handleBlockContextMenu(event) ?? false
        }
        coordinator.setupChrome(scrollView: scrollView, textView: textView)
        coordinator.applyDocumentText()
        return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.teardownChrome()
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
            tv.blockContextMenuHandler = { [weak coordinator] event in
                coordinator?.handleBlockContextMenu(event) ?? false
            }
        }
        context.coordinator.applyDocumentText()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SingleSurfaceNoteEditor
        weak var textView: NSTextView?
        fileprivate let textStorageDelegateBridge = TextStorageDelegateBridge()
        private var isApplyingModelUpdate = false
        private var pendingSelection: NSRange?
        private var currentSlashQuery: SlashQueryMatch?
        private var slashMatches: [SlashCommandMatch] = []
        private var highlightedSlashIndex = 0
        private var slashMenuPopover: NSPopover?
        private var slashMenuHost: NSHostingController<SlashCommandMenuView>?
        /// Last document snapshot for which `EditorVisualStyle.apply` ran (full equality skips redraw when text and metadata match).
        private var lastStyledDocument: NoteDocument?

        private weak var chromeOverlay: BlockChromeOverlayView?
        private var hoveredBlockID: String?
        private var mouseMonitor: Any?
        private var textViewFrameObserver: NSObjectProtocol?
        private var clipBoundsObserver: NSObjectProtocol?

        init(_ parent: SingleSurfaceNoteEditor) {
            self.parent = parent
            super.init()
            textStorageDelegateBridge.owner = self
        }

        /// Forwards TextKit storage callbacks on the main thread; `Coordinator` cannot adopt `NSTextStorageDelegate` directly under Swift 6 isolation rules.
        fileprivate final class TextStorageDelegateBridge: NSObject, NSTextStorageDelegate {
            nonisolated(unsafe) weak var owner: Coordinator?

            func textStorage(
                _ textStorage: NSTextStorage,
                didProcessEditing editedMask: NSTextStorageEditActions,
                range editedRange: NSRange,
                changeInLength delta: Int
            ) {
                guard let owner else { return }
                let ownerPtr = Unmanaged.passUnretained(owner).toOpaque()
                nonisolated(unsafe) let storage = textStorage
                MainActor.assumeIsolated {
                    let coordinator = Unmanaged<Coordinator>.fromOpaque(ownerPtr).takeUnretainedValue()
                    coordinator.textStorageDidProcessEditing(
                        storage,
                        editedMask: editedMask,
                        editedRange: editedRange,
                        delta: delta
                    )
                }
            }
        }

        func setupChrome(scrollView: NSScrollView, textView: NSTextView) {
            guard let clipView = scrollView.contentView as? NSClipView else { return }
            clipView.postsBoundsChangedNotifications = true

            let chrome = BlockChromeOverlayView()
            chrome.textView = textView
            chrome.autoresizingMask = [.width, .height]
            clipView.addSubview(chrome, positioned: .above, relativeTo: textView)
            chrome.frame = textView.frame
            chromeOverlay = chrome

            textViewFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: textView,
                queue: .main
            ) { [weak self] _ in
                self?.syncChromeFrame()
                self?.refreshBlockChrome()
            }

            clipBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.syncChromeFrame()
                self?.refreshBlockChrome()
            }

            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .scrollWheel]) { [weak self] event in
                self?.handleMouseMovedForChrome(event)
                return event
            }
        }

        func teardownChrome() {
            textView?.textStorage?.delegate = nil
            textStorageDelegateBridge.owner = nil
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
                mouseMonitor = nil
            }
            if let o = textViewFrameObserver {
                NotificationCenter.default.removeObserver(o)
                textViewFrameObserver = nil
            }
            if let o = clipBoundsObserver {
                NotificationCenter.default.removeObserver(o)
                clipBoundsObserver = nil
            }
            hoveredBlockID = nil
            chromeOverlay?.removeFromSuperview()
            chromeOverlay = nil
        }

        private func syncChromeFrame() {
            guard let textView, let chrome = chromeOverlay else { return }
            chrome.frame = textView.frame
        }

        private func handleMouseMovedForChrome(_ event: NSEvent) {
            guard let textView, let window = textView.window, window == event.window else { return }
            let local = textView.convert(event.locationInWindow, from: nil)
            guard textView.bounds.contains(local) else {
                if hoveredBlockID != nil {
                    hoveredBlockID = nil
                    refreshBlockChrome()
                }
                return
            }
            let idx = textView.characterIndex(for: local)
            guard idx != NSNotFound else { return }
            let blocks = parent.document.metadata.blocks
            let newHover = DocumentLayoutController.blockIndex(at: idx, blocks: blocks).map { blocks[$0].id }
            if newHover != hoveredBlockID {
                hoveredBlockID = newHover
                refreshBlockChrome()
            }
        }

        private func refreshBlockChrome() {
            guard let textView, let overlay = chromeOverlay else { return }
            let blocks = parent.document.metadata.blocks
            let loc = textView.selectedRange().location
            let focused = DocumentLayoutController.blockIndex(at: loc, blocks: blocks).map { blocks[$0].id }
            overlay.blocks = blocks
            overlay.focusedBlockID = focused
            overlay.hoveredBlockID = hoveredBlockID
            overlay.invalidateGeometry()
        }

        @objc private func blockTypeMenuClicked(_ sender: NSMenuItem) {
            guard let rep = sender.representedObject as? BlockTypeMenuRep, let textView else { return }
            _ = runCommandSession(
                textView: textView,
                commands: [.changeBlockType(blockID: rep.blockID, type: rep.type, headingLevel: rep.headingLevel)]
            )
        }

        @objc private func blockMenuDuplicate(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String, let textView else { return }
            _ = runCommandSession(textView: textView, commands: [.duplicateBlock(blockID: id)])
        }

        @objc private func blockMenuDelete(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String, let textView else { return }
            _ = runCommandSession(textView: textView, commands: [.deleteBlock(blockID: id)])
        }

        fileprivate func handleBlockContextMenu(_ event: NSEvent) -> Bool {
            guard let textView else { return false }
            let local = textView.convert(event.locationInWindow, from: nil)
            let idx = textView.characterIndex(for: local)
            guard idx != NSNotFound else { return false }
            let blocks = parent.document.metadata.blocks
            guard let bIndex = DocumentLayoutController.blockIndex(at: idx, blocks: blocks) else { return false }
            let block = blocks[bIndex]

            let menu = NSMenu(title: "Block")
            let typeMenu = NSMenu(title: "Change Block Type")
            func addTypeItem(_ title: String, type: BlockType, headingLevel: Int?) {
                let item = NSMenuItem(title: title, action: #selector(blockTypeMenuClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = BlockTypeMenuRep(blockID: block.id, type: type, headingLevel: headingLevel)
                typeMenu.addItem(item)
            }
            addTypeItem("Paragraph", type: .paragraph, headingLevel: nil)
            addTypeItem("Heading 1", type: .heading, headingLevel: 1)
            addTypeItem("Heading 2", type: .heading, headingLevel: 2)
            addTypeItem("Heading 3", type: .heading, headingLevel: 3)
            addTypeItem("List Item", type: .listItem, headingLevel: nil)
            addTypeItem("Callout", type: .callout, headingLevel: nil)
            addTypeItem("Code", type: .code, headingLevel: nil)
            addTypeItem("Divider", type: .divider, headingLevel: nil)

            let typeItem = NSMenuItem(title: "Change Block Type", action: nil, keyEquivalent: "")
            typeItem.submenu = typeMenu

            let dup = NSMenuItem(title: "Duplicate Block", action: #selector(blockMenuDuplicate(_:)), keyEquivalent: "")
            dup.target = self
            dup.representedObject = block.id

            let del = NSMenuItem(title: "Delete Block", action: #selector(blockMenuDelete(_:)), keyEquivalent: "")
            del.target = self
            del.representedObject = block.id

            menu.addItem(typeItem)
            menu.addItem(.separator())
            menu.addItem(dup)
            menu.addItem(del)

            NSMenu.popUpContextMenu(menu, with: event, for: textView)
            return true
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

        fileprivate func textStorageDidProcessEditing(
            _ textStorage: NSTextStorage,
            editedMask: NSTextStorageEditActions,
            editedRange: NSRange,
            delta: Int
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
                // Block structure may be partially collapsed; reconcile heading types, then apply via the command pipeline.
                let previous = parent.document.text
                let oldBlocks = parent.document.metadata.blocks
                let replaceCmd = EditCommand.replaceText(
                    range: TextRange(start: 0, length: previous.utf16.count),
                    replacement: storageString
                )
                let afterReplace = EditCommandEngine.apply(replaceCmd, to: parent.document)
                let reconciled = EditCommandEngine.reconcileBlocksFromText(document: afterReplace, oldText: previous, oldBlocks: oldBlocks)
                var commands: [EditCommand] = [replaceCmd]
                if reconciled.metadata.blocks != afterReplace.metadata.blocks {
                    commands.append(.replaceMetadataBlocks(blocks: reconciled.metadata.blocks))
                }
                _ = runCommandSession(textView: textView, commands: commands)
                parent.onFullReplaceWarning?()
            }
        }

        private func inlineTriggerCommands(
            storageText: String,
            insertion: (range: NSRange, replacement: String)
        ) -> [EditCommand]? {
            guard
                let blockIndex = DocumentLayoutController.blockIndexMatchingTextEngineInsertion(
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
            guard textView.window != nil else { return }
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
                let blockIndex = DocumentLayoutController.blockIndexMatchingTextEngineInsertion(
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
            defer {
                refreshBlockChrome()
                applyEditorFindFromQuery()
            }
            guard let textView else { return }
            // Avoid clobbering an in-flight IME composition when the model updates (e.g. external reload).
            if textView.hasMarkedText() { return }

            if textView.string == parent.document.text {
                refreshVisualChrome(textView: textView, document: parent.document)
                applyPendingSelectionIfNeeded()
                applyPendingEditorScrollIfNeeded(textView: textView)
                refreshSlashMenuState(for: textView)
                EditorSyncController.sampleAndLogDriftIfNeeded(
                    document: parent.document,
                    textView: textView,
                    sampleRate: EditorSyncController.driftSampleRate
                )
                return
            }

            let savedSelection = textView.selectedRange()
            var applying = isApplyingModelUpdate
            let didFullReplace = EditorSyncController.applyModelText(
                to: textView,
                modelText: parent.document.text,
                isApplyingModelUpdate: &applying
            )
            isApplyingModelUpdate = applying
            if didFullReplace {
                restoreSelectionClamped(savedSelection)
            }
            refreshVisualChrome(textView: textView, document: parent.document)
            applyPendingSelectionIfNeeded()
            applyPendingEditorScrollIfNeeded(textView: textView)
            refreshSlashMenuState(for: textView)
            EditorSyncController.sampleAndLogDriftIfNeeded(
                document: parent.document,
                textView: textView,
                sampleRate: EditorSyncController.driftSampleRate
            )
        }

        /// Selects the first case-insensitive match of the bound find query at or after the caret, wrapping to the document start.
        private func applyEditorFindFromQuery() {
            guard let textView else { return }
            guard !textView.hasMarkedText() else { return }
            let trimmed = parent.editorFindQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let hay = textView.string as NSString
            let fullLen = hay.length
            guard fullLen > 0 else { return }

            let opts: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            let sel = textView.selectedRange()
            var start = NSMaxRange(sel)
            if start > fullLen { start = 0 }

            var r = hay.range(of: trimmed, options: opts, range: NSRange(location: start, length: fullLen - start))
            if r.location == NSNotFound, start > 0 {
                r = hay.range(of: trimmed, options: opts, range: NSRange(location: 0, length: fullLen))
            }
            guard r.location != NSNotFound else { return }

            textView.setSelectedRange(r)
            textView.scrollRangeToVisible(r)
        }

        private func refreshVisualChrome(textView: NSTextView, document: NoteDocument) {
            let linkOverlay = WikiLinkPresentationPolicy.isFrontendEnabled ? document.metadata.links : []
            if lastStyledDocument == document {
                if let w = textView as? WikiLinkTextView {
                    w.wikiLinks = linkOverlay
                }
                return
            }
            EditorVisualStyle.apply(to: textView, document: document)
            lastStyledDocument = document
            if let w = textView as? WikiLinkTextView {
                w.wikiLinks = linkOverlay
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

        private func applyPendingEditorScrollIfNeeded(textView: NSTextView) {
            guard let p = parent.pendingEditorScroll,
                  p.noteID == parent.document.metadata.noteID,
                  !p.range.isEmpty
            else { return }
            let maxLen = (textView.string as NSString).length
            let clamped = p.range.clamped(to: maxLen)
            guard clamped.length > 0 else {
                parent.onPendingEditorScrollConsumed?()
                return
            }
            let nsr = NSRange(location: clamped.start, length: clamped.length)
            textView.setSelectedRange(nsr)
            textView.scrollRangeToVisible(nsr)
            parent.onPendingEditorScrollConsumed?()
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
                // After splitting, if the split-target block ended up as a heading (either because it
                // was already a heading or because a slash command in the same batch promoted it),
                // demote the newly created successor block to paragraph.
                let didSplit = structural.contains { if case .splitBlock = $0 { return true }; return false }
                // Capture the ID of the block that will be split (regardless of its current type).
                // We check its type *after* the commands run so that slash-command promotions are included.
                let splitTargetBlockID: String? = didSplit
                    ? DocumentLayoutController.blockIndexMatchingTextEngineInsertion(
                        at: selectedLocation,
                        blocks: parent.document.metadata.blocks
                      ).map { parent.document.metadata.blocks[$0].id }
                    : nil

                let targetSelection = NSRange(location: affectedCharRange.location + replacement.utf16.count, length: 0)
                let afterSplit = runCommandSession(
                    textView: textView,
                    commands: structural,
                    pendingSelection: targetSelection
                )

                if let splitID = splitTargetBlockID,
                   let origIndex = afterSplit.metadata.blocks.firstIndex(where: { $0.id == splitID }),
                   afterSplit.metadata.blocks[origIndex].type == .heading,
                   origIndex + 1 < afterSplit.metadata.blocks.count {
                    let newBlock = afterSplit.metadata.blocks[origIndex + 1]
                    if newBlock.type == .heading {
                        _ = runCommandSession(textView: textView, commands: [
                            .changeBlockType(blockID: newBlock.id, type: .paragraph, headingLevel: nil)
                        ])
                    }
                }

                return false
            }

            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let r = tv.selectedRange()
            let loc = r.location
            if parent.cursorOffset != loc {
                parent.cursorOffset = loc
            }
            let tr = MiranNotesCore.TextRange(start: r.location, length: r.length)
            if parent.editorTextSelection != tr {
                parent.editorTextSelection = tr
            }
            refreshSlashMenuState(for: tv)
            refreshBlockChrome()
            syncTypingFont(textView: tv)
        }

        /// Keeps `typingAttributes` font in sync with the block at the cursor so characters
        /// typed into an empty or newly-created block appear at the correct size immediately.
        private func syncTypingFont(textView: NSTextView) {
            let docLength = (parent.document.text as NSString).length
            let rawLoc = textView.selectedRange().location
            let loc = min(rawLoc, docLength)
            let blocks = parent.document.metadata.blocks
            guard let idx = DocumentLayoutController.blockIndex(at: loc, blocks: blocks) else { return }
            let desired = EditorVisualStyle.fontForBlock(blocks[idx])
            var attrs = textView.typingAttributes
            if (attrs[.font] as? NSFont) != desired {
                attrs[.font] = desired
                textView.typingAttributes = attrs
            }
        }

        @discardableResult
        private func runCommandSession(
            textView: NSTextView,
            commands: [EditCommand],
            pendingSelection: NSRange? = nil
        ) -> NoteDocument {
            defer { refreshBlockChrome() }
            if let pendingSelection {
                self.pendingSelection = pendingSelection
            }
            let newDoc = parent.onCommands(commands)

            // Apply the canonical model text immediately so both mutation paths stay ordered.
            // **EditorSyncController** is the only supported path for this sync (see EditorSyncController.swift).
            var applying = isApplyingModelUpdate
            EditorSyncController.applyCanonicalDocument(
                to: textView,
                newDoc: newDoc,
                isApplyingModelUpdate: &applying
            )
            isApplyingModelUpdate = applying

            refreshVisualChrome(textView: textView, document: newDoc)
            applyPendingSelectionIfNeeded()
            refreshSlashMenuState(for: textView)
            EditorSyncController.sampleAndLogDriftIfNeeded(
                document: newDoc,
                textView: textView,
                sampleRate: EditorSyncController.driftSampleRate
            )
            return newDoc
        }
    }
}

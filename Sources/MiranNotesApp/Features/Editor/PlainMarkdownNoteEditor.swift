import AppKit
import MiranNotesCore
import SwiftUI

/// Plain note body as markdown source: minimal structure UI; relies on ``EditCommand/replaceText`` and save-time normalization.
struct PlainMarkdownNoteEditor: NSViewRepresentable {
    @Binding var document: NoteDocument
    @Binding var cursorOffset: Int
    @Binding var editorTextSelection: MiranNotesCore.TextRange
    @Binding var editorFindQuery: String
    var modules: EditorModuleFlags
    var pendingEditorScroll: PendingEditorScroll?
    var onPendingEditorScrollConsumed: (() -> Void)?
    var onCommands: ([EditCommand]) -> NoteDocument
    var onWikiLinkClick: ((UUID) -> Void)?
    var onFullReplaceWarning: (() -> Void)?
    var onSizeLimitExceeded: (() -> Void)?
    var focusBodyNonce: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteEditorWikiLinkTextView()
        textView.isEditable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.usesFontPanel = false
        textView.textContainerInset = NSSize(width: 48, height: 24)
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
        coordinator.bindWikiAndFormattingHandlers(textView: textView)
        coordinator.applyDocumentText()
        return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let tv = nsView.documentView as? NoteEditorWikiLinkTextView {
            context.coordinator.bindWikiAndFormattingHandlers(textView: tv)
        }
        context.coordinator.applyDocumentText()
        let nonce = focusBodyNonce
        if nonce != context.coordinator.lastAppliedBodyFocusNonce {
            context.coordinator.lastAppliedBodyFocusNonce = nonce
            if let tv = nsView.documentView as? NSTextView {
                tv.window?.makeFirstResponder(tv)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainMarkdownNoteEditor
        weak var textView: NSTextView?
        fileprivate var lastAppliedBodyFocusNonce: Int = 0
        fileprivate let textStorageDelegateBridge = TextStorageDelegateBridge()
        private var isApplyingModelUpdate = false
        private var pendingSelection: NSRange?
        private var currentSlashQuery: SlashQueryMatch?
        private var slashMatches: [SlashCommandMatch] = []
        private var highlightedSlashIndex = 0
        private var slashMenuPopover: NSPopover?
        private var slashMenuHost: NSHostingController<EditorSlashCommandMenuView>?
        private var lastStyledDocument: NoteDocument?

        init(_ parent: PlainMarkdownNoteEditor) {
            self.parent = parent
            super.init()
            textStorageDelegateBridge.owner = self
        }

        func bindWikiAndFormattingHandlers(textView: NoteEditorWikiLinkTextView) {
            let wikiClick =
                WikiLinkPresentationPolicy.isFrontendEnabled && parent.modules.wikiLinkClickThrough
            textView.linkHitHandler = wikiClick
                ? { [weak self] id in
                    self?.parent.onWikiLinkClick?(id)
                }
                : nil
            textView.wikiLinks =
                (WikiLinkPresentationPolicy.isFrontendEnabled && wikiClick)
                ? parent.document.metadata.links
                : []
            textView.formattingCommandHandler = { [weak self] style in
                self?.toggleSpanStyle(style)
            }
            textView.slashMenuCommandHandler = { [weak self] command in
                self?.handleSlashMenuCommand(command) ?? false
            }
            textView.blockContextMenuHandler = nil
        }

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
                    coordinator.consumeTextStorageEdit(
                        storage,
                        editedMask: editedMask,
                        editedRange: editedRange,
                        delta: delta
                    )
                }
            }
        }

        func teardown() {
            textView?.textStorage?.delegate = nil
            textStorageDelegateBridge.owner = nil
            slashMenuPopover?.performClose(nil)
            slashMenuPopover = nil
            slashMenuHost = nil
        }

        fileprivate func consumeTextStorageEdit(
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
                let previous = parent.document.text
                let oldBlocks = parent.document.metadata.blocks
                let replaceCmd = EditCommand.replaceText(
                    range: TextRange(start: 0, length: previous.utf16.count),
                    replacement: storageString
                )
                let afterReplace = EditCommandEngine.apply(replaceCmd, to: parent.document)
                let reconciled = EditCommandEngine.reconcileBlocksFromText(
                    document: afterReplace,
                    oldText: previous,
                    oldBlocks: oldBlocks
                )
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
            guard parent.modules.markdownShortcutDetector else { return nil }
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

            guard parent.modules.slashMenu else { return nil }
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
            guard parent.modules.slashMenu else {
                closeSlashMenu()
                return
            }
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
            let host = NSHostingController(rootView: EditorSlashCommandMenuView(
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
            host.rootView = EditorSlashCommandMenuView(
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
                applyEditorFindFromQuery()
            }
            guard let textView else { return }
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
                NoteEditorNSTextViewSynchronizer.restoreSelectionClamped(savedSelection, textView: textView)
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

        private func applyEditorFindFromQuery() {
            guard let textView else { return }
            guard !textView.hasMarkedText() else { return }
            guard textView.window?.firstResponder === textView else { return }
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
            let wikiClick =
                WikiLinkPresentationPolicy.isFrontendEnabled && parent.modules.wikiLinkClickThrough
            let linkOverlay =
                (WikiLinkPresentationPolicy.isFrontendEnabled && wikiClick) ? document.metadata.links : []
            if lastStyledDocument == document {
                if let w = textView as? NoteEditorWikiLinkTextView {
                    w.wikiLinks = linkOverlay
                }
                return
            }
            EditorVisualStyle.applyPlainMarkdownSource(to: textView, document: document)
            lastStyledDocument = document
            if let w = textView as? NoteEditorWikiLinkTextView {
                w.wikiLinks = linkOverlay
            }
        }

        private func applyPendingSelectionIfNeeded() {
            guard let textView, let pendingSelection else { return }
            let maxOffset = textView.string.utf16.count
            let clampedLocation = min(max(0, pendingSelection.location), maxOffset)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
            self.pendingSelection = nil
        }

        private func applyPendingEditorScrollIfNeeded(textView: NSTextView) {
            NoteEditorNSTextViewSynchronizer.applyPendingEditorScroll(
                textView: textView,
                pending: parent.pendingEditorScroll,
                documentNoteID: parent.document.metadata.noteID,
                onConsumed: { parent.onPendingEditorScrollConsumed?() }
            )
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

            let newLength = (textView.string.utf16.count - affectedCharRange.length) + replacement.utf16.count
            if newLength > 1_048_576 {
                parent.onSizeLimitExceeded?()
                return false
            }

            guard parent.modules.layoutControllerNewlineRules else { return true }

            let selectedLocation = textView.selectedRange().location

            if let structural = DocumentLayoutController.commandsForEdit(
                document: parent.document,
                affectedRange: affectedCharRange,
                replacement: replacement,
                selectedLocation: selectedLocation
            ) {
                let didSplit = structural.contains { if case .splitBlock = $0 { return true }; return false }
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

        fileprivate func handleSlashMenuCommand(_ command: NoteEditorSlashMenuCommand) -> Bool {
            guard parent.modules.slashMenu else { return false }
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

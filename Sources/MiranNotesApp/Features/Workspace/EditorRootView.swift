import AppKit
import MiranNotesCore
import SwiftUI

struct EditorRootView: View {
    @Bindable var model: AppModel
    var paneIndex: Int = 0
    @Environment(\.undoManager) private var undoManager
    @State private var repairDetailsPresented = false
    @State private var editorBodyFocusNonce = 0

    var body: some View {
        Group {
            if model.workspacePanes.indices.contains(paneIndex),
                let current = model.workspacePanes[paneIndex].activeDocument {
                editorChrome(for: current)
            }
        }
        .onAppear {
            if paneIndex == model.activePaneIndex {
                model.setUndoManager(undoManager)
            }
        }
        .onChange(of: undoManager) { _, newValue in
            if paneIndex == model.activePaneIndex {
                model.setUndoManager(newValue)
            }
        }
        .onChange(of: model.activePaneIndex) { _, newValue in
            if newValue == paneIndex {
                model.setUndoManager(undoManager)
            }
        }
    }

    @ViewBuilder
    private func editorChrome(for current: NoteDocument) -> some View {
        VStack(spacing: 0) {
            if let diskHint = model.diskActivityBanner {
                DiskActivityBanner(text: diskHint, onDismiss: { model.dismissDiskActivityBanner() })
            }
            if let advisory = model.workspacePanes[paneIndex].repairAdvisory {
                RepairNoticeBanner(
                    advisory: advisory,
                    onDismiss: { model.dismissRepairAdvisory(pane: paneIndex) },
                    onShowInFinder: { model.revealSelectedNoteFileInFinder(pane: paneIndex) },
                    onDetails: { repairDetailsPresented = true },
                    showDetailsButton: advisory.detailsPlainText != nil
                )
                .sheet(isPresented: $repairDetailsPresented) {
                    RepairAdvisoryDetailsSheet(
                        detailsText: advisory.detailsPlainText ?? "",
                        onDone: { repairDetailsPresented = false }
                    )
                }
            }
            NoteEditorTitleHeader(model: model, paneIndex: paneIndex) {
                editorBodyFocusNonce += 1
            }
            NoteTagStripView(model: model, paneIndex: paneIndex)
            NoteFindBarView(model: model, paneIndex: paneIndex)
            noteEditorSurface(fallbackDocument: current)
                .id(
                    "\(model.effectiveEditorActivationProfile(forPane: paneIndex).editorKind.rawValue)-\(model.workspacePanes[paneIndex].selectedNoteID?.uuidString ?? "none")-fs\(AppSettings.shared.editorBodyPointSize)"
                )
            if WikiLinkPresentationPolicy.isFrontendEnabled {
                BacklinksPanelView(model: model, paneIndex: paneIndex)
            }
        }
        .navigationTitle("")
        .toolbar {
            if model.effectiveEditorActivationProfile(forPane: paneIndex).editorKind == .plainMarkdownSource {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.toggleMarkdownPreview(pane: paneIndex)
                    } label: {
                        Label(
                            "Markdown preview",
                            systemImage: model.workspacePanes[paneIndex].showMarkdownPreview ? "eye.fill" : "eye"
                        )
                    }
                    .help(
                        model.workspacePanes[paneIndex].showMarkdownPreview
                            ? "Hide rendered preview"
                            : "Show rendered preview beside source"
                    )
                }
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                if model.activePaneIndex != paneIndex {
                    model.activatePane(index: paneIndex)
                }
            }
        )
    }

    @ViewBuilder
    private func plainMarkdownEditorSurface(
        pane p: Int,
        fallbackDocument: NoteDocument,
        modules: EditorModuleFlags,
        wiki: ((UUID) -> Void)?,
        focusBodyFocusNonce: Int
    ) -> some View {
        PlainMarkdownNoteEditor(
            document: Binding(
                get: { model.workspacePanes[p].activeDocument ?? fallbackDocument },
                set: { model.workspacePanes[p].activeDocument = $0 }
            ),
            cursorOffset: Binding(
                get: { model.workspacePanes[p].editorCursorOffset },
                set: { model.workspacePanes[p].editorCursorOffset = $0 }
            ),
            editorTextSelection: Binding(
                get: { model.workspacePanes[p].editorTextSelection },
                set: { model.workspacePanes[p].editorTextSelection = $0 }
            ),
            editorFindQuery: Binding(
                get: { model.workspacePanes[p].editorFindQuery },
                set: { model.workspacePanes[p].editorFindQuery = $0 }
            ),
            modules: modules,
            pendingEditorScroll: model.pendingEditorScroll,
            onPendingEditorScrollConsumed: { model.clearPendingEditorScroll() },
            onCommands: { commands in
                if model.activePaneIndex != p {
                    model.activatePaneForEditingSync(p)
                }
                return model.apply(commands)
            },
            onWikiLinkClick: wiki,
            wikiLinkCandidates: { query in
                model.wikiLinkMenuEntries(matching: query, pane: p)
            },
            onCreateWikiLinkTarget: { title, completion in
                model.createWikiLinkTarget(title: title, pane: p, completion: completion)
            },
            onFullReplaceWarning: { model.presentFullBufferAdvisory(pane: p) },
            onSizeLimitExceeded: { model.presentSizeLimitAdvisory(pane: p) },
            focusBodyNonce: focusBodyFocusNonce
        )
    }

    @ViewBuilder
    private func noteEditorSurface(fallbackDocument: NoteDocument) -> some View {
        let p = paneIndex
        let profile = model.effectiveEditorActivationProfile(forPane: p)
        let wiki: ((UUID) -> Void)? =
            WikiLinkPresentationPolicy.isFrontendEnabled
            ? { targetID in
                model.openWikiLink(targetNoteID: targetID, pane: p)
            }
            : nil
        let modules = profile.effectiveModules
        switch profile.editorKind {
        case .blockNative:
            SingleSurfaceNoteEditor(
                document: Binding(
                    get: { model.workspacePanes[p].activeDocument ?? fallbackDocument },
                    set: { model.workspacePanes[p].activeDocument = $0 }
                ),
                cursorOffset: Binding(
                    get: { model.workspacePanes[p].editorCursorOffset },
                    set: { model.workspacePanes[p].editorCursorOffset = $0 }
                ),
                editorTextSelection: Binding(
                    get: { model.workspacePanes[p].editorTextSelection },
                    set: { model.workspacePanes[p].editorTextSelection = $0 }
                ),
                editorFindQuery: Binding(
                    get: { model.workspacePanes[p].editorFindQuery },
                    set: { model.workspacePanes[p].editorFindQuery = $0 }
                ),
                pendingEditorScroll: model.pendingEditorScroll,
                onPendingEditorScrollConsumed: { model.clearPendingEditorScroll() },
                onCommands: { commands in
                    if model.activePaneIndex != p {
                        model.activatePaneForEditingSync(p)
                    }
                    return model.apply(commands)
                },
                onWikiLinkClick: wiki,
                wikiLinkCandidates: { query in
                    model.wikiLinkMenuEntries(matching: query, pane: p)
                },
                onCreateWikiLinkTarget: { title, completion in
                    model.createWikiLinkTarget(title: title, pane: p, completion: completion)
                },
                onAddBlockToTodaysTasks: { blockID, text in
                    guard let noteID = model.workspacePanes[p].activeDocument?.metadata.noteID else { return }
                    model.addNoteBlockToTodaysTasks(noteID: noteID, blockID: blockID, text: text)
                },
                onOpenAttachment: { filename in
                    model.openAttachment(filename: filename, pane: p)
                },
                onAttachFilesDropped: { urls, index in
                    model.attachFiles(urls, pane: p, atUTF16Offset: index)
                },
                onFullReplaceWarning: { model.presentFullBufferAdvisory(pane: p) },
                onSizeLimitExceeded: { model.presentSizeLimitAdvisory(pane: p) },
                focusBodyNonce: editorBodyFocusNonce
            )
        case .plainMarkdownSource:
            if model.workspacePanes[p].showMarkdownPreview {
                HSplitView {
                    plainMarkdownEditorSurface(
                        pane: p,
                        fallbackDocument: fallbackDocument,
                        modules: modules,
                        wiki: wiki,
                        focusBodyFocusNonce: editorBodyFocusNonce
                    )
                    .frame(minWidth: 240)
                    MarkdownRenderedPreview(source: model.workspacePanes[p].activeDocument?.text ?? "")
                        .frame(minWidth: 220, idealWidth: 320)
                }
            } else {
                plainMarkdownEditorSurface(
                    pane: p,
                    fallbackDocument: fallbackDocument,
                    modules: modules,
                    wiki: wiki,
                    focusBodyFocusNonce: editorBodyFocusNonce
                )
            }
        }
    }
}

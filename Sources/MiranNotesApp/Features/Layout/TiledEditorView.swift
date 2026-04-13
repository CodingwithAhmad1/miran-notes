import MiranNotesCore
import SwiftUI

/// The detail-column root for the Notes mode. Renders the active layout — either the
/// classic single-pane editor or a tiled arrangement of multiple note panes.
struct TiledEditorView: View {
    @ObservedObject var model: AppModel
    @State private var layoutSelectorVisible = false

    var body: some View {
        Group {
            switch model.currentLayout {
            case .single:
                singlePaneView

            case .twoPane:
                HSplitView {
                    activePaneContent.frame(minWidth: 280)
                    viewPane(index: 1).frame(minWidth: 200)
                }

            case .threePane:
                HSplitView {
                    activePaneContent.frame(minWidth: 280)
                    VSplitView {
                        viewPane(index: 1).frame(minHeight: 120)
                        viewPane(index: 2).frame(minHeight: 120)
                    }
                    .frame(minWidth: 200)
                }

            case .fourPane:
                HSplitView {
                    VSplitView {
                        activePaneContent.frame(minHeight: 120)
                        viewPane(index: 1).frame(minHeight: 120)
                    }
                    .frame(minWidth: 240)
                    VSplitView {
                        viewPane(index: 2).frame(minHeight: 120)
                        viewPane(index: 3).frame(minHeight: 120)
                    }
                    .frame(minWidth: 200)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    layoutSelectorVisible.toggle()
                } label: {
                    Image(systemName: "rectangle.split.2x2")
                }
                .help("Change layout")
                .popover(isPresented: $layoutSelectorVisible, arrowEdge: .bottom) {
                    LayoutSelectorView(model: model)
                }
            }
        }
    }

    // MARK: - Single-pane

    /// Single layout: delegate to the full `EditorRootView` which includes the backlinks panel.
    @ViewBuilder
    private var singlePaneView: some View {
        if model.activeDocument != nil {
            EditorRootView(model: model)
        } else {
            ContentUnavailableView(
                "Select a note",
                systemImage: "note.text",
                description: Text("Create or open a note to start editing.")
            )
            .toolbar {
                // Placeholder toolbar group so the layout button sits alongside the
                // empty-state detail column without jumping on layout change.
                ToolbarItemGroup { EmptyView() }
            }
        }
    }

    // MARK: - Multi-pane: active pane

    /// In multi-pane mode the active pane shows the editor surface only (no backlinks panel)
    /// to keep each pane spacious.
    @ViewBuilder
    private var activePaneContent: some View {
        ActiveEditorPane(model: model)
            .overlay(alignment: .topLeading) {
                // Accent border marks which pane is currently editable.
                Rectangle()
                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
    }

    // MARK: - Multi-pane: read-only panes

    @ViewBuilder
    private func viewPane(index: Int) -> some View {
        let slot = index - 1
        if slot < model.viewPaneStates.count {
            let state = model.viewPaneStates[slot]
            ReadOnlyPaneView(
                state: state,
                isActive: model.activePaneIndex == index
            ) {
                model.activatePane(index: index)
            }
        } else {
            // Safety fallback — should not happen if viewPaneStates is sized correctly.
            ReadOnlyPaneView(
                state: ViewPaneState(),
                isActive: false
            ) {
                model.activatePane(index: index)
            }
        }
    }
}

// MARK: - Active editor pane (multi-pane mode)

/// Stripped editor: SingleSurfaceNoteEditor + activity banners, without the backlinks sidebar.
/// Used as the active/editable pane in two-, three-, and four-pane layouts.
private struct ActiveEditorPane: View {
    @ObservedObject var model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var repairDetailsPresented = false

    var body: some View {
        Group {
            if let current = model.activeDocument {
                VStack(spacing: 0) {
                    if let diskHint = model.diskActivityBanner {
                        DiskActivityBanner(text: diskHint, onDismiss: { model.dismissDiskActivityBanner() })
                    }
                    if let advisory = model.repairAdvisory {
                        RepairNoticeBanner(
                            advisory: advisory,
                            onDismiss: { model.dismissRepairAdvisory() },
                            onShowInFinder: { model.revealSelectedNoteFileInFinder() },
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
                    SingleSurfaceNoteEditor(
                        document: Binding(
                            get: { model.activeDocument ?? current },
                            set: { model.activeDocument = $0 }
                        ),
                        cursorOffset: $model.editorCursorOffset,
                        editorTextSelection: $model.editorTextSelection,
                        pendingEditorScroll: model.pendingEditorScroll,
                        onPendingEditorScrollConsumed: { model.clearPendingEditorScroll() },
                        onCommands: { commands in model.apply(commands) },
                        onWikiLinkClick: { targetID in model.openNote(noteID: targetID) },
                        onFullReplaceWarning: { model.presentFullBufferAdvisory() },
                        onSizeLimitExceeded: { model.presentSizeLimitAdvisory() }
                    )
                }
                .toolbar {
                    ToolbarItemGroup {
                        Menu("Link") {
                            ForEach(
                                model.noteSummaries.filter { $0.noteID != current.metadata.noteID },
                                id: \.relativePath
                            ) { note in
                                Button(note.title) {
                                    model.insertWikiLink(to: note.noteID, displayText: note.title)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a note",
                    systemImage: "note.text",
                    description: Text("Click to activate this pane, then pick a note from the sidebar.")
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    // Tapping the empty active pane is a no-op (it is already active).
                }
            }
        }
        .onAppear { model.setUndoManager(undoManager) }
        .onChange(of: undoManager) { _, newValue in model.setUndoManager(newValue) }
    }
}


import AppKit
import MiranNotesCore
import SwiftUI

// MARK: - Workspace detail (folder list vs note editor)

/// Matches `NSTextView` / markdown preview document surface so the detail column reads as one paper sheet.
enum WorkspaceDocumentSurface {
    static var background: Color { Color(nsColor: .textBackgroundColor) }
}

struct WorkspaceDetailColumnView: View {
    @Bindable var model: AppModel
    var paneIndex: Int
    var sidebarColumnVisibility: Binding<NavigationSplitViewVisibility>
    var onClearToolbarSearchFocus: () -> Void
    /// When non-`nil`, this column shows a per-tile search field in its local toolbar (multi-pane layouts).
    var multipaneSearchFocused: Binding<Bool>? = nil
    var onWorkspaceShortcutsChanged: () -> Void = {}
    @Environment(\.controlActiveState) private var controlActiveState

    private func showsLoadedEditor(forPane pane: Int) -> Bool {
        guard model.workspacePanes.indices.contains(pane) else { return false }
        let s = model.workspacePanes[pane]
        guard let doc = s.activeDocument, let id = s.selectedNoteID else { return false }
        return doc.metadata.noteID == id
    }

    private var paneSearchPlaceholder: String {
        if model.isFolderManagementPresented {
            return String(localized: "Search vault…")
        }
        guard model.workspacePanes.indices.contains(paneIndex) else { return "" }
        let s = model.workspacePanes[paneIndex]
        return s.selectedNoteID != nil
            ? String(localized: "Find in note…")
            : String(localized: "Search vault…")
    }

    private func paneSearchTextBinding() -> Binding<String> {
        Binding(
            get: {
                if model.isFolderManagementPresented {
                    return model.vaultSearchQuery
                }
                guard model.workspacePanes.indices.contains(paneIndex) else { return "" }
                let s = model.workspacePanes[paneIndex]
                return s.selectedNoteID != nil ? s.editorFindQuery : s.vaultSearchQuery
            },
            set: { newValue in
                if model.isFolderManagementPresented {
                    model.vaultSearchQuery = newValue
                } else {
                    guard model.workspacePanes.indices.contains(paneIndex) else { return }
                    if model.workspacePanes[paneIndex].selectedNoteID != nil {
                        model.workspacePanes[paneIndex].editorFindQuery = newValue
                    } else {
                        model.workspacePanes[paneIndex].vaultSearchQuery = newValue
                    }
                }
            }
        )
    }

    private static let paneSearchMinWidth: CGFloat = 140
    private static let paneSearchIdealWidth: CGFloat = 220
    private static let paneSearchMaxWidth: CGFloat = 480

    @ViewBuilder
    private func paneToolbarSearchField(focusBinding: Binding<Bool>) -> some View {
        let showsSearchRing = focusBinding.wrappedValue && controlActiveState == .active
        ToolbarSearchField(
            text: paneSearchTextBinding(),
            isFocused: focusBinding,
            placeholder: paneSearchPlaceholder
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minWidth: Self.paneSearchMinWidth, idealWidth: Self.paneSearchIdealWidth, maxWidth: Self.paneSearchMaxWidth, minHeight: 28)
        .overlay {
            if showsSearchRing {
                Capsule().strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
            }
        }
        .accessibilityLabel(paneSearchPlaceholder)
        .onChange(of: focusBinding.wrappedValue) { _, focused in
            if focused {
                model.activatePane(index: paneIndex)
            }
        }
    }

    private var showsMultipaneToolbarSearch: Bool {
        guard multipaneSearchFocused != nil, model.currentLayout != .single else { return false }
        if model.isFolderManagementPresented {
            return paneIndex == model.activePaneIndex
        }
        return true
    }

    private var showsMultipaneSidebarExpandControl: Bool {
        multipaneSearchFocused != nil
            && model.currentLayout != .single
            && sidebarColumnVisibility.wrappedValue == .detailOnly
    }

    var body: some View {
        Group {
            if model.workspacePanes.indices.contains(paneIndex) {
                Group {
                    if model.isFolderManagementPresented {
                        if paneIndex == model.activePaneIndex {
                            FolderManagementDashboardView(
                                model: model,
                                onWorkspaceShortcutsChanged: onWorkspaceShortcutsChanged
                            )
                        } else {
                            ContentUnavailableView(
                                "Folder management",
                                systemImage: "folder.badge.gearshape",
                                description: Text("Open in the highlighted pane to manage folders.")
                            )
                        }
                    } else if showsLoadedEditor(forPane: paneIndex) {
                        EditorRootView(model: model, paneIndex: paneIndex)
                    } else if model.workspacePanes[paneIndex].selectedNoteID != nil {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading note…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        FolderPageView(model: model, paneIndex: paneIndex)
                    }
                }
                .frame(minHeight: 0, maxHeight: .infinity)
                .simultaneousGesture(
                    TapGesture().onEnded { _ in
                        onClearToolbarSearchFocus()
                        model.activatePane(index: paneIndex)
                    }
                )
                .background {
                    ZStack(alignment: .topLeading) {
                        WorkspaceDocumentSurface.background
                        if paneIndex == model.activePaneIndex || model.currentLayout == .single {
                            GeometryReader { geo in
                                Color.clear.preference(key: DetailColumnWidthPreferenceKey.self, value: geo.size.width)
                            }
                        }
                    }
                }
                .toolbar {
                    if showsMultipaneSidebarExpandControl {
                        ToolbarItem(placement: .navigation) {
                            WorkspaceSidebarExpandToolbarButton {
                                onClearToolbarSearchFocus()
                                sidebarColumnVisibility.wrappedValue = .all
                            }
                        }
                    }
                    if showsMultipaneToolbarSearch, let multipaneSearchFocused {
                        ToolbarItem(placement: .principal) {
                            paneToolbarSearchField(focusBinding: multipaneSearchFocused)
                        }
                    }
                }
                .onChange(of: model.activePaneIndex) { _, newIdx in
                    if let binding = multipaneSearchFocused, newIdx != paneIndex {
                        binding.wrappedValue = false
                    }
                }
            }
        }
    }
}

struct FolderFirstNoteBodyFormatSheet: View {
    var onChooseBlocks: () -> Void
    var onChooseMarkdown: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("This folder does not have any notes yet. Choose how new notes should be stored on disk.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: onChooseBlocks) {
                        Label("Miran blocks (.txt)", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    Button(action: onChooseMarkdown) {
                        Label("Markdown source (.md)", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(minWidth: 380, minHeight: 220)
            .navigationTitle("Note format")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

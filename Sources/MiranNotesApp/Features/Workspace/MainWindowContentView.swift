import AppKit
import MiranNotesCore
import SwiftUI

// MARK: - Main window (vault open)

struct DetailColumnWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum WorkspaceSidebarColumnVisibilityStore {
    static func userDefaultsKey(paneIndex: Int) -> String {
        "workspace.sidebarCollapsedPane\(paneIndex)"
    }
}

struct WorkspaceSidebarExpandToolbarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(Color(nsColor: .quaternarySystemFill))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
        .help("Show sidebar")
        .accessibilityLabel("Show sidebar")
    }
}

struct MiranNotesMainWindowContent: View {
    @Bindable var model: AppModel
    @Environment(VaultSessionRegistry.self) private var vaultSessionRegistry
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.scenePhase) private var scenePhase
    var presentOpenWorkspacePanel: () -> Void
    @Binding var conflictDetailsPresented: Bool
    @Binding var conflictDetailsDiskDate: Date?
    @Binding var editingHelpPresented: Bool
    var onWorkspaceShortcutsChanged: () -> Void
    @State private var isToolbarSearchFocused = false
    /// Per-tile search field focus in multi-pane layouts (principal search lives in each tile’s `NavigationStack`).
    @State private var multipaneSearchFocused: [Bool] = []
    /// Width of the split view’s detail column (where the unified toolbar lays out). Drives compact search sizing
    /// so AppKit never inserts the toolbar overflow chevron.
    @State private var measuredDetailColumnWidth: CGFloat = 0
    @AppStorage(WorkspaceSidebarColumnVisibilityStore.userDefaultsKey(paneIndex: 0)) private var sidebarCollapsedPane0 = false
    @AppStorage(WorkspaceSidebarColumnVisibilityStore.userDefaultsKey(paneIndex: 1)) private var sidebarCollapsedPane1 = false
    @AppStorage(WorkspaceSidebarColumnVisibilityStore.userDefaultsKey(paneIndex: 2)) private var sidebarCollapsedPane2 = false
    @AppStorage(WorkspaceSidebarColumnVisibilityStore.userDefaultsKey(paneIndex: 3)) private var sidebarCollapsedPane3 = false

    private func clearToolbarSearchFocus() {
        isToolbarSearchFocused = false
        for i in multipaneSearchFocused.indices {
            multipaneSearchFocused[i] = false
        }
    }

    private func multipaneSearchFieldBinding(paneIndex: Int) -> Binding<Bool> {
        Binding(
            get: {
                paneIndex < multipaneSearchFocused.count ? multipaneSearchFocused[paneIndex] : false
            },
            set: { newValue in
                if multipaneSearchFocused.count <= paneIndex {
                    multipaneSearchFocused.append(
                        contentsOf: Array(repeating: false, count: paneIndex + 1 - multipaneSearchFocused.count)
                    )
                }
                multipaneSearchFocused[paneIndex] = newValue
            }
        )
    }

    private func isSidebarCollapsed(paneIndex: Int) -> Bool {
        switch paneIndex {
        case 0: return sidebarCollapsedPane0
        case 1: return sidebarCollapsedPane1
        case 2: return sidebarCollapsedPane2
        case 3: return sidebarCollapsedPane3
        default: return false
        }
    }

    private func setSidebarCollapsed(_ collapsed: Bool, paneIndex: Int) {
        switch paneIndex {
        case 0: sidebarCollapsedPane0 = collapsed
        case 1: sidebarCollapsedPane1 = collapsed
        case 2: sidebarCollapsedPane2 = collapsed
        case 3: sidebarCollapsedPane3 = collapsed
        default: break
        }
    }

    private func sidebarColumnVisibilityBinding(paneIndex: Int) -> Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { isSidebarCollapsed(paneIndex: paneIndex) ? .detailOnly : .all },
            set: { setSidebarCollapsed($0 == .detailOnly, paneIndex: paneIndex) }
        )
    }

    private func sidebarExpandToolbarButton(visibility: Binding<NavigationSplitViewVisibility>) -> some View {
        WorkspaceSidebarExpandToolbarButton {
            clearToolbarSearchFocus()
            visibility.wrappedValue = .all
        }
    }

    var body: some View {
        workspaceRootView
            .onChange(of: model.currentLayout) { _, newLayout in
                multipaneSearchFocused = Array(repeating: false, count: newLayout.paneCount)
            }
            .onChange(of: controlActiveState) { _, newValue in
                if newValue == .inactive {
                    clearToolbarSearchFocus()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    clearToolbarSearchFocus()
                }
            }
            .onAppear {
                multipaneSearchFocused = Array(repeating: false, count: model.currentLayout.paneCount)
                vaultSessionRegistry.registerSession()
            }
            .onDisappear {
                vaultSessionRegistry.unregisterSession()
            }
            .task(id: model.repository.vaultURL.path) {
                model.loadVault()
            }
            .sheet(item: $model.externalTextCompare) { payload in
                ExternalEditCompareSheet(payload: payload) {
                    model.externalTextCompare = nil
                }
            }
            .sheet(item: $model.pendingFolderFirstNoteBodyPicker) { _ in
                FolderFirstNoteBodyFormatSheet(
                    onChooseBlocks: { model.confirmPendingFirstNoteBodyFormat(bodyFileExtension: "txt") },
                    onChooseMarkdown: { model.confirmPendingFirstNoteBodyFormat(bodyFileExtension: "md") },
                    onCancel: { model.cancelPendingFirstNoteBodyPicker() }
                )
            }
            .sheet(isPresented: $editingHelpPresented) {
                EditingHelpSheet {
                    editingHelpPresented = false
                }
            }
            .sheet(isPresented: $model.isTrashPresented) {
                TrashPageView(model: model)
            }
            .sheet(isPresented: $conflictDetailsPresented) {
                NavigationStack {
                    ScrollView {
                        Text(ExternalEditConflictCopy.detailsLines(diskDate: conflictDetailsDiskDate ?? Date()))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(minWidth: 360, minHeight: 200)
                    .navigationTitle("Details")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                conflictDetailsPresented = false
                            }
                        }
                    }
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { model.userAlert != .none },
                    set: { if !$0 { model.userAlert = .none } }
                )
            ) {
                Group {
                    if let kind = model.userAlertRecoveryKind {
                        Button("Retry") {
                            model.performUserAlertRecovery(kind: kind)
                        }
                    }
                    Button("OK", role: .cancel) {
                        model.userAlert = .none
                    }
                }
            } message: {
                Text(model.userAlert.alertMessage)
            }
            .alert(
                ExternalEditConflictCopy.alertTitle,
                isPresented: Binding(
                    get: { model.externalEditConflictAlert != nil },
                    set: { newValue in
                        if !newValue, model.externalEditConflictAlert != nil {
                            model.resolveExternalEditConflict(reloadFromDisk: false)
                        }
                    }
                ),
                presenting: model.externalEditConflictAlert,
                actions: { conflict in
                    Button(ExternalEditConflictCopy.buttonKeepEdits, role: .cancel) {
                        model.resolveExternalEditConflict(reloadFromDisk: false)
                    }
                    Button(ExternalEditConflictCopy.buttonUseSavedFile, role: .destructive) {
                        model.resolveExternalEditConflict(reloadFromDisk: true)
                    }
                    Button(ExternalEditConflictCopy.buttonShowInFinder) {
                        model.revealSelectedNoteFileInFinder()
                    }
                    Button(ExternalEditConflictCopy.buttonDetails) {
                        conflictDetailsDiskDate = conflict.diskDate
                        conflictDetailsPresented = true
                    }
                    Button(ExternalEditConflictCopy.buttonCompare) {
                        model.openExternalEditCompare()
                    }
                },
                message: { _ in
                    Text(ExternalEditConflictCopy.alertMessage)
                }
            )
    }

    private var workspaceRootView: some View {
        Group {
            switch model.workspaceGateState {
            case .checking:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking workspace…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .incompatible(let report):
                WorkspaceIncompatibleView(
                    report: report,
                    vaultRootURL: model.repository.vaultURL,
                    onChooseDifferentFolder: presentOpenWorkspacePanel
                )
            case .ready:
                GeometryReader { geo in
                    readyWorkspaceShell(windowContentWidth: geo.size.width)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Full window content width (sidebar + detail). Used to drop trailing toolbar items before the system
    /// overflow chevron would absorb them on narrow windows.
    @ViewBuilder
    private func readyWorkspaceShell(windowContentWidth: CGFloat) -> some View {
        let toolbarLayoutWidth = Self.effectiveToolbarLayoutWidth(
            detail: measuredDetailColumnWidth,
            window: windowContentWidth
        )
        let outerToolbarLayoutWidth =
            model.currentLayout == .single
            ? toolbarLayoutWidth
            : max(windowContentWidth * 0.45, 320)
        let activePane = model.activePaneIndex
        let activeNote = model.workspacePanes.indices.contains(activePane)
            ? model.workspacePanes[activePane].selectedNoteID : nil

        NavigationStack {
            Group {
                if model.currentLayout == .single {
                    NavigationSplitView(columnVisibility: sidebarColumnVisibilityBinding(paneIndex: 0)) {
                        WorkspaceFolderSidebarView(
                            model: model,
                            paneIndex: 0,
                            sidebarColumnVisibility: sidebarColumnVisibilityBinding(paneIndex: 0),
                            onClearToolbarSearchFocus: clearToolbarSearchFocus
                        )
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
                        .toolbar(removing: .sidebarToggle)
                    } detail: {
                        WorkspaceDetailColumnView(
                            model: model,
                            paneIndex: 0,
                            sidebarColumnVisibility: sidebarColumnVisibilityBinding(paneIndex: 0),
                            onClearToolbarSearchFocus: clearToolbarSearchFocus,
                            onWorkspaceShortcutsChanged: onWorkspaceShortcutsChanged
                        )
                    }
                } else {
                    workspaceMultiPaneGrid()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 8) {
                        if model.currentLayout == .single, isSidebarCollapsed(paneIndex: 0) {
                            sidebarExpandToolbarButton(
                                visibility: sidebarColumnVisibilityBinding(paneIndex: 0)
                            )
                        }
                        if model.isFolderManagementPresented {
                            Button {
                                isToolbarSearchFocused = false
                                model.isFolderManagementPresented = false
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        Circle().fill(Color(nsColor: .quaternarySystemFill))
                                    )
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                            .help("Back to vault")
                            .accessibilityLabel("Back to vault")
                        } else if activeNote != nil {
                            Button {
                                clearToolbarSearchFocus()
                                model.closeToFolderPage()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        Circle().fill(Color(nsColor: .quaternarySystemFill))
                                    )
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                            .help("Back to folder")
                            .accessibilityLabel("Back to folder")
                        }
                    }
                }
                if model.currentLayout == .single {
                    ToolbarItem(placement: .principal) {
                        vaultToolbarSearchField(toolbarLayoutWidth: toolbarLayoutWidth)
                    }
                }
                if !Self.shouldHideTrailingToolbarControls(width: outerToolbarLayoutWidth) {
                    ToolbarItemGroup(placement: .primaryAction) {
                        LayoutToolbarItem(
                            model: model,
                            vaultSessionRegistry: vaultSessionRegistry,
                            onToolbarInteraction: clearToolbarSearchFocus
                        )
                        FolderManagementToolbarButton(model: model, onToolbarInteraction: clearToolbarSearchFocus)
                    }
                }
            }
        }
        .onPreferenceChange(DetailColumnWidthPreferenceKey.self) { measuredDetailColumnWidth = $0 }
    }

    @ViewBuilder
    private func workspaceMultiPaneGrid() -> some View {
        switch model.currentLayout {
        case .single:
            EmptyView()
        case .twoPane:
            HSplitView {
                workspaceTile(paneIndex: 0).frame(minWidth: 280)
                workspaceTile(paneIndex: 1).frame(minWidth: 200)
            }
        case .threePane:
            HSplitView {
                workspaceTile(paneIndex: 0).frame(minWidth: 280)
                VSplitView {
                    workspaceTile(paneIndex: 1).frame(minHeight: 120)
                    workspaceTile(paneIndex: 2).frame(minHeight: 120)
                }
                .frame(minWidth: 200)
            }
        case .fourPane:
            HSplitView {
                VSplitView {
                    workspaceTile(paneIndex: 0).frame(minHeight: 120)
                    workspaceTile(paneIndex: 1).frame(minHeight: 120)
                }
                .frame(minWidth: 240)
                VSplitView {
                    workspaceTile(paneIndex: 2).frame(minHeight: 120)
                    workspaceTile(paneIndex: 3).frame(minHeight: 120)
                }
                .frame(minWidth: 200)
            }
        }
    }

    private func workspaceTile(paneIndex: Int) -> some View {
        NavigationSplitView(columnVisibility: sidebarColumnVisibilityBinding(paneIndex: paneIndex)) {
            WorkspaceFolderSidebarView(
                model: model,
                paneIndex: paneIndex,
                sidebarColumnVisibility: sidebarColumnVisibilityBinding(paneIndex: paneIndex),
                onClearToolbarSearchFocus: clearToolbarSearchFocus
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack {
                WorkspaceDetailColumnView(
                    model: model,
                    paneIndex: paneIndex,
                    sidebarColumnVisibility: sidebarColumnVisibilityBinding(paneIndex: paneIndex),
                    onClearToolbarSearchFocus: clearToolbarSearchFocus,
                    multipaneSearchFocused: multipaneSearchFieldBinding(paneIndex: paneIndex),
                    onWorkspaceShortcutsChanged: onWorkspaceShortcutsChanged
                )
            }
        }
        .overlay {
            if model.currentLayout != .single, model.activePaneIndex == paneIndex {
                Rectangle()
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Prefer the measured detail column width (toolbar row); fall back to full window width before first layout.
    private static func effectiveToolbarLayoutWidth(detail: CGFloat, window: CGFloat) -> CGFloat {
        if detail.isFinite, detail > 1 { return detail }
        return window
    }

    /// Hide layout + folder-management toolbar items when the detail column is too narrow for the principal search
    /// field’s usual minimum width plus leading navigation and trailing controls, so AppKit does not move items
    /// into the overflow menu.
    private static func shouldHideTrailingToolbarControls(width: CGFloat) -> Bool {
        guard width.isFinite, width > 1 else { return true }
        return width < (toolbarSearchFieldMinWidth + toolbarChromeReserveForTrailingItems)
    }

    /// Space reserved for back/navigation column, trailing icon buttons, and unified-toolbar insets.
    private static let toolbarChromeReserveForTrailingItems: CGFloat = 300

    /// Reserved when sizing the principal search field so its width stays stable when the back button appears.
    private static let toolbarSearchLeadingChromeWhenBackVisible: CGFloat = 120

    private static let toolbarSearchFieldMinWidth: CGFloat = 400
    private static let toolbarSearchFieldIdealWidth: CGFloat = 500
    private static let toolbarSearchFieldMaxWidth: CGFloat = 600

    private static func toolbarSearchFieldFrameWidths(toolbarLayoutWidth: CGFloat) -> (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        // Always reserve the wider leading chrome so the search pill does not resize when back navigation appears.
        let budget = max(96, toolbarLayoutWidth - toolbarSearchLeadingChromeWhenBackVisible)
        let rawMin = min(toolbarSearchFieldMinWidth, budget)
        let minW = max(200, rawMin)
        let idealW = min(toolbarSearchFieldIdealWidth, max(minW, budget))
        let maxW = min(toolbarSearchFieldMaxWidth, max(idealW, budget))
        return (minW, idealW, maxW)
    }

    @ViewBuilder
    private func vaultToolbarSearchField(toolbarLayoutWidth: CGFloat) -> some View {
        let showsSearchRing = isToolbarSearchFocused && controlActiveState == .active
        let frames = Self.toolbarSearchFieldFrameWidths(toolbarLayoutWidth: toolbarLayoutWidth)
        ToolbarSearchField(
            text: workspaceSearchBinding,
            isFocused: $isToolbarSearchFocused,
            placeholder: workspaceSearchPlaceholderText
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minWidth: frames.min, idealWidth: frames.ideal, maxWidth: frames.max, minHeight: 28)
        .overlay {
            if showsSearchRing {
                Capsule().strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
            }
        }
        .accessibilityLabel(workspaceSearchAccessibilityLabel)
        .accessibilityHint(workspaceSearchAccessibilityHint)
    }

    private var workspaceSearchBinding: Binding<String> {
        Binding(
            get: {
                if model.isFolderManagementPresented {
                    return model.vaultSearchQuery
                }
                return model.selectedNoteID != nil ? model.editorFindQuery : model.vaultSearchQuery
            },
            set: { newValue in
                if model.isFolderManagementPresented {
                    model.vaultSearchQuery = newValue
                } else if model.selectedNoteID != nil {
                    model.editorFindQuery = newValue
                } else {
                    model.vaultSearchQuery = newValue
                }
            }
        )
    }

    private var workspaceSearchPlaceholderText: String {
        if model.isFolderManagementPresented {
            return String(localized: "Search vault…")
        }
        return model.selectedNoteID != nil
            ? String(localized: "Find in note…")
            : String(localized: "Search vault…")
    }

    private var workspaceSearchAccessibilityLabel: String {
        workspaceSearchPlaceholderText
    }

    private var workspaceSearchAccessibilityHint: String {
        if model.selectedNoteID != nil, !model.isFolderManagementPresented {
            return String(localized: "Searches text in the open note.")
        }
        return String(localized: "Searches note titles in the vault.")
    }

}

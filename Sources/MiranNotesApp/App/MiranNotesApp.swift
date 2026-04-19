import AppKit
import KeyboardShortcuts
import MiranNotesCore
import SwiftUI

private final class MiranNotesAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        WorkspaceShortcutCarbonPolicy.suppressGlobalHotkeysForMenuShortcuts()
    }
}

@main
struct MiranNotesApp: App {
    @NSApplicationDelegateAdaptor(MiranNotesAppDelegate.self) private var appDelegate
    @State private var vaultAccess: VaultWorkspaceAccess?
    @State private var model: AppModel?
    @State private var sessionRegistry = VaultSessionRegistry()
    @State private var conflictDetailsPresented = false
    @State private var conflictDetailsDiskDate: Date?
    @State private var editingHelpPresented = false
    @State private var vaultPickerErrorMessage: String?
    /// Picker chose a folder that failed the compatibility gate; full report (same UI as runtime gate).
    @State private var incompatiblePick: (report: CompatibilityReport, vaultURL: URL)?
    /// Forces ``appCommands`` to re-read shortcuts from `KeyboardShortcuts` / UserDefaults.
    @State private var menuShortcutEpoch = 0

    init() {
        SlashCommandRegistry.registerBuiltins()
        if ProcessInfo.processInfo.environment["MIRAN_USE_DEFAULT_VAULT"] == "1" {
            let devVault = Self.defaultVaultDirectoryURL()
            try? FileManager.default.createDirectory(at: devVault, withIntermediateDirectories: true)
        }
        let outcome = VaultWorkspaceAccess.bootstrap(defaultVaultURL: Self.bootstrapDefaultVaultURL())
        switch outcome {
        case .resolved(let access):
            _vaultAccess = State(initialValue: access)
            _model = State(initialValue: AppModel(repository: NoteRepository(vaultURL: access.vaultRootURL)))
        case .needsUserSelectedVault:
            _vaultAccess = State(initialValue: nil)
            _model = State(initialValue: nil)
        }

        Self.seedWorkspaceShortcutDefaultsAndUseMenuOnlyHotkeys()
    }

    /// Ensures `KeyboardShortcuts` UserDefaults entries exist and disables Carbon hotkeys so File menu shortcuts still fire.
    private static func seedWorkspaceShortcutDefaultsAndUseMenuOnlyHotkeys() {
        for command in WorkspaceShortcutCommand.allCases {
            _ = command.keyboardShortcutName
        }
        WorkspaceShortcutCarbonPolicy.suppressGlobalHotkeysForMenuShortcuts()
    }

    /// When `MIRAN_USE_DEFAULT_VAULT=1` is set, restores the legacy `~/MiranNotesVault` bootstrap for local iteration without picking a folder.
    private static func bootstrapDefaultVaultURL() -> URL? {
        if ProcessInfo.processInfo.environment["MIRAN_USE_DEFAULT_VAULT"] == "1" {
            return defaultVaultDirectoryURL()
        }
        return nil
    }

    private static func defaultVaultDirectoryURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("MiranNotesVault", isDirectory: true)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if let model {
                        MiranNotesMainWindowContent(
                            model: model,
                            presentOpenWorkspacePanel: presentOpenWorkspacePanel,
                            conflictDetailsPresented: $conflictDetailsPresented,
                            conflictDetailsDiskDate: $conflictDetailsDiskDate,
                            editingHelpPresented: $editingHelpPresented,
                            onWorkspaceShortcutsChanged: {
                                menuShortcutEpoch &+= 1
                                WorkspaceShortcutCarbonPolicy.suppressGlobalHotkeysForMenuShortcuts()
                            }
                        )
                    } else {
                        VaultWelcomeView(onOpenVault: presentOpenWorkspacePanel)
                            .alert(
                                "Error",
                                isPresented: Binding(
                                    get: { vaultPickerErrorMessage != nil },
                                    set: { if !$0 { vaultPickerErrorMessage = nil } }
                                )
                            ) {
                                Button("OK", role: .cancel) {
                                    vaultPickerErrorMessage = nil
                                }
                            } message: {
                                Text(vaultPickerErrorMessage ?? "")
                            }
                    }
                }
                if let pick = incompatiblePick {
                    WorkspaceIncompatibleView(
                        report: pick.report,
                        vaultRootURL: pick.vaultURL,
                        onChooseDifferentFolder: {
                            incompatiblePick = nil
                            presentOpenWorkspacePanel()
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
            .environment(sessionRegistry)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { appCommands }

        Settings {
            MiranNotesSettingsView()
        }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        let _ = menuShortcutEpoch
        CommandGroup(after: .newItem) {
            Button("Open Workspace…") {
                presentOpenWorkspacePanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("New Folder") {
                model?.performNewFolderFromShortcut()
            }
            .workspaceMenuKeyboardShortcut(.newFolder)
            Button("New Note") {
                model?.performNewNoteFromShortcut()
            }
            .workspaceMenuKeyboardShortcut(.newNote)
        }
        CommandGroup(after: .help) {
            Button("Editing in Miran Notes…") {
                editingHelpPresented = true
            }
        }
        CommandMenu("Format") {
            Button("Bold") {
                NSApp.sendAction(Selector(("toggleBold:")), to: nil, from: nil)
            }
            .keyboardShortcut("b", modifiers: .command)
            Button("Italic") {
                NSApp.sendAction(Selector(("toggleItalic:")), to: nil, from: nil)
            }
            .keyboardShortcut("i", modifiers: .command)
            Button("Code") {
                NSApp.sendAction(Selector(("toggleCodeSpan:")), to: nil, from: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }

    private func presentOpenWorkspacePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            panel.directoryURL = desktop
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let newAccess = try VaultWorkspaceAccess.adoptUserSelectedVaultRoot(url)
            incompatiblePick = nil
            vaultAccess = newAccess
            model = AppModel(repository: NoteRepository(vaultURL: newAccess.vaultRootURL))
            model?.loadVault()
        } catch let adoption as VaultWorkspaceAdoptionError {
            switch adoption {
            case .incompatibleVault(let report):
                incompatiblePick = (report, url.standardizedFileURL)
            }
        } catch {
            let message =
                "Could not remember access to the folder you chose. Try again or check disk permissions."
            if let model {
                model.userAlert = .message("\(message) \(error.localizedDescription)")
            } else {
                vaultPickerErrorMessage = "\(message) \(error.localizedDescription)"
            }
        }
    }

}

// MARK: - Main window (vault open)

private struct DetailColumnWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum WorkspaceSidebarColumnVisibilityStore {
    static func userDefaultsKey(paneIndex: Int) -> String {
        "workspace.sidebarCollapsedPane\(paneIndex)"
    }
}

private struct WorkspaceSidebarExpandToolbarButton: View {
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

private struct MiranNotesMainWindowContent: View {
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

// MARK: - Workspace detail (folder list vs note editor)

/// Matches `NSTextView` / markdown preview document surface so the detail column reads as one paper sheet.
private enum WorkspaceDocumentSurface {
    static var background: Color { Color(nsColor: .textBackgroundColor) }
}

private struct WorkspaceDetailColumnView: View {
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

private struct FolderFirstNoteBodyFormatSheet: View {
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
            noteEditorSurface(fallbackDocument: current)
                .id(
                    "\(model.effectiveEditorActivationProfile(forPane: paneIndex).editorKind.rawValue)-\(model.workspacePanes[paneIndex].selectedNoteID?.uuidString ?? "none")"
                )
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
                model.activatePane(index: p)
                model.openNote(noteID: targetID, pane: p)
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

struct RepairAdvisoryDetailsSheet: View {
    let detailsText: String
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: detailsText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(minWidth: 360, minHeight: 220)
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

struct RepairNoticeBanner: View {
    let advisory: RepairAdvisory
    let onDismiss: () -> Void
    let onShowInFinder: () -> Void
    let onDetails: () -> Void
    let showDetailsButton: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(advisory.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(advisory.explanation)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Got it", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            HStack(spacing: 12) {
                Button("Show in Finder", action: onShowInFinder)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showDetailsButton {
                    Button("Details", action: onDetails)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}

struct DiskActivityBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "externaldrive")
                .foregroundStyle(.blue)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
    }
}

private struct ExternalEditCompareSheet: View {
    let payload: ExternalTextComparePayload
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your edits (editor)")
                        .font(.headline)
                    ScrollView {
                        Text(payload.localText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 200)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved file (disk)")
                        .font(.headline)
                    ScrollView {
                        Text(payload.diskText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 200)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .frame(minWidth: 520, minHeight: 320)
            .navigationTitle("Compare text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

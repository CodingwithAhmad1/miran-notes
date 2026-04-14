import AppKit
import MiranNotesCore
import SwiftUI

private final class MiranNotesAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
            Group {
                if let model {
                    MiranNotesMainWindowContent(
                        model: model,
                        presentOpenWorkspacePanel: presentOpenWorkspacePanel,
                        conflictDetailsPresented: $conflictDetailsPresented,
                        conflictDetailsDiskDate: $conflictDetailsDiskDate,
                        editingHelpPresented: $editingHelpPresented
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
            .environment(sessionRegistry)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { appCommands }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Workspace…") {
                presentOpenWorkspacePanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
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
            vaultAccess = newAccess
            model = AppModel(repository: NoteRepository(vaultURL: newAccess.vaultRootURL))
            model?.loadVault()
        } catch let adoption as VaultWorkspaceAdoptionError {
            if let model {
                model.userAlert = .message(adoption.localizedDescription ?? "This folder cannot be used as a vault.")
            } else {
                vaultPickerErrorMessage = adoption.localizedDescription ?? "This folder cannot be used as a vault."
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

private struct MiranNotesMainWindowContent: View {
    @Bindable var model: AppModel
    @Environment(VaultSessionRegistry.self) private var vaultSessionRegistry
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.scenePhase) private var scenePhase
    var presentOpenWorkspacePanel: () -> Void
    @Binding var conflictDetailsPresented: Bool
    @Binding var conflictDetailsDiskDate: Date?
    @Binding var editingHelpPresented: Bool
    @FocusState private var isToolbarSearchFocused: Bool

    private func clearToolbarSearchFocus() {
        isToolbarSearchFocused = false
    }

    var body: some View {
        workspaceRootView
            .onChange(of: controlActiveState) { _, newValue in
                if newValue == .inactive {
                    isToolbarSearchFocused = false
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    isToolbarSearchFocused = false
                }
            }
            .onAppear {
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
                WorkspaceIncompatibleView(report: report, onChooseDifferentFolder: presentOpenWorkspacePanel)
            case .ready:
                NavigationSplitView {
                    WorkspaceFolderSidebarView(model: model, onClearToolbarSearchFocus: clearToolbarSearchFocus)
                        .toolbar(removing: .sidebarToggle)
                } detail: {
                    WorkspaceDetailColumnView(model: model, onClearToolbarSearchFocus: clearToolbarSearchFocus)
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        HStack(spacing: 8) {
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
                            } else if model.selectedNoteID != nil {
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
                    ToolbarItem(placement: .principal) {
                        HStack {
                            Spacer(minLength: 0)
                            vaultToolbarSearchField
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
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
    }

    private static let toolbarSearchFieldMinWidth: CGFloat = 400
    private static let toolbarSearchFieldIdealWidth: CGFloat = 500
    private static let toolbarSearchFieldMaxWidth: CGFloat = 600

    @ViewBuilder
    private var vaultToolbarSearchField: some View {
        let showsSearchRing = isToolbarSearchFocused && controlActiveState == .active
        let outlineOpacity = showsSearchRing ? 0.42 : 0.18
        TextField("", text: workspaceSearchBinding, prompt: workspaceSearchPrompt)
            .textFieldStyle(.plain)
            .focused($isToolbarSearchFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(nsColor: .quaternarySystemFill)))
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(outlineOpacity), lineWidth: 1)
            )
            .focusEffectDisabled()
            .frame(
                minWidth: Self.toolbarSearchFieldMinWidth,
                idealWidth: Self.toolbarSearchFieldIdealWidth,
                maxWidth: Self.toolbarSearchFieldMaxWidth
            )
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

    private var workspaceSearchPrompt: Text {
        if model.isFolderManagementPresented {
            return Text("Search vault…")
        }
        return model.selectedNoteID != nil ? Text("Find in note…") : Text("Search vault…")
    }

}

// MARK: - Workspace detail (folder list vs note editor)

private struct WorkspaceDetailColumnView: View {
    @Bindable var model: AppModel
    var onClearToolbarSearchFocus: () -> Void

    private var showsLoadedEditor: Bool {
        guard let doc = model.activeDocument, let id = model.selectedNoteID else { return false }
        return doc.metadata.noteID == id
    }

    var body: some View {
        Group {
            if model.isFolderManagementPresented {
                FolderManagementDashboardView(model: model)
            } else if showsLoadedEditor {
                TiledEditorView(model: model)
            } else if model.selectedNoteID != nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading note…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FolderPageView(model: model)
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                onClearToolbarSearchFocus()
            }
        )
    }
}


struct EditorRootView: View {
    @Bindable var model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var repairDetailsPresented = false
    @State private var editorBodyFocusNonce = 0

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
                            onDetails: {
                                repairDetailsPresented = true
                            },
                            showDetailsButton: advisory.detailsPlainText != nil
                        )
                        .sheet(isPresented: $repairDetailsPresented) {
                            RepairAdvisoryDetailsSheet(
                                detailsText: advisory.detailsPlainText ?? "",
                                onDone: { repairDetailsPresented = false }
                            )
                        }
                    }
                    NoteEditorTitleHeader(model: model) {
                        editorBodyFocusNonce += 1
                    }
                    SingleSurfaceNoteEditor(
                        document: Binding(
                            get: { model.activeDocument ?? current },
                            set: { model.activeDocument = $0 }
                        ),
                        cursorOffset: $model.editorCursorOffset,
                        editorTextSelection: $model.editorTextSelection,
                        editorFindQuery: $model.editorFindQuery,
                        pendingEditorScroll: model.pendingEditorScroll,
                        onPendingEditorScrollConsumed: { model.clearPendingEditorScroll() },
                        onCommands: { commands in model.apply(commands) },
                        onWikiLinkClick: WikiLinkPresentationPolicy.isFrontendEnabled
                            ? { targetID in model.openNote(noteID: targetID) }
                            : nil,
                        onFullReplaceWarning: {
                            model.presentFullBufferAdvisory()
                        },
                        onSizeLimitExceeded: {
                            model.presentSizeLimitAdvisory()
                        },
                        focusBodyNonce: editorBodyFocusNonce
                    )
                }
                .navigationTitle("")
            }
        }
        .onAppear {
            model.setUndoManager(undoManager)
        }
        .onChange(of: undoManager) { _, newValue in
            model.setUndoManager(newValue)
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

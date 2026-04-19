import AppKit
import SwiftUI

struct FolderManagementToolbarButton: View {
    var model: AppModel?
    var onToolbarInteraction: () -> Void = {}

    private var isEnabled: Bool {
        guard let model else { return false }
        if case .ready = model.workspaceGateState { return true }
        return false
    }

    var body: some View {
        Button {
            onToolbarInteraction()
            model?.isFolderManagementPresented = true
        } label: {
            Image(systemName: "gearshape")
        }
        .help("Folder Management…")
        .disabled(!isEnabled || model?.isFolderManagementPresented == true)
    }
}

struct FolderManagementDashboardView: View {
    @Bindable var model: AppModel
    /// Bump menu shortcut epoch when shortcuts change (same as Settings).
    var onWorkspaceShortcutsChanged: () -> Void = {}

    @State private var activeActionsFolderID: UUID?
    @State private var folderPendingHide: UUID?
    @State private var folderPendingUnhide: UUID?
    @State private var folderPendingDelete: UUID?
    @State private var inlineNotice: String?
    @State private var noticeDismissTask: Task<Void, Never>?

    private var confirmHideBinding: Binding<Bool> {
        Binding(
            get: { folderPendingHide != nil },
            set: { if !$0 { folderPendingHide = nil } }
        )
    }

    private var confirmUnhideBinding: Binding<Bool> {
        Binding(
            get: { folderPendingUnhide != nil },
            set: { if !$0 { folderPendingUnhide = nil } }
        )
    }

    private var confirmDeleteBinding: Binding<Bool> {
        Binding(
            get: { folderPendingDelete != nil },
            set: { if !$0 { folderPendingDelete = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let inlineNotice {
                Text(inlineNotice)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.quaternary.opacity(0.35))
            }

            List {
                Section("Folders") {
                    if model.visibleTopLevelFolderEntries.isEmpty {
                        Text("No visible folders.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.visibleTopLevelFolderEntries, id: \.id) { folder in
                        folderRow(folder, isHiddenRow: false)
                    }
                }

                if !model.hiddenTopLevelFolderEntries.isEmpty {
                    Section {
                        DisclosureGroup("Hidden") {
                            ForEach(model.hiddenTopLevelFolderEntries, id: \.id) { folder in
                                folderRow(folder, isHiddenRow: true)
                            }
                        }
                    }
                }

                WorkspaceKeyboardShortcutsSettingsSections(
                    sectionHeader: Text(
                        "Keyboard shortcuts",
                        comment: "Folder management: section below folders for New Folder / New Note shortcuts"
                    ),
                    onWorkspaceShortcutsChanged: onWorkspaceShortcutsChanged
                )
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .confirmationDialog(
                "Hide folders from sidebar?",
                isPresented: confirmHideBinding,
                titleVisibility: .visible
            ) {
                Button("Hide") {
                    if let id = folderPendingHide {
                        model.hideTopLevelFolders(ids: [id])
                        if activeActionsFolderID == id { activeActionsFolderID = nil }
                        scheduleNotice("Hid 1 folder.")
                    }
                    folderPendingHide = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Notes stay on disk. Unhide from the Hidden section anytime.")
            }
            .confirmationDialog(
                "Unhide folders?",
                isPresented: confirmUnhideBinding,
                titleVisibility: .visible
            ) {
                Button("Unhide") {
                    if let id = folderPendingUnhide {
                        model.unhideTopLevelFolders(ids: [id])
                        if activeActionsFolderID == id { activeActionsFolderID = nil }
                        scheduleNotice("Restored 1 folder to the sidebar.")
                    }
                    folderPendingUnhide = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Selected folders will appear in the sidebar again.")
            }
            .confirmationDialog(
                "Delete selected folders?",
                isPresented: confirmDeleteBinding,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = folderPendingDelete {
                        model.deleteTopLevelFolders(ids: [id]) { count in
                            if activeActionsFolderID == id { activeActionsFolderID = nil }
                            scheduleNotice(
                                count == 1 ? "Deleted 1 folder." : "Deleted \(count) folders."
                            )
                        }
                    }
                    folderPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This permanently removes each selected folder and everything inside it (notes, metadata, and subfolders). This cannot be undone."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            noticeDismissTask?.cancel()
            noticeDismissTask = nil
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: FolderEntry, isHiddenRow: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .imageScale(.medium)
                .frame(width: Self.folderGlyphColumnWidth, alignment: .center)
            Text(folder.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.trailing, Self.fiveAverageBodyCharacterWidthTightening)
                .frame(maxWidth: .infinity, alignment: .leading)
            folderRowTrailingActions(folder: folder, isHiddenRow: isHiddenRow)
                .frame(width: Self.trailingActionsSlotWidth, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            activeActionsFolderID = activeActionsFolderID == folder.id ? nil : folder.id
        }
    }

    @ViewBuilder
    private func folderRowTrailingActions(folder: FolderEntry, isHiddenRow: Bool) -> some View {
        let expanded = activeActionsFolderID == folder.id
        HStack(spacing: 8) {
            if expanded {
                Button {
                    folderPendingHide = nil
                    folderPendingUnhide = nil
                    folderPendingDelete = nil
                    if isHiddenRow {
                        folderPendingUnhide = folder.id
                    } else {
                        folderPendingHide = folder.id
                    }
                } label: {
                    Image(systemName: isHiddenRow ? "eye.slash" : "eye")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help(isHiddenRow ? "Unhide folder in sidebar" : "Hide folder from sidebar")
                .accessibilityLabel(isHiddenRow ? "Unhide folder" : "Hide folder from sidebar")

                Button {
                    folderPendingHide = nil
                    folderPendingUnhide = nil
                    folderPendingDelete = nil
                    folderPendingDelete = folder.id
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help("Delete folder")
                .accessibilityLabel("Delete folder")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func scheduleNotice(_ text: String) {
        noticeDismissTask?.cancel()
        inlineNotice = text
        noticeDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            inlineNotice = nil
            noticeDismissTask = nil
        }
    }

    /// Reserves space for two borderless icon buttons plus spacing so the row does not jump when actions appear.
    private static let trailingActionsSlotWidth: CGFloat = 64

    private static let folderGlyphColumnWidth: CGFloat = 22

    /// Five times the average advance width of system body digits — tightens the label so names truncate slightly earlier than the icon column alone would imply.
    private static let fiveAverageBodyCharacterWidthTightening: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let probe = "0123456789" as NSString
        let perChar = probe.size(withAttributes: [.font: font]).width / 10
        return perChar * 5
    }()
}

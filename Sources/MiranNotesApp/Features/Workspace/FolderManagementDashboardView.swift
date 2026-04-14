import SwiftUI

struct FolderManagementToolbarButton: View {
    var model: AppModel?

    private var isEnabled: Bool {
        guard let model else { return false }
        if case .ready = model.workspaceGateState { return true }
        return false
    }

    var body: some View {
        Button {
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

    @State private var selection: Set<UUID> = []
    @State private var confirmHide = false
    @State private var confirmDelete = false
    @State private var confirmUnhide = false
    @State private var inlineNotice: String?
    @State private var noticeDismissTask: Task<Void, Never>?

    private var selectedVisibleIDs: Set<UUID> {
        selection.intersection(Set(model.visibleTopLevelFolderEntries.map(\.id)))
    }

    private var selectedHiddenIDs: Set<UUID> {
        selection.intersection(Set(model.hiddenTopLevelFolderEntries.map(\.id)))
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
                        folderRow(folder)
                    }
                }

                if !model.hiddenTopLevelFolderEntries.isEmpty {
                    Section {
                        DisclosureGroup("Hidden") {
                            ForEach(model.hiddenTopLevelFolderEntries, id: \.id) { folder in
                                folderRow(folder)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !selection.isEmpty {
                    HStack(spacing: 16) {
                        if !selectedHiddenIDs.isEmpty {
                            Button("Unhide") {
                                confirmUnhide = true
                            }
                        }
                        if !selectedVisibleIDs.isEmpty {
                            Button("Hide") {
                                confirmHide = true
                            }
                        }
                        Spacer(minLength: 0)
                        Button("Delete", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
            }
            .confirmationDialog(
                "Hide folders from sidebar?",
                isPresented: $confirmHide,
                titleVisibility: .visible
            ) {
                Button("Hide") {
                    let ids = selectedVisibleIDs
                    let n = ids.count
                    model.hideTopLevelFolders(ids: ids)
                    selection.subtract(ids)
                    scheduleNotice(n == 1 ? "Hid 1 folder." : "Hid \(n) folders.")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Notes stay on disk. Unhide from the Hidden section anytime.")
            }
            .confirmationDialog(
                "Unhide folders?",
                isPresented: $confirmUnhide,
                titleVisibility: .visible
            ) {
                Button("Unhide") {
                    let ids = selectedHiddenIDs
                    let n = ids.count
                    model.unhideTopLevelFolders(ids: ids)
                    selection.subtract(ids)
                    scheduleNotice(n == 1 ? "Restored 1 folder to the sidebar." : "Restored \(n) folders to the sidebar.")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Selected folders will appear in the sidebar again.")
            }
            .confirmationDialog(
                "Delete selected folders?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    let ids = selection
                    model.deleteTopLevelFolders(ids: ids) { count in
                        selection.removeAll()
                        scheduleNotice(
                            count == 1 ? "Deleted 1 folder." : "Deleted \(count) folders."
                        )
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This permanently removes each empty folder from the workspace (no notes and no subfolders). Folders that still contain items cannot be deleted."
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
    private func folderRow(_ folder: FolderEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .imageScale(.medium)
            Text(folder.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button {
                if selection.contains(folder.id) {
                    selection.remove(folder.id)
                } else {
                    selection.insert(folder.id)
                }
            } label: {
                Image(systemName: selection.contains(folder.id) ? "checkmark.square.fill" : "square")
                    .imageScale(.medium)
                    .foregroundStyle(selection.contains(folder.id) ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(selection.contains(folder.id) ? "Deselect folder" : "Select folder")
        }
        .padding(.vertical, 2)
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
}

import SwiftUI

struct FolderPageView: View {
    @Bindable var model: AppModel
    @State private var folderTitleDraft = ""
    @State private var isCommittingFolderRename = false
    @FocusState private var isFolderTitleFocused: Bool

    var body: some View {
        Group {
            if model.selectedFolderID == nil {
                if !model.hasDismissedVaultWelcome {
                    VaultOpenedWelcomeView(vaultPath: model.repository.vaultURL.path)
                } else {
                    ContentUnavailableView(
                        "No folder selected",
                        systemImage: "folder",
                        description: Text("Add a folder from the sidebar, or choose notes in the vault root.")
                    )
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        folderPageHeader
                            .padding(.bottom, 4)

                        ForEach(model.folderPageNoteSummaries) { summary in
                            NoteLinkRow(
                                title: summary.title,
                                onTap: { model.openNote(noteID: summary.noteID) },
                                onDelete: {
                                    model.deleteNoteFromFolder(noteID: summary.noteID)
                                }
                            )
                        }

                        if model.folderPageNoteSummaries.isEmpty {
                            Text("No notes in this folder yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .onAppear {
                    folderTitleDraft = model.selectedFolderDisplayTitle
                }
                .onChange(of: model.selectedFolderID) { _, _ in
                    folderTitleDraft = model.selectedFolderDisplayTitle
                }
                .onChange(of: model.selectedFolderDisplayTitle) { _, _ in
                    if !isFolderTitleFocused {
                        folderTitleDraft = model.selectedFolderDisplayTitle
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var folderPageHeader: some View {
        if selectedFolderIsRenamable {
            TextField("Folder name", text: $folderTitleDraft)
                .font(.largeTitle)
                .fontWeight(.bold)
                .textFieldStyle(.plain)
                .focused($isFolderTitleFocused)
                .onSubmit { commitFolderTitleRename() }
                .onChange(of: isFolderTitleFocused) { _, focused in
                    if !focused {
                        commitFolderTitleRename()
                    }
                }
        } else {
            Text(model.selectedFolderDisplayTitle)
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }

    private var selectedFolderIsRenamable: Bool {
        guard let id = model.selectedFolderID else { return false }
        return id != FolderCatalog.rootFolderID
    }

    private func commitFolderTitleRename() {
        guard let id = model.selectedFolderID, id != FolderCatalog.rootFolderID else { return }
        let trimmed = folderTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            folderTitleDraft = model.selectedFolderDisplayTitle
            return
        }
        let current = model.selectedFolderDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == current { return }

        guard !isCommittingFolderRename else { return }
        isCommittingFolderRename = true
        let capturedID = id
        Task { @MainActor in
            defer { isCommittingFolderRename = false }
            _ = await model.renameFolderAndWait(id: capturedID, newName: trimmed)
            guard model.selectedFolderID == capturedID else { return }
            folderTitleDraft = model.selectedFolderDisplayTitle
        }
    }

}

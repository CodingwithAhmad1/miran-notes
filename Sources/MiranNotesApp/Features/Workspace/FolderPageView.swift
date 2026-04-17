import SwiftUI

struct FolderPageView: View {
    @Bindable var model: AppModel
    var paneIndex: Int = 0
    @State private var folderTitleDraft = ""
    @State private var isCommittingFolderRename = false
    @FocusState private var isFolderTitleFocused: Bool

    private var vaultSearchActive: Bool {
        !model.workspacePanes[paneIndex].vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if vaultSearchActive {
                vaultSearchResultsPane
            } else if model.workspacePanes[paneIndex].selectedFolderID == nil {
                if !model.hasDismissedVaultWelcome {
                    VaultOpenedWelcomeView(vaultPath: model.repository.vaultURL.path)
                } else {
                    ContentUnavailableView(
                        "No folder selected",
                        systemImage: "folder",
                        description: Text("Add a folder from the sidebar, or choose notes in the vault root.")
                    )
                }
            } else if model.showsTodaysTasksVaultRootPage(forPane: paneIndex) {
                TodaysTasksVaultPageView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        folderPageHeader
                            .padding(.bottom, 4)

                        ForEach(model.folderPageNoteSummaries(forPane: paneIndex)) { summary in
                            NoteLinkRow(
                                title: summary.title,
                                pathTooltip: summary.relativePath,
                                onTap: {
                                    model.activatePane(index: paneIndex)
                                    model.openNote(noteID: summary.noteID, pane: paneIndex)
                                },
                                onDelete: {
                                    model.deleteNoteFromFolder(noteID: summary.noteID)
                                }
                            )
                        }

                        if model.folderPageNoteSummaries(forPane: paneIndex).isEmpty {
                            Text("No notes in this folder yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .onAppear {
                    folderTitleDraft = model.selectedFolderDisplayTitle(forPane: paneIndex)
                }
                .onChange(of: model.workspacePanes[paneIndex].selectedFolderID) { _, _ in
                    folderTitleDraft = model.selectedFolderDisplayTitle(forPane: paneIndex)
                }
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                model.activatePane(index: paneIndex)
            }
        )
    }

    private var vaultSearchResultsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Search results")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 4)

                let matches = model.vaultSearchMatchingNoteSummaries(forPane: paneIndex)
                ForEach(matches) { summary in
                    NoteLinkRow(
                        title: summary.title,
                        pathTooltip: summary.relativePath,
                        onTap: {
                            model.activatePane(index: paneIndex)
                            model.openNote(noteID: summary.noteID, pane: paneIndex)
                        },
                        onDelete: {
                            model.deleteNoteFromFolder(noteID: summary.noteID)
                        }
                    )
                }

                if matches.isEmpty {
                    Text("No matching notes.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
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
                .onSubmit {
                    // Enter should commit rename by ending editing, not keep selected text highlighted.
                    isFolderTitleFocused = false
                }
                .onChange(of: isFolderTitleFocused) { _, focused in
                    if !focused {
                        commitFolderTitleRename()
                    }
                }
        } else {
            Text(model.selectedFolderDisplayTitle(forPane: paneIndex))
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }

    private var selectedFolderIsRenamable: Bool {
        guard let id = model.workspacePanes[paneIndex].selectedFolderID else { return false }
        return id != FolderCatalog.rootFolderID
    }

    private func commitFolderTitleRename() {
        guard let id = model.workspacePanes[paneIndex].selectedFolderID, id != FolderCatalog.rootFolderID else { return }
        let trimmed = folderTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            folderTitleDraft = model.selectedFolderDisplayTitle(forPane: paneIndex)
            return
        }
        let current = model.selectedFolderDisplayTitle(forPane: paneIndex).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == current { return }

        guard !isCommittingFolderRename else { return }
        isCommittingFolderRename = true
        let capturedID = id
        Task { @MainActor in
            defer { isCommittingFolderRename = false }
            _ = await model.renameFolderAndWait(id: capturedID, newName: trimmed)
            guard model.workspacePanes[paneIndex].selectedFolderID == capturedID else { return }
            folderTitleDraft = model.selectedFolderDisplayTitle(forPane: paneIndex)
        }
    }

}

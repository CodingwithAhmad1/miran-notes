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
                TodaysTasksVaultPageView(model: model)
            } else {
                folderPageForSelectedFolder
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                model.activatePane(index: paneIndex)
            }
        )
    }

    @ViewBuilder
    private var folderPageForSelectedFolder: some View {
        if let folderID = model.workspacePanes[paneIndex].selectedFolderID {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    folderPageHeader
                        .padding(.bottom, 4)

                    if folderID == FolderCatalog.rootFolderID {
                        repositoryNoteListContent
                    } else if model.folderRole(for: folderID) == nil {
                        folderRolePickerContent(folderID: folderID)
                    } else if model.folderRole(for: folderID) == .dashboard {
                        dashboardFolderListContent(parentFolderID: folderID)
                    } else {
                        repositoryNoteListContent
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

    @ViewBuilder
    private var repositoryNoteListContent: some View {
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

    @ViewBuilder
    private func folderRolePickerContent(folderID: UUID) -> some View {
        Text("Choose how this folder works. This cannot be changed later.")
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 12) {
            Button {
                model.activatePane(index: paneIndex)
                model.setFolderRole(.dashboard, folderID: folderID)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dashboard")
                        .font(.headline)
                    Text("Add nested folders only. Open this folder to browse links to other folders.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .buttonStyle(.bordered)

            Button {
                model.activatePane(index: paneIndex)
                model.setFolderRole(.repository, folderID: folderID)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repository")
                        .font(.headline)
                    Text("Hold notes here—the usual folder page with note links.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func dashboardFolderListContent(parentFolderID: UUID) -> some View {
        let children = model.folderCatalog.childFolders(of: parentFolderID).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        ForEach(children, id: \.id) { folder in
            NoteLinkRow(
                title: folder.name,
                pathTooltip: model.folderCatalog.relativeDirectoryPath(for: folder.id),
                onTap: {
                    model.activatePane(index: paneIndex)
                    model.selectFolderForPage(folder.id, pane: paneIndex)
                }
            )
        }

        if children.isEmpty {
            Text("No nested folders yet.")
                .foregroundStyle(.secondary)
        }

        Button {
            model.activatePane(index: paneIndex)
            model.createFolder(parentID: parentFolderID, pane: paneIndex)
        } label: {
            Label("New subfolder", systemImage: "folder.badge.plus")
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 8)
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

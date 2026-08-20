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
            let needsRolePicker = folderID != FolderCatalog.rootFolderID && model.folderRole(for: folderID) == nil
            let usesIconBrowser = !needsRolePicker && model.folderPageViewMode(folderID: folderID) == .icons

            Group {
                if usesIconBrowser {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            folderBreadcrumb(folderID: folderID)
                            HStack(alignment: .firstTextBaseline) {
                                folderPageHeader
                                Spacer()
                                viewModeToggle(folderID: folderID)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                        FolderIconBrowserView(
                            model: model,
                            paneIndex: paneIndex,
                            folderID: folderID,
                            items: browserItems(folderID: folderID)
                        )
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                folderBreadcrumb(folderID: folderID)
                                HStack(alignment: .firstTextBaseline) {
                                    folderPageHeader
                                    Spacer()
                                    if !needsRolePicker {
                                        viewModeToggle(folderID: folderID)
                                    }
                                }
                            }
                            .padding(.bottom, 4)

                            if folderID == FolderCatalog.rootFolderID {
                                repositoryNoteListContent
                            } else if needsRolePicker {
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
                }
            }
            .onAppear {
                folderTitleDraft = model.selectedFolderDisplayTitle(forPane: paneIndex)
            }
            .onChange(of: model.workspacePanes[paneIndex].selectedFolderID) { _, _ in
                folderTitleDraft = model.selectedFolderDisplayTitle(forPane: paneIndex)
            }
        }
    }

    /// Items on the icon canvas: child folders for dashboards, notes for repositories / the root tray.
    private func browserItems(folderID: UUID) -> [FolderBrowserItem] {
        if folderID != FolderCatalog.rootFolderID, model.folderRole(for: folderID) == .dashboard {
            return model.folderCatalog.childFolders(of: folderID)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { .folder($0) }
        }
        return model.folderPageNoteSummaries(forPane: paneIndex).map { .note($0) }
    }

    @ViewBuilder
    private func viewModeToggle(folderID: UUID) -> some View {
        Picker("View mode", selection: Binding(
            get: { model.folderPageViewMode(folderID: folderID) },
            set: { model.setFolderPageViewMode($0, folderID: folderID) }
        )) {
            Image(systemName: "square.grid.2x2").tag(FolderPageViewMode.icons)
            Image(systemName: "list.bullet").tag(FolderPageViewMode.list)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 88)
        .help("Show contents as icons or a list")
    }

    /// Tappable path segments for nested folders (dashboard drill-down trail).
    @ViewBuilder
    private func folderBreadcrumb(folderID: UUID) -> some View {
        let chain = breadcrumbChain(folderID: folderID)
        if chain.count > 1 {
            HStack(spacing: 4) {
                ForEach(Array(chain.enumerated()), id: \.element.id) { index, folder in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button(folder.name) {
                        model.activatePane(index: paneIndex)
                        model.selectFolderForPage(folder.id, pane: paneIndex)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(index == chain.count - 1 ? .secondary : Color.accentColor)
                    .disabled(index == chain.count - 1)
                }
            }
        }
    }

    private func breadcrumbChain(folderID: UUID) -> [FolderEntry] {
        var chain: [FolderEntry] = []
        var currentID: UUID? = folderID
        var guardCounter = 0
        while let id = currentID, id != FolderCatalog.rootFolderID, guardCounter < 64 {
            guard let entry = model.folderCatalog.folder(id: id) else { break }
            chain.insert(entry, at: 0)
            currentID = entry.parentFolderID
            guardCounter += 1
        }
        return chain
    }

    @ViewBuilder
    private var repositoryNoteListContent: some View {
        let summaries = model.folderPageNoteSummaries(forPane: paneIndex)
        let pinned = summaries.filter { model.isNotePinned($0.noteID) }
        let unpinned = summaries.filter { !model.isNotePinned($0.noteID) }

        if !pinned.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("Pinned", systemImage: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(pinned) { summary in
                    noteRow(summary)
                }
            }
            Divider()
        }

        ForEach(unpinned) { summary in
            noteRow(summary)
        }

        if summaries.isEmpty {
            Text("No notes in this folder yet.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func noteRow(_ summary: NoteSummary) -> some View {
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
        .contextMenu {
            Button(model.isNotePinned(summary.noteID) ? "Unpin Note" : "Pin Note") {
                model.togglePinned(noteID: summary.noteID)
            }
            let destinations = model.moveDestinationFolders(excludingFolderID: summary.folderID)
            if !destinations.isEmpty {
                Menu("Move To") {
                    ForEach(destinations, id: \.id) { destination in
                        Button(destination.name) {
                            model.moveNote(noteID: summary.noteID, toFolderID: destination.id)
                        }
                    }
                }
            }
        }
        .draggable(NoteTransfer(noteID: summary.noteID, title: summary.title))
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

                if model.isBodySearchIndexBuilding {
                    Label("Indexing note text…", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let matches = model.vaultSearchMatchingNoteSummaries(forPane: paneIndex)
                ForEach(matches) { summary in
                    NoteLinkRow(
                        title: summary.title,
                        subtitle: model.searchSnippet(for: summary, pane: paneIndex)
                            ?? model.vaultSearchResultSubtitle(for: summary),
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

import SwiftUI

struct WorkspaceFolderSidebarView: View {
    @Bindable var model: AppModel
    @State private var renamingFolder: FolderEntry?
    @State private var renameFieldText = ""

    var body: some View {
        List(selection: folderSelection) {
            if model.hasRootLevelNotes {
                Label("Vault", systemImage: "tray.full")
                    .tag(Optional(FolderCatalog.rootFolderID))
            }
            ForEach(model.topLevelFolderEntries, id: \.id) { folder in
                Text(folder.name)
                    .tag(Optional(folder.id))
                    .contextMenu {
                        Button("Rename…") {
                            renamingFolder = folder
                            renameFieldText = folder.name
                        }
                        Button("Delete Folder", role: .destructive) {
                            model.deleteFolder(id: folder.id)
                        }
                    }
            }
        }
        .navigationTitle("Folders")
        .alert("Rename Folder", isPresented: renameBinding, presenting: renamingFolder) { folder in
            TextField("Name", text: $renameFieldText)
            Button("Cancel", role: .cancel) {
                renamingFolder = nil
            }
            Button("OK") {
                let trimmed = renameFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    model.renameFolder(id: folder.id, newName: trimmed)
                }
                renamingFolder = nil
            }
        } message: { _ in
            Text("Enter a new name for this folder.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.createFolder()
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                Button {
                    model.createNote()
                } label: {
                    Label("New Note", systemImage: "plus")
                }
            }
        }
    }

    private var folderSelection: Binding<UUID?> {
        Binding(
            get: { model.selectedFolderID },
            set: { new in
                Task { await model.selectFolderForPage(new) }
            }
        )
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )
    }
}

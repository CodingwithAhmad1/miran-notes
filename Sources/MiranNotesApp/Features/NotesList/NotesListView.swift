import MiranNotesCore
import SwiftUI

private struct SidebarOutlineRows: View {
    let entries: [SidebarOutlineEntry]
    @ObservedObject var model: AppModel

    var body: some View {
        ForEach(entries) { entry in
            switch entry {
            case let .folder(folder, children):
                DisclosureGroup {
                    SidebarOutlineRows(entries: children, model: model)
                } label: {
                    Text(folder.name)
                }
                .contextMenu {
                    Button("New Folder Inside…") {
                        model.createFolder(parentID: folder.id, name: "New Folder")
                    }
                    Button("Delete Folder", role: .destructive) {
                        model.deleteFolder(id: folder.id)
                    }
                }
            case let .note(note, searchSnippet):
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                    if let searchSnippet, !searchSnippet.isEmpty {
                        Text(searchSnippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .tag(Optional(note.relativePath))
            }
        }
    }
}

struct NotesListView: View {
    @ObservedObject var model: AppModel

    private var emptyListMessage: String {
        if model.noteSummaries.isEmpty {
            return "No notes yet"
        }
        if !model.noteQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No matching notes"
        }
        return "No notes yet"
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.selectedBaseName },
            set: { model.changeSelection(baseName: $0) }
        )
    }

    var body: some View {
        List(selection: selectionBinding) {
            SidebarOutlineRows(entries: model.sidebarOutline, model: model)
        }
        .searchable(text: $model.noteQuery, prompt: Text("Search notes"))
        .overlay {
            if model.filteredNoteSummaries.isEmpty && !model.isLoading {
                Text(emptyListMessage)
                    .foregroundStyle(.secondary)
            }
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
                Button(role: .destructive) {
                    model.deleteSelectedNote()
                } label: {
                    Label("Delete Note", systemImage: "trash")
                }
                .disabled(model.selectedBaseName == nil)
            }
        }
    }
}

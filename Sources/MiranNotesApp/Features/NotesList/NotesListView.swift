import MiranNotesCore
import SwiftUI

private struct SidebarOutlineRows: View {
    let entries: [SidebarOutlineEntry]
    var model: AppModel
    let selectedNoteID: UUID?

    @State private var hoveredNoteID: UUID?

    var body: some View {
        ForEach(entries) { entry in
            switch entry {
            case let .folder(folder, children):
                DisclosureGroup {
                    SidebarOutlineRows(entries: children, model: model, selectedNoteID: selectedNoteID)
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
                .tag(Optional(note.noteID))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(rowColor(for: note.noteID))
                        .allowsHitTesting(false)
                )
                .onHover { isHovered in
                    hoveredNoteID = isHovered ? note.noteID : nil
                }
            }
        }
    }

    private func rowColor(for noteID: UUID) -> Color {
        if noteID == selectedNoteID {
            return Color.primary.opacity(0.10)
        } else if noteID == hoveredNoteID {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }
}

struct NotesListView: View {
    @Bindable var model: AppModel

    private var emptyListMessage: String {
        if model.noteSummaries.isEmpty {
            return "No notes yet"
        }
        if !model.noteQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No matching notes"
        }
        return "No notes yet"
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { model.selectedNoteID },
            set: { model.changeSelection(noteID: $0) }
        )
    }

    var body: some View {
        List(selection: selectionBinding) {
            SidebarOutlineRows(entries: model.sidebarOutline, model: model, selectedNoteID: model.selectedNoteID)
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
                .disabled(model.selectedNoteID == nil)
            }
        }
    }
}

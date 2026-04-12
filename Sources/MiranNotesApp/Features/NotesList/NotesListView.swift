import MiranNotesCore
import SwiftUI

struct NotesListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List(selection: Binding(
            get: { model.selectedBaseName },
            set: { model.changeSelection(baseName: $0) }
        )) {
            ForEach(model.filteredNoteSummaries, id: \.baseName) { note in
                Text(note.title)
                    .tag(Optional(note.baseName))
            }
        }
        .searchable(text: $model.noteQuery, prompt: Text("Search notes"))
        .overlay {
            if model.filteredNoteSummaries.isEmpty && !model.isLoading {
                Text("No notes yet")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            Button {
                model.createNote()
            } label: {
                Label("New Note", systemImage: "plus")
            }
        }
    }
}

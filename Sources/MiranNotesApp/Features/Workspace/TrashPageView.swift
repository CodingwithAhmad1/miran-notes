import SwiftUI

/// Trash sheet: restore or permanently delete trashed notes (`.miran/trash/`).
struct TrashPageView: View {
    @Bindable var model: AppModel
    @State private var confirmEmptyTrash = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Trash", systemImage: "trash")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Empty Trash", role: .destructive) {
                    confirmEmptyTrash = true
                }
                .disabled(model.trashedNotes.isEmpty)
                Button("Done") {
                    model.isTrashPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if model.trashedNotes.isEmpty {
                ContentUnavailableView(
                    "Trash is empty",
                    systemImage: "trash",
                    description: Text("Deleted notes are kept here until you empty the trash.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.trashedNotes) { item in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .fontWeight(.medium)
                            Text("\(item.originalRelativePath) — deleted \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Restore") {
                            model.restoreTrashedNote(noteID: item.noteID)
                        }
                        Button(role: .destructive) {
                            model.deleteTrashedNotePermanently(noteID: item.noteID)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Delete permanently")
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 480, minHeight: 340)
        .onAppear { model.refreshTrashedNotes() }
        .confirmationDialog(
            "Permanently delete all trashed notes?",
            isPresented: $confirmEmptyTrash,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) {
                model.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

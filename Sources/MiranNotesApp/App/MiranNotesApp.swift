import MiranNotesCore
import SwiftUI

@main
struct MiranNotesApp: App {
    @StateObject private var model: AppModel

    init() {
        let vault = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("MiranNotesVault", isDirectory: true)
        let repository = NoteRepository(vaultURL: vault)
        _model = StateObject(wrappedValue: AppModel(repository: repository))
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                NotesListView(model: model)
                    .navigationTitle("Notes")
            } detail: {
                if model.activeDocument != nil {
                    EditorRootView(model: model)
                } else {
                    ContentUnavailableView(
                        "Select a note",
                        systemImage: "note.text",
                        description: Text("Create or open a note to start editing.")
                    )
                }
            }
            .task {
                model.loadVault()
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { model.lastError != nil },
                    set: { if !$0 { model.lastError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    model.lastError = nil
                }
            } message: {
                Text(model.lastError ?? "")
            }
            .alert(
                "File changed on disk",
                isPresented: Binding(
                    get: { model.externalEditConflictAlert != nil },
                    set: { newValue in
                        if !newValue, model.externalEditConflictAlert != nil {
                            model.resolveExternalEditConflict(reloadFromDisk: false)
                        }
                    }
                ),
                presenting: model.externalEditConflictAlert,
                actions: { _ in
                    Button("Reload from disk", role: .destructive) {
                        model.resolveExternalEditConflict(reloadFromDisk: true)
                    }
                    Button("Keep local edits", role: .cancel) {
                        model.resolveExternalEditConflict(reloadFromDisk: false)
                    }
                },
                message: { _ in
                    Text(
                        "This note was modified outside the app while you have unsaved edits. Reload replaces your buffer with the files on disk; keeping edits leaves your text in memory and the next save may overwrite external changes."
                    )
                }
            )
        }
    }
}

private struct EditorRootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if let current = model.activeDocument {
                SingleSurfaceNoteEditor(
                    document: Binding(
                        get: { model.activeDocument ?? current },
                        set: { model.activeDocument = $0 }
                    ),
                    onCommands: { model.apply($0) }
                )
                .navigationTitle("Editor")
            }
        }
        .onAppear {
            model.setUndoManager(undoManager)
        }
        .onChange(of: undoManager) { _, newValue in
            model.setUndoManager(newValue)
        }
    }
}

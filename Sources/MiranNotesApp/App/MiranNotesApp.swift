import AppKit
import MiranNotesCore
import SwiftUI

private final class MiranNotesAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MiranNotesApp: App {
    @NSApplicationDelegateAdaptor(MiranNotesAppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        SlashCommandRegistry.registerBuiltins()
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
            .sheet(item: $model.tableEditorPayload) { payload in
                TableEditorSheet(jsonlURL: payload.jsonlURL, schemaURL: payload.schemaURL)
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
        .commands {
            CommandMenu("Format") {
                Button("Bold") {
                    NSApp.sendAction(Selector(("toggleBold:")), to: nil, from: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
                Button("Italic") {
                    NSApp.sendAction(Selector(("toggleItalic:")), to: nil, from: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
                Button("Code") {
                    NSApp.sendAction(Selector(("toggleCodeSpan:")), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}

private struct EditorRootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.undoManager) private var undoManager
    var body: some View {
        Group {
            if let current = model.activeDocument {
                HSplitView {
                    VStack(spacing: 0) {
                        if let notice = model.repairNotice {
                            RepairNoticeBanner(message: notice) {
                                model.repairNotice = nil
                            }
                        }
                        SingleSurfaceNoteEditor(
                            document: Binding(
                                get: { model.activeDocument ?? current },
                                set: { model.activeDocument = $0 }
                            ),
                            cursorOffset: $model.editorCursorOffset,
                            onCommands: { commands in model.apply(commands) },
                            onWikiLinkClick: { targetID in
                                model.openNote(noteID: targetID)
                            },
                            onFullReplaceWarning: {
                                model.repairNotice = "Block structure may have been partially lost due to a complex paste or undo operation."
                            },
                            onSizeLimitExceeded: {
                                model.repairNotice = "Note is at the 1 MB size limit. Content was not added."
                            }
                        )
                    }
                    .frame(minWidth: 320)
                    .navigationTitle("Editor")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backlinks")
                            .font(.headline)
                        if model.backlinks.isEmpty {
                            Text("No incoming links")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            List(model.backlinks, id: \.baseName) { note in
                                Button(note.title) {
                                    model.openNote(noteID: note.noteID)
                                }
                                .buttonStyle(.plain)
                            }
                            .listStyle(.sidebar)
                        }
                    }
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 280)
                    .padding(.horizontal, 8)
                }
                .toolbar {
                    ToolbarItemGroup {
                        Menu("Link") {
                            ForEach(model.noteSummaries.filter { $0.noteID != current.metadata.noteID }, id: \.baseName) { note in
                                Button(note.title) {
                                    model.insertWikiLink(to: note.noteID, displayText: note.title)
                                }
                            }
                        }
                        Button("Table") {
                            model.addTableToActiveNote()
                        }
                        Button("Open table") {
                            model.openFirstTableArtifact()
                        }
                        .disabled(!current.metadata.artifacts.contains { $0.kind == .table })
                    }
                }
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

private struct RepairNoticeBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}

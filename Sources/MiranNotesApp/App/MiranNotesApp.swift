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
    @State private var conflictDetailsPresented = false
    @State private var conflictDetailsDiskDate: Date?

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
            .sheet(item: $model.externalTextCompare) { payload in
                ExternalEditCompareSheet(payload: payload) {
                    model.externalTextCompare = nil
                }
            }
            .sheet(isPresented: $conflictDetailsPresented) {
                NavigationStack {
                    ScrollView {
                        Text(ExternalEditConflictCopy.detailsLines(diskDate: conflictDetailsDiskDate ?? Date()))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(minWidth: 360, minHeight: 200)
                    .navigationTitle("Details")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                conflictDetailsPresented = false
                            }
                        }
                    }
                }
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
                ExternalEditConflictCopy.alertTitle,
                isPresented: Binding(
                    get: { model.externalEditConflictAlert != nil },
                    set: { newValue in
                        if !newValue, model.externalEditConflictAlert != nil {
                            model.resolveExternalEditConflict(reloadFromDisk: false)
                        }
                    }
                ),
                presenting: model.externalEditConflictAlert,
                actions: { conflict in
                    Button(ExternalEditConflictCopy.buttonKeepEdits, role: .cancel) {
                        model.resolveExternalEditConflict(reloadFromDisk: false)
                    }
                    Button(ExternalEditConflictCopy.buttonUseSavedFile, role: .destructive) {
                        model.resolveExternalEditConflict(reloadFromDisk: true)
                    }
                    Button(ExternalEditConflictCopy.buttonShowInFinder) {
                        model.revealSelectedNoteFileInFinder()
                    }
                    Button(ExternalEditConflictCopy.buttonDetails) {
                        conflictDetailsDiskDate = conflict.diskDate
                        conflictDetailsPresented = true
                    }
                    Button(ExternalEditConflictCopy.buttonCompare) {
                        model.openExternalEditCompare()
                    }
                },
                message: { _ in
                    Text(ExternalEditConflictCopy.alertMessage)
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
    @State private var repairDetailsPresented = false

    var body: some View {
        Group {
            if let current = model.activeDocument {
                HSplitView {
                    VStack(spacing: 0) {
                        if let diskHint = model.diskActivityBanner {
                            DiskActivityBanner(text: diskHint, onDismiss: { model.dismissDiskActivityBanner() })
                        }
                        if let advisory = model.repairAdvisory {
                            RepairNoticeBanner(
                                advisory: advisory,
                                onDismiss: { model.dismissRepairAdvisory() },
                                onShowInFinder: { model.revealSelectedNoteFileInFinder() },
                                onDetails: {
                                    repairDetailsPresented = true
                                },
                                showDetailsButton: advisory.detailsPlainText != nil
                            )
                            .sheet(isPresented: $repairDetailsPresented) {
                                RepairAdvisoryDetailsSheet(
                                    detailsText: advisory.detailsPlainText ?? "",
                                    onDone: { repairDetailsPresented = false }
                                )
                            }
                        }
                        SingleSurfaceNoteEditor(
                            document: Binding(
                                get: { model.activeDocument ?? current },
                                set: { model.activeDocument = $0 }
                            ),
                            cursorOffset: $model.editorCursorOffset,
                            editorTextSelection: $model.editorTextSelection,
                            pendingEditorScroll: model.pendingEditorScroll,
                            onPendingEditorScrollConsumed: { model.clearPendingEditorScroll() },
                            onCommands: { commands in model.apply(commands) },
                            onWikiLinkClick: { targetID in
                                model.openNote(noteID: targetID)
                            },
                            onFullReplaceWarning: {
                                model.presentFullBufferAdvisory()
                            },
                            onSizeLimitExceeded: {
                                model.presentSizeLimitAdvisory()
                            }
                        )
                    }
                    .frame(minWidth: 320)
                    .navigationTitle("Editor")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backlinks")
                            .font(.headline)
                        if model.backlinks.isEmpty {
                            Text("No notes link here yet")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            List(model.backlinks, id: \.sourceNoteID) { item in
                                Button {
                                    model.openBacklinkSource(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.body)
                                            .multilineTextAlignment(.leading)
                                        if !item.snippet.isEmpty {
                                            Text(item.snippet)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            ForEach(model.noteSummaries.filter { $0.noteID != current.metadata.noteID }, id: \.relativePath) { note in
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

private struct RepairAdvisoryDetailsSheet: View {
    let detailsText: String
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: detailsText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(minWidth: 360, minHeight: 220)
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

private struct RepairNoticeBanner: View {
    let advisory: RepairAdvisory
    let onDismiss: () -> Void
    let onShowInFinder: () -> Void
    let onDetails: () -> Void
    let showDetailsButton: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(advisory.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(advisory.explanation)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Got it", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            HStack(spacing: 12) {
                Button("Show in Finder", action: onShowInFinder)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showDetailsButton {
                    Button("Details", action: onDetails)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}

private struct DiskActivityBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "externaldrive")
                .foregroundStyle(.blue)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
    }
}

private struct ExternalEditCompareSheet: View {
    let payload: ExternalTextComparePayload
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your edits (editor)")
                        .font(.headline)
                    ScrollView {
                        Text(payload.localText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 200)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved file (disk)")
                        .font(.headline)
                    ScrollView {
                        Text(payload.diskText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 200)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .frame(minWidth: 520, minHeight: 320)
            .navigationTitle("Compare text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

import MiranNotesCore
import SwiftUI

private struct SidebarOutlineRows: View {
    let entries: [SidebarOutlineEntry]
    var model: AppModel
    let selectedNoteID: UUID?

    @State private var hoveredNoteID: UUID?
    @State private var revealedPathNoteIDs: Set<UUID> = []
    @State private var pulsingPathNoteID: UUID?

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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if revealedPathNoteIDs.contains(note.noteID), !note.relativePath.isEmpty {
                            Text(note.relativePath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        Text(note.title)
                        if let searchSnippet, !searchSnippet.isEmpty {
                            Text(searchSnippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    if !note.relativePath.isEmpty {
                        Button {
                            withAnimation(.easeOut(duration: 0.12)) {
                                pulsingPathNoteID = note.noteID
                            }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 120_000_000)
                                withAnimation(.easeOut(duration: 0.14)) {
                                    pulsingPathNoteID = nil
                                    if revealedPathNoteIDs.contains(note.noteID) {
                                        revealedPathNoteIDs.remove(note.noteID)
                                    } else {
                                        revealedPathNoteIDs.insert(note.noteID)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(width: 22, height: 22)
                                .contentShape(Circle())
                                .scaleEffect(pulsingPathNoteID == note.noteID ? 1.15 : 1.0)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Toggle note path")
                        .help(note.relativePath)
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
    /// When this list is shown beside the window toolbar search field, wire this to clear that field’s focus.
    var onDismissCompanionToolbarSearch: () -> Void = {}
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.scenePhase) private var scenePhase

    private var emptyListMessage: String {
        if model.noteSummaries.isEmpty {
            return "No notes yet"
        }
        if !model.vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                onDismissCompanionToolbarSearch()
            }
        )
        .onChange(of: controlActiveState) { _, newValue in
            if newValue == .inactive {
                onDismissCompanionToolbarSearch()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                onDismissCompanionToolbarSearch()
            }
        }
        .overlay {
            let queryNonEmpty = !model.vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if queryNonEmpty && model.isBodySearchIndexBuilding {
                Text("Indexing note text…")
                    .foregroundStyle(.secondary)
            } else if model.filteredNoteSummaries.isEmpty && !model.isLoading {
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
                .disabled(!model.allowsToolbarNewNote)
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

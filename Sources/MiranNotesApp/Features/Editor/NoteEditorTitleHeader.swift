import SwiftUI

/// In-content note title: editable display name (backed by `renameActiveNote`), separated from the body; Return moves the caret into the note.
struct NoteEditorTitleHeader: View {
    @Bindable var model: AppModel
    /// Which workspace tile this header belongs to.
    var paneIndex: Int = 0
    var onRequestFocusNoteBody: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool
    /// Suppresses duplicate renames while `selectedBaseName` is still updating after submit.
    @State private var pendingDisplayedTitleUntilPathUpdates: String?

    private var canonicalTitle: String { model.selectedNoteHeaderTitle(forPane: paneIndex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Note title", text: $titleDraft)
                .font(.system(size: 26, weight: .semibold))
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .padding(.horizontal, 48)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .onSubmit {
                    commitTitle(moveCaretToBody: true)
                }
            Divider()
        }
        .onAppear {
            syncDraftFromModel()
        }
        .onChange(of: model.workspacePanes[paneIndex].selectedBaseName) { _, _ in
            pendingDisplayedTitleUntilPathUpdates = nil
            syncDraftFromModel()
        }
        .onChange(of: model.workspacePanes[paneIndex].selectedNoteID) { oldID, newID in
            if oldID != nil, newID == nil {
                commitTitle(moveCaretToBody: false)
            }
            pendingDisplayedTitleUntilPathUpdates = nil
            syncDraftFromModel()
        }
        .onChange(of: titleFocused) { _, focused in
            if !focused {
                commitTitle(moveCaretToBody: false)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, titleFocused {
                commitTitle(moveCaretToBody: false)
            }
        }
    }

    private func syncDraftFromModel() {
        titleDraft = canonicalTitle
    }

    private func commitTitle(moveCaretToBody: Bool) {
        let current = canonicalTitle
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if let pending = pendingDisplayedTitleUntilPathUpdates, pending == trimmed {
            if moveCaretToBody { onRequestFocusNoteBody() }
            return
        }

        if trimmed.isEmpty {
            titleDraft = current
            if moveCaretToBody { onRequestFocusNoteBody() }
            return
        }

        if trimmed == current {
            if moveCaretToBody { onRequestFocusNoteBody() }
            return
        }

        pendingDisplayedTitleUntilPathUpdates = trimmed
        model.renameActiveNote(newTitle: trimmed, pane: paneIndex)
        if moveCaretToBody { onRequestFocusNoteBody() }
    }
}

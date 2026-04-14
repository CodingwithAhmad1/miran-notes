import SwiftUI

/// In-content note title: editable display name (backed by `renameActiveNote`), separated from the body; Return moves the caret into the note.
struct NoteEditorTitleHeader: View {
    @Bindable var model: AppModel
    var onRequestFocusNoteBody: () -> Void

    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool
    /// Suppresses duplicate renames while `selectedBaseName` is still updating after submit.
    @State private var pendingDisplayedTitleUntilPathUpdates: String?

    private var pathDisplayTitle: String {
        guard let path = model.selectedBaseName else { return "" }
        return VaultPath.displayTitle(forRelativePath: path)
    }

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
        .onChange(of: model.selectedBaseName) { _, _ in
            pendingDisplayedTitleUntilPathUpdates = nil
            syncDraftFromModel()
        }
        .onChange(of: model.selectedNoteID) { _, _ in
            pendingDisplayedTitleUntilPathUpdates = nil
            syncDraftFromModel()
        }
        .onChange(of: titleFocused) { _, focused in
            if !focused {
                commitTitle(moveCaretToBody: false)
            }
        }
    }

    private func syncDraftFromModel() {
        titleDraft = pathDisplayTitle
    }

    private func commitTitle(moveCaretToBody: Bool) {
        let current = pathDisplayTitle
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
        model.renameActiveNote(newTitle: trimmed)
        if moveCaretToBody { onRequestFocusNoteBody() }
    }
}

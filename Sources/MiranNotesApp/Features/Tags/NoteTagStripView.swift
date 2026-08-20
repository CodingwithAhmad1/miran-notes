import SwiftUI

/// Tag chips + add field under the note title. Tags live in `metadata.properties["tags"]`
/// and mutate through `EditCommand.setProperty` (undoable, engine-only). Clicking a chip sets
/// the pane's vault search to `#tag`.
struct NoteTagStripView: View {
    @Bindable var model: AppModel
    var paneIndex: Int
    @State private var newTagText = ""
    @FocusState private var isAddFieldFocused: Bool

    private var tags: [String] {
        guard model.workspacePanes.indices.contains(paneIndex),
              let doc = model.workspacePanes[paneIndex].activeDocument else { return [] }
        return NoteTags.parse(doc.metadata.properties)
    }

    var body: some View {
        if model.workspacePanes.indices.contains(paneIndex),
           model.workspacePanes[paneIndex].activeDocument != nil {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 2) {
                        Button("#\(tag)") {
                            model.closeToFolderPage(pane: paneIndex)
                            model.workspacePanes[paneIndex].vaultSearchQuery = "#\(tag)"
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        Button {
                            model.removeTag(tag, pane: paneIndex)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove tag")
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }

                TextField("Add tag", text: $newTagText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .frame(maxWidth: 100)
                    .focused($isAddFieldFocused)
                    .onSubmit {
                        let tag = NoteTags.normalize(newTagText)
                        newTagText = ""
                        guard !tag.isEmpty else { return }
                        model.addTag(tag, pane: paneIndex)
                        isAddFieldFocused = true
                    }

                Spacer()
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 4)
        }
    }
}

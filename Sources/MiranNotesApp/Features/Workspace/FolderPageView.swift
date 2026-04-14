import SwiftUI

struct FolderPageView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.selectedFolderID == nil {
                if model.isEmptyVaultOnboardingState {
                    ContentUnavailableView {
                        Label("Welcome to Miran Notes", systemImage: "note.text")
                    } description: {
                        Text(
                            "Your notes are plain text files in this workspace—local-first and private.\n\n"
                                + "Miran is for calm, personal knowledge—not cloud collaboration or a shared wiki by default.\n\n"
                                + "Use New Folder or New Note in the Folders sidebar. Open Workspace… (Shift-Command-O) picks a different folder."
                        )
                    }
                } else {
                    ContentUnavailableView(
                        "No folder selected",
                        systemImage: "folder",
                        description: Text("Add a folder from the sidebar, or choose notes in the vault root.")
                    )
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(model.selectedFolderDisplayTitle)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .padding(.bottom, 4)

                        ForEach(model.folderPageNoteSummaries) { summary in
                            noteSection(summary)
                        }

                        if model.folderPageNoteSummaries.isEmpty {
                            Text("No notes in this folder yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
        }
    }

    @ViewBuilder
    private func noteSection(_ summary: NoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(summary.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(role: .destructive) {
                    model.deleteNoteFromFolder(noteID: summary.noteID)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete note")
            }

            TextEditor(text: model.bindingForFolderPageNoteText(noteID: summary.noteID))
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140, alignment: .topLeading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 4)
    }
}

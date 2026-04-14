import SwiftUI

enum EditingHelpContent {
    static let navigationTitle = "Editing in Miran Notes"

    static let undoTitle = "Undo"
    static let undoBody = """
        Undo applies to the note you are editing in the active pane. If you use a multi-pane layout and switch \
        which pane is editable, the undo history for the previous note is cleared so each pane stays consistent. \
        In the usual single-pane layout, this does not come up.
        """

    static let largeNotesTitle = "Large notes"
    static let largeNotesBody = """
        Each note has a maximum size (about one million characters). If you reach the limit, Miran stops adding \
        text and tells you—your existing content stays safe.
        """

    static let linksTitle = "Wiki links"
    static let linksBody = """
        Use wiki-style links to jump between notes. Links are tied to each note’s stable identity, not just its \
        title, so renaming a note does not break navigation from other notes.
        """
}

struct EditingHelpSheet: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section(title: EditingHelpContent.undoTitle, body: EditingHelpContent.undoBody)
                    section(title: EditingHelpContent.largeNotesTitle, body: EditingHelpContent.largeNotesBody)
                    section(title: EditingHelpContent.linksTitle, body: EditingHelpContent.linksBody)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .frame(minWidth: 400, minHeight: 360)
            .navigationTitle(EditingHelpContent.navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    @ViewBuilder
    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

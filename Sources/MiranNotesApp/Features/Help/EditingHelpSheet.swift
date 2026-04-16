import SwiftUI

enum EditingHelpContent {
    static let navigationTitle = "Editing in Miran Notes"

    static let undoTitle = "Undo"
    static let undoBody = """
        Undo applies to the note you are editing in the active pane. If you use a multi-pane layout and switch \
        which pane is editable, the undo history for the previous note is cleared so each pane stays consistent. \
        In the usual single-pane layout, this does not come up.
        """

    static let multiPaneTitle = "Multi-pane layouts"
    static let multiPaneBody = """
        Split layouts show a full sidebar and folder page (or note) in each tile, all using the same vault. The \
        highlighted tile is the active pane: the window toolbar search, back button, and undo stack follow that \
        tile. Click a tile or start typing in its editor to make it active.
        """

    static let largeNotesTitle = "Large notes"
    static let largeNotesBody = """
        Each note has a maximum size (about one million characters). If you reach the limit, Miran stops adding \
        text and tells you—your existing content stays safe.
        """

    static let linksTitle = "Note links (not in UI yet)"
    static let linksBody = """
        Wiki-style links between notes are not shown in the editor right now—there is no click-to-follow or link \
        highlighting. Your vault can still contain link data from earlier versions or other tools; nothing is deleted. \
        The editing engine keeps supporting links under the hood for when we turn the UI back on.
        """
}

struct EditingHelpSheet: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section(title: EditingHelpContent.undoTitle, body: EditingHelpContent.undoBody)
                    section(title: EditingHelpContent.multiPaneTitle, body: EditingHelpContent.multiPaneBody)
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

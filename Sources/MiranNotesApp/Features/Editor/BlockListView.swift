import MiranNotesCore
import SwiftUI

struct BlockListView: View {
    @Binding var document: NoteDocument
    let onCommand: (EditCommand) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(document.metadata.blocks) { block in
                    BlockRowView(
                        block: block,
                        document: $document,
                        onCommand: onCommand
                    )
                }
            }
            .padding(16)
        }
    }
}

private struct BlockRowView: View {
    let block: Block
    @Binding var document: NoteDocument
    let onCommand: (EditCommand) -> Void

    var body: some View {
        switch block.type {
        case .paragraph:
            editor
        case .heading:
            editor
        case .listItem:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                editor
            }
        case .callout:
            HStack(alignment: .top, spacing: 8) {
                Text(block.icon ?? "💡")
                editor
            }
            .padding(10)
            .background(Color.yellow.opacity(0.15))
            .cornerRadius(8)
        case .code:
            editor
                .padding(8)
                .background(Color.black.opacity(0.06))
                .cornerRadius(6)
        case .divider:
            Divider()
        }
    }

    private var editor: some View {
        TextKit2BlockEditor(block: block, document: $document, onCommand: onCommand)
            .frame(minHeight: 24)
    }
}

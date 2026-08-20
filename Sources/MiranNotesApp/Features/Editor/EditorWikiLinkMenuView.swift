import SwiftUI

/// Row model for the `[[` autocomplete popover.
enum WikiLinkMenuEntry: Equatable {
    case note(noteID: UUID, title: String, relativePath: String)
    case create(title: String)
}

@MainActor
struct EditorWikiLinkMenuView: View {
    let entries: [WikiLinkMenuEntry]
    let highlightedIndex: Int
    let hasQuery: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                Text(hasQuery ? "No matching notes" : "Type a note title")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    row(entry)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(index == highlightedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(index) }
                }
            }
        }
        .frame(width: 320)
        .padding(.vertical, 4)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func row(_ entry: WikiLinkMenuEntry) -> some View {
        switch entry {
        case .note(_, let title, let relativePath):
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(relativePath)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
        case .create(let title):
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                Text("Create “\(title)”")
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
            }
        }
    }
}

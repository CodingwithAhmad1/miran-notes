import MiranNotesCore
import SwiftUI

@MainActor
struct EditorSlashCommandMenuView: View {
    let matches: [SlashCommandMatch]
    let highlightedIndex: Int
    let hasQuery: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if matches.isEmpty {
                Text(hasQuery ? "No commands found" : "Type to search commands")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(matches.enumerated()), id: \.element.item.id) { index, match in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.item.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text("/\(match.item.id)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(match.item.category)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
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
}

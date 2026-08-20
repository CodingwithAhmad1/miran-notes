import SwiftUI

/// Collapsible "Linked mentions" strip under the editor: notes whose wiki links point at the open note.
/// Rows come from `WorkspacePaneSession.backlinks` (kept fresh by `AppModel.refreshBacklinks`); tapping
/// one opens the source note and scrolls to the link (`AppModel.openBacklinkSource`).
struct BacklinksPanelView: View {
    @Bindable var model: AppModel
    var paneIndex: Int

    private var backlinks: [BacklinkItem] {
        guard model.workspacePanes.indices.contains(paneIndex) else { return [] }
        return model.workspacePanes[paneIndex].backlinks
    }

    private var isExpanded: Bool {
        guard model.workspacePanes.indices.contains(paneIndex) else { return false }
        return model.workspacePanes[paneIndex].showBacklinksPanel
    }

    var body: some View {
        if !backlinks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                Button {
                    model.workspacePanes[paneIndex].showBacklinksPanel.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.up.left")
                            .font(.caption)
                        Text("Linked mentions (\(backlinks.count))")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle linked mentions")

                if isExpanded {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(backlinks) { item in
                                NoteLinkRow(
                                    title: item.title,
                                    subtitle: item.snippet.isEmpty ? nil : item.snippet,
                                    pathTooltip: item.relativePath,
                                    onTap: { model.openBacklinkSource(item, pane: paneIndex) }
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 180)
                }
            }
            .background(.thinMaterial)
        }
    }
}

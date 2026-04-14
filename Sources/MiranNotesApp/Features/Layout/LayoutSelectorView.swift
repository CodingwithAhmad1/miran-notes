import SwiftUI

/// Popover panel for choosing a pane layout, shown from the top-right layout button.
/// Left column lists saved layouts (empty for now); right column shows built-in layout options.
struct LayoutSelectorView: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Saved layouts (empty for now — placeholder row area)
            Color.clear.frame(height: 4)
            Divider()
            // Available layouts — icons only, no labels
            VStack(spacing: 2) {
                ForEach(PaneLayout.allCases, id: \.self) { layout in
                    layoutButton(for: layout)
                }
            }
            .padding(6)
        }
        .frame(width: 52)
    }

    private func layoutButton(for layout: PaneLayout) -> some View {
        let isSelected = model.currentLayout == layout
        return Button {
            switch layout {
            case .single:
                model.setLayout(layout)
                dismiss()
            case .twoPane, .threePane, .fourPane:
                let payload = WorkspaceWindowPayload(
                    vaultPath: model.repository.vaultURL.path,
                    initialLayout: layout,
                    workspaceScope: model.workspaceScope
                )
                openWindow(value: payload)
                dismiss()
            }
        } label: {
            LayoutIconView(layout: layout, isSelected: isSelected)
                .padding(4)
                .background(
                    isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
    }
}

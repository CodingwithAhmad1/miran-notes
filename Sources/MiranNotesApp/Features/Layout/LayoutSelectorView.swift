import SwiftUI

/// Popover panel for choosing a pane layout, shown from the top-right layout button.
/// Left column lists saved layouts (empty for now); right column shows built-in layout options.
struct LayoutSelectorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            savedLayoutsColumn
            Divider()
            availableLayoutsColumn
        }
        .frame(minWidth: 360, minHeight: 180)
        .padding(16)
    }

    // MARK: - Saved layouts

    private var savedLayoutsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            columnHeading("Saved Layouts")
            Text("No saved layouts yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(minWidth: 130, maxWidth: 160, alignment: .topLeading)
        .padding(.trailing, 16)
    }

    // MARK: - Available layouts

    private var availableLayoutsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            columnHeading("Available Layouts")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 60), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(PaneLayout.allCases, id: \.self) { layout in
                    layoutButton(for: layout)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.leading, 16)
    }

    private func layoutButton(for layout: PaneLayout) -> some View {
        let isSelected = model.currentLayout == layout
        return Button {
            model.setLayout(layout)
            dismiss()
        } label: {
            VStack(spacing: 5) {
                LayoutIconView(layout: layout, isSelected: isSelected)
                Text(layout.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
    }

    private func columnHeading(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
    }
}

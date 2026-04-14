import SwiftUI

/// Tappable row for a note title. Optional subtitle supports snippets (e.g. future backlinks UI).
struct NoteLinkRow: View {
    let title: String
    var subtitle: String? = nil
    /// Shown in the system help tooltip (e.g. vault-relative path).
    var pathTooltip: String? = nil
    let onTap: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .center) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let pathTooltip, !pathTooltip.isEmpty {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Note path")
                    .help(pathTooltip)
            }

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete note")
            }
        }
        .padding(.vertical, 4)
    }
}

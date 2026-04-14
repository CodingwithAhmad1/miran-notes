import SwiftUI

/// Tappable row for a note title. Optional subtitle supports snippets (e.g. future backlinks UI).
struct NoteLinkRow: View {
    let title: String
    var subtitle: String?
    let onTap: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
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

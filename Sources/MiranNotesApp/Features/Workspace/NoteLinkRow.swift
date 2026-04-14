import SwiftUI

/// Tappable row for a note title. Optional subtitle supports snippets (e.g. future backlinks UI).
struct NoteLinkRow: View {
    let title: String
    var subtitle: String? = nil
    /// Shown in the system help tooltip (e.g. vault-relative path).
    var pathTooltip: String? = nil
    let onTap: () -> Void
    var onDelete: (() -> Void)?
    @State private var isPathVisible = false
    @State private var isPathIconPulsing = false

    var body: some View {
        HStack(alignment: .center) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    if let pathTooltip, !pathTooltip.isEmpty, isPathVisible {
                        Text(pathTooltip)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
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
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        isPathIconPulsing = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        withAnimation(.easeOut(duration: 0.14)) {
                            isPathIconPulsing = false
                            isPathVisible.toggle()
                        }
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                        .scaleEffect(isPathIconPulsing ? 1.15 : 1.0)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Toggle note path")
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

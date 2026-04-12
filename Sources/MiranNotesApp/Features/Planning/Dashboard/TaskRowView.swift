import SwiftUI
import MiranNotesCore

struct TaskRowView: View {
    let row: TableRowRecord
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var isComplete: Bool {
        row.cells["status"] == "complete"
    }

    private var priorityColor: Color {
        switch row.cells["priority"] {
        case "high": return .red
        case "medium": return .orange
        case "low": return .blue
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isComplete ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.cells["title"] ?? "Untitled")
                    .strikethrough(isComplete)
                    .foregroundStyle(isComplete ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let type = row.cells["type"], !type.isEmpty {
                        Text(type.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                    if let subject = row.cells["subject"], !subject.isEmpty {
                        Text(subject)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let time = row.cells["time"], !time.isEmpty {
                        Label(time, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let priority = row.cells["priority"], !priority.isEmpty {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit") { onEdit() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

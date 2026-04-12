import SwiftUI
import MiranNotesCore

struct InlineDatabaseRowView: View {
    enum RowKind {
        case task
        case session
    }

    let row: TableRowRecord
    let kind: RowKind
    var onToggleTask: ((UUID) -> Void)?

    private var title: String {
        row.cells["title"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? row.cells["title"]!
            : "Untitled"
    }

    var body: some View {
        HStack(spacing: 8) {
            if kind == .task {
                let isComplete = row.cells["status"] == "complete"
                Button {
                    onToggleTask?(row.id)
                } label: {
                    Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isComplete ? .green : .secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(sessionColor)
                    .frame(width: 3, height: 16)
            }

            Text(title)
                .font(.caption)
                .lineLimit(1)
                .strikethrough(kind == .task && row.cells["status"] == "complete")

            Spacer(minLength: 6)

            if let status = row.cells["status"], !status.isEmpty {
                Text(status.capitalized)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var sessionColor: Color {
        switch row.cells["type"] {
        case "session": return .indigo
        case "block": return .gray
        case "habit": return .green
        case "event": return .purple
        default: return .blue
        }
    }
}

import SwiftUI
import MiranNotesCore

/// Compact session list embeddable in the editor sidebar, showing today's sessions.
struct InlineSessionListView: View {
    @ObservedObject var model: PlanningModel
    let noteID: UUID?

    private var linkedSessions: [TableRowRecord] {
        guard let noteID else { return [] }
        let idStr = noteID.uuidString
        return model.allSessions.filter { $0.cells["linkedNote"] == idStr }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !linkedSessions.isEmpty {
                Text("Linked Sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(linkedSessions, id: \.id) { session in
                    compactSessionRow(session)
                }
            } else if !model.todaySessions.isEmpty {
                Text("Today's Sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(model.todaySessions.prefix(4), id: \.id) { session in
                    compactSessionRow(session)
                }
            }
        }
    }

    private func compactSessionRow(_ session: TableRowRecord) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(sessionColor(session))
                .frame(width: 3, height: 16)

            VStack(alignment: .leading, spacing: 0) {
                Text(session.cells["title"] ?? "")
                    .font(.caption)
                    .lineLimit(1)
                if let time = session.cells["startTime"], !time.isEmpty {
                    Text(time)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sessionColor(_ session: TableRowRecord) -> Color {
        switch session.cells["type"] {
        case "session": return .indigo
        case "block": return .gray
        case "habit": return .green
        case "event": return .purple
        default: return .blue
        }
    }
}

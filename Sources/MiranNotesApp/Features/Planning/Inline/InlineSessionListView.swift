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
        VStack(alignment: .leading, spacing: 0) {
            InlineDatabaseRowView(row: session, kind: .session)
            if let time = session.cells["startTime"], !time.isEmpty {
                Text(time)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

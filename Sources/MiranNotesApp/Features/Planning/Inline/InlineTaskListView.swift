import SwiftUI
import MiranNotesCore

/// Compact task list embeddable in the editor sidebar, showing tasks linked to the current note.
struct InlineTaskListView: View {
    @ObservedObject var model: PlanningModel
    let noteID: UUID?

    private var linkedTasks: [TableRowRecord] {
        guard let noteID else { return [] }
        let idStr = noteID.uuidString
        return model.allTasks.filter { $0.cells["linkedNote"] == idStr }
    }

    private var todayTasks: [TableRowRecord] {
        let dateStr = PlanningModel.dateString(Date())
        return model.todayTasks.filter { $0.cells["date"] == dateStr }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !linkedTasks.isEmpty {
                Text("Linked Tasks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(linkedTasks, id: \.id) { task in
                    compactTaskRow(task)
                }
            }

            if linkedTasks.isEmpty && !todayTasks.isEmpty {
                Text("Today's Tasks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(todayTasks.prefix(5), id: \.id) { task in
                    compactTaskRow(task)
                }
            }

            if linkedTasks.isEmpty && todayTasks.isEmpty {
                Text("No tasks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func compactTaskRow(_ task: TableRowRecord) -> some View {
        InlineDatabaseRowView(row: task, kind: .task) { rowID in
            Task { await model.toggleTaskComplete(rowID: rowID) }
        }
    }
}

import SwiftUI
import MiranNotesCore

struct PlanningDashboardView: View {
    @ObservedObject var model: PlanningModel
    @State private var editingTask: TableRowRecord?
    @State private var showingSessionSheet = false

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }

    var body: some View {
        VStack(spacing: 0) {
            QuickAddBar(model: model)
            Divider()
            dateNavigation
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sessionsSection
                    tasksSection
                    if !model.backlogTasks.isEmpty {
                        backlogSection
                    }
                }
                .padding()
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditSheet(model: model, mode: .edit(task)) {
                editingTask = nil
            }
        }
        .sheet(isPresented: $showingSessionSheet) {
            SessionEditSheet(model: model, mode: .create(prefillDate: model.selectedDate)) {
                showingSessionSheet = false
            }
        }
    }

    // MARK: - Date navigation

    private var dateNavigation: some View {
        HStack {
            Button {
                Task { await model.navigateDay(-1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Text(dateFormatter.string(from: model.selectedDate))
                .font(.headline)

            Spacer()

            Button {
                Task { await model.navigateDay(1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)

            Button("Today") {
                Task { await model.selectDate(Date()) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Sessions", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showingSessionSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if model.todaySessions.isEmpty {
                Text("No sessions scheduled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(model.todaySessions, id: \.id) { session in
                    SessionRowView(row: session) {
                        Task { await model.updateSessionStatus(rowID: session.id, status: "complete") }
                    }
                }
            }
        }
    }

    // MARK: - Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tasks", systemImage: "checklist")
                .font(.subheadline.weight(.semibold))

            if model.todayTasks.isEmpty {
                Text("No tasks for this day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(model.todayTasks, id: \.id) { task in
                    TaskRowView(
                        row: task,
                        onToggle: { Task { await model.toggleTaskComplete(rowID: task.id) } },
                        onEdit: { editingTask = task },
                        onDelete: { Task { await model.deleteTask(rowID: task.id) } }
                    )
                }
            }
        }
    }

    // MARK: - Backlog

    private var backlogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Backlog", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("\(model.backlogTasks.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange)
                    .clipShape(Capsule())
            }

            ForEach(model.backlogTasks, id: \.id) { task in
                TaskRowView(
                    row: task,
                    onToggle: { Task { await model.toggleTaskComplete(rowID: task.id) } },
                    onEdit: { editingTask = task },
                    onDelete: { Task { await model.deleteTask(rowID: task.id) } }
                )
            }
        }
    }
}

// MARK: - Session row

private struct SessionRowView: View {
    let row: TableRowRecord
    let onComplete: () -> Void

    private var isComplete: Bool { row.cells["status"] == "complete" }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(sessionColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.cells["title"] ?? "Untitled")
                    .font(.callout)
                    .strikethrough(isComplete)

                HStack(spacing: 6) {
                    if let start = row.cells["startTime"], !start.isEmpty {
                        let dur = Int(row.cells["duration"] ?? "0") ?? 0
                        let endStr = dur > 0 ? " - \(addMinutes(start, dur))" : ""
                        Text("\(start)\(endStr)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let subject = row.cells["subject"], !subject.isEmpty {
                        Text(subject)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            if !isComplete {
                Button("Done") { onComplete() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
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

    private func addMinutes(_ time: String, _ minutes: Int) -> String {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return time }
        let total = h * 60 + m + minutes
        return String(format: "%02d:%02d", (total / 60) % 24, total % 60)
    }
}

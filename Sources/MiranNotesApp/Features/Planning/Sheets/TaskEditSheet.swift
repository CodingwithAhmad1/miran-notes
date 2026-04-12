import SwiftUI
import MiranNotesCore

struct TaskEditSheet: View {
    @ObservedObject var model: PlanningModel
    let mode: Mode
    let onDismiss: () -> Void

    enum Mode {
        case create
        case edit(TableRowRecord)
    }

    @State private var title = ""
    @State private var type = "academics"
    @State private var subject = ""
    @State private var date = Date()
    @State private var time = ""
    @State private var duration = ""
    @State private var priority = "medium"
    @State private var project = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEdit ? "Edit Task" : "New Task")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                TextField("Title", text: $title)

                Picker("Type", selection: $type) {
                    ForEach(model.config.taskTypes, id: \.self) { t in
                        Text(t.capitalized).tag(t)
                    }
                }

                if type == "academics" {
                    Picker("Subject", selection: $subject) {
                        Text("None").tag("")
                        ForEach(model.config.subjects, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                }

                DatePicker("Date", selection: $date, displayedComponents: .date)

                TextField("Time (HH:MM)", text: $time)
                TextField("Duration (minutes)", text: $duration)

                Picker("Priority", selection: $priority) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }

                TextField("Project", text: $project)
            }
            .formStyle(.grouped)
            .padding(.bottom, 8)

            HStack {
                Spacer()
                Button(isEdit ? "Save" : "Add Task") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 380, minHeight: 400)
        .onAppear { populateFromMode() }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func populateFromMode() {
        if case .edit(let row) = mode {
            title = row.cells["title"] ?? ""
            type = row.cells["type"] ?? "academics"
            subject = row.cells["subject"] ?? ""
            if let d = row.cells["date"], let parsed = DatabaseDateParser.parseLoose(d) {
                date = parsed
            }
            time = row.cells["time"] ?? ""
            duration = row.cells["duration"] ?? ""
            priority = row.cells["priority"] ?? "medium"
            project = row.cells["project"] ?? ""
        } else {
            date = model.selectedDate
            priority = model.config.quickAddDefaults.defaultPriority
            type = model.config.quickAddDefaults.defaultType
        }
    }

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if case .edit(let row) = mode {
            var cells = row.cells
            cells["title"] = trimmed
            cells["type"] = type
            cells["subject"] = type == "academics" ? subject : ""
            cells["date"] = PlanningModel.dateString(date)
            cells["time"] = time
            cells["duration"] = duration
            cells["priority"] = priority
            cells["project"] = project
            await model.updateTask(rowID: row.id, cells: cells)
        } else {
            await model.quickAddTask(
                title: trimmed,
                type: type,
                subject: type == "academics" ? subject : nil,
                date: date,
                time: time.isEmpty ? nil : time,
                duration: Int(duration),
                priority: priority,
                project: project.isEmpty ? nil : project
            )
        }
        onDismiss()
    }
}

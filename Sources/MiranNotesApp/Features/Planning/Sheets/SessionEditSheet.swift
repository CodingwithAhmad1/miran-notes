import SwiftUI
import MiranNotesCore

struct SessionEditSheet: View {
    @ObservedObject var model: PlanningModel
    let mode: SessionMode
    let onDismiss: () -> Void

    enum SessionMode {
        case create(prefillDate: Date?)
        case edit(TableRowRecord)
    }

    @State private var title = ""
    @State private var type = "session"
    @State private var subject = ""
    @State private var topic = ""
    @State private var sessionType = "learning"
    @State private var date = Date()
    @State private var startTime = ""
    @State private var duration = ""
    @State private var objective = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEdit ? "Edit Session" : "New Session")
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
                    Text("Session").tag("session")
                    Text("Time Block").tag("block")
                    Text("Habit").tag("habit")
                    Text("Event").tag("event")
                }

                if type == "session" {
                    Picker("Subject", selection: $subject) {
                        Text("None").tag("")
                        ForEach(model.config.subjects, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }

                    TextField("Topic", text: $topic)

                    Picker("Session Type", selection: $sessionType) {
                        Text("Learning").tag("learning")
                        Text("Practice").tag("practice")
                    }
                }

                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Start Time (HH:MM)", text: $startTime)
                TextField("Duration (minutes)", text: $duration)
                TextField("Objective", text: $objective)
            }
            .formStyle(.grouped)
            .padding(.bottom, 8)

            HStack {
                Spacer()
                Button(isEdit ? "Save" : "Add Session") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 380, minHeight: 420)
        .onAppear { populateFromMode() }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func populateFromMode() {
        switch mode {
        case .create(let prefill):
            date = prefill ?? model.selectedDate
        case .edit(let row):
            title = row.cells["title"] ?? ""
            type = row.cells["type"] ?? "session"
            subject = row.cells["subject"] ?? ""
            topic = row.cells["topic"] ?? ""
            sessionType = row.cells["sessionType"] ?? "learning"
            if let d = row.cells["date"], let parsed = DatabaseDateParser.parseLoose(d) {
                date = parsed
            }
            startTime = row.cells["startTime"] ?? ""
            duration = row.cells["duration"] ?? ""
            objective = row.cells["objective"] ?? ""
        }
    }

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if case .edit(let row) = mode {
            var cells = row.cells
            cells["title"] = trimmed
            cells["type"] = type
            cells["subject"] = type == "session" ? subject : ""
            cells["topic"] = topic
            cells["sessionType"] = sessionType
            cells["date"] = PlanningModel.dateString(date)
            cells["startTime"] = startTime
            cells["duration"] = duration
            cells["objective"] = objective
            await model.updateTask(rowID: row.id, cells: cells)
        } else {
            await model.quickAddSession(
                title: trimmed,
                type: type,
                subject: type == "session" ? subject : nil,
                topic: topic.isEmpty ? nil : topic,
                sessionType: sessionType,
                date: date,
                startTime: startTime.isEmpty ? nil : startTime,
                duration: Int(duration),
                objective: objective.isEmpty ? nil : objective
            )
        }
        onDismiss()
    }
}

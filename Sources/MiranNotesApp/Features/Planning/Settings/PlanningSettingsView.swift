import SwiftUI
import MiranNotesCore

struct PlanningSettingsView: View {
    @ObservedObject var model: PlanningModel
    @State private var editableSubjects: [String] = []
    @State private var newSubject = ""
    @State private var showMigrationSheet = false
    @State private var migrationResult: String?
    @State private var exportPath: String?

    var body: some View {
        Form {
            subjectsSection
            colorSection
            quickAddSection
            exportSection
            migrationSection
        }
        .formStyle(.grouped)
        .navigationTitle("Planning Settings")
        .onAppear {
            editableSubjects = model.config.subjects
        }
    }

    // MARK: - Subjects

    private var subjectsSection: some View {
        Section("Subjects") {
            ForEach(editableSubjects, id: \.self) { subject in
                HStack {
                    Text(subject)
                    Spacer()
                    Button(role: .destructive) {
                        editableSubjects.removeAll { $0 == subject }
                        saveSubjects()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("New subject", text: $newSubject)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newSubject.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !editableSubjects.contains(trimmed) else { return }
                    editableSubjects.append(trimmed)
                    newSubject = ""
                    saveSubjects()
                }
                .disabled(newSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Colors

    private var colorSection: some View {
        Section("Color Schema") {
            ForEach(model.config.colorSchema.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: value) ?? .gray)
                        .frame(width: 24, height: 24)
                    Text(value)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Quick Add defaults

    private var quickAddSection: some View {
        Section("Quick Add Defaults") {
            HStack {
                Text("Default Priority")
                Spacer()
                Text(model.config.quickAddDefaults.defaultPriority.capitalized)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Default Type")
                Spacer()
                Text(model.config.quickAddDefaults.defaultType.capitalized)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section("Export") {
            Button("Export Tasks as CSV") {
                Task { await exportTasksCSV() }
            }
            Button("Export Sessions as CSV") {
                Task { await exportSessionsCSV() }
            }
            if let path = exportPath {
                Text("Exported to: \(path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Migration

    private var migrationSection: some View {
        Section("Zora Migration") {
            Text("Import data from a Zora Planning vault (.zora directory) into the Miran database layer.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Import from Zora Vault...") {
                showMigrationSheet = true
            }
            .sheet(isPresented: $showMigrationSheet) {
                ZoraMigrationSheet(model: model) { result in
                    migrationResult = result
                    showMigrationSheet = false
                }
            }

            if let result = migrationResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func saveSubjects() {
        Task {
            var config = model.config
            config.subjects = editableSubjects
            model.config = config
        }
    }

    private func exportTasksCSV() async {
        let schema = PlanningSchemas.tasksSchema()
        let headers = schema.columns.map(\.title).joined(separator: ",")
        var csv = headers + "\n"
        for row in model.allTasks {
            let values = schema.columns.map { col in
                let val = row.cells[col.id] ?? ""
                return val.contains(",") ? "\"\(val)\"" : val
            }
            csv += values.joined(separator: ",") + "\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-export.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        exportPath = url.path
    }

    private func exportSessionsCSV() async {
        let schema = PlanningSchemas.sessionsSchema()
        let headers = schema.columns.map(\.title).joined(separator: ",")
        var csv = headers + "\n"
        for row in model.allSessions {
            let values = schema.columns.map { col in
                let val = row.cells[col.id] ?? ""
                return val.contains(",") ? "\"\(val)\"" : val
            }
            csv += values.joined(separator: ",") + "\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-export.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        exportPath = url.path
    }
}

// MARK: - Color hex extension

private extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let rgb = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

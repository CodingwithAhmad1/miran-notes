import Foundation
import MiranNotesCore
import os.log

struct SubjectSessionMetric: Equatable {
    var planned: Int = 0
    var completed: Int = 0
}

/// Weekly review metrics aggregated from tasks and sessions databases.
struct WeeklyReviewMetrics: Equatable {
    var weekRange: DateInterval
    var sessionsPlanned: Int = 0
    var sessionsCompleted: Int = 0
    var sessionsMissed: Int = 0
    var tasksTotal: Int = 0
    var tasksCompleted: Int = 0
    var backlogSize: Int = 0
    var sessionsBySubject: [String: SubjectSessionMetric] = [:]
    var timeBySubject: [String: Int] = [:]

    var completionRate: Double {
        guard sessionsPlanned > 0 else { return 0 }
        return Double(sessionsCompleted) / Double(sessionsPlanned)
    }

    var taskCompletionRate: Double {
        guard tasksTotal > 0 else { return 0 }
        return Double(tasksCompleted) / Double(tasksTotal)
    }
}

/// Drives all planning features (dashboard, calendar, quick add) on top of ``DatabaseRepository``.
@MainActor
final class PlanningModel: ObservableObject {
    @Published var selectedDate: Date = PlanningModel.startOfDay(Date())
    @Published var todayTasks: [TableRowRecord] = []
    @Published var backlogTasks: [TableRowRecord] = []
    @Published var todaySessions: [TableRowRecord] = []
    @Published var allTasks: [TableRowRecord] = []
    @Published var allSessions: [TableRowRecord] = []
    @Published var isLoaded = false
    @Published var lastError: String?
    @Published var config: PlanningConfig = .default
    var onDataChanged: (() -> Void)?

    let _databaseRepo: DatabaseRepository
    private let configManager: PlanningConfigManager
    private var tasksDatabaseID: UUID?
    private var sessionsDatabaseID: UUID?

    init(databaseRepo: DatabaseRepository, configManager: PlanningConfigManager) {
        self._databaseRepo = databaseRepo
        self.configManager = configManager
    }

    // MARK: - Bootstrap

    /// Ensures the Tasks and Sessions databases exist, creating them if needed.
    func bootstrap() async {
        await configManager.load()
        config = await configManager.config

        do {
            let existing = try await _databaseRepo.listDatabases()

            if let tasks = existing.first(where: { $0.kind == .tasks }) {
                tasksDatabaseID = tasks.id
            } else {
                let record = try await _databaseRepo.createDatabase(
                    name: "Tasks",
                    kind: .tasks,
                    schema: PlanningSchemas.tasksSchema(),
                    views: [PlanningSchemas.tasksDefaultView(), PlanningSchemas.tasksCalendarView()]
                )
                tasksDatabaseID = record.id
            }

            if let sessions = existing.first(where: { $0.kind == .sessions }) {
                sessionsDatabaseID = sessions.id
            } else {
                let record = try await _databaseRepo.createDatabase(
                    name: "Sessions",
                    kind: .sessions,
                    schema: PlanningSchemas.sessionsSchema(),
                    views: [PlanningSchemas.sessionDefaultView(), PlanningSchemas.sessionCalendarView()]
                )
                sessionsDatabaseID = record.id
            }

            await refreshAll()
            isLoaded = true
        } catch {
            lastError = "Planning bootstrap failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Refresh

    func refreshAll() async {
        await refreshTasks()
        await refreshSessions()
        onDataChanged?()
    }

    func refreshTasks() async {
        guard let dbID = tasksDatabaseID else { return }
        do {
            let all = try await _databaseRepo.allRows(databaseID: dbID)
            allTasks = all
            let dateStr = Self.dateString(selectedDate)
            let todayStr = Self.dateString(Date())

            todayTasks = all.filter { row in
                row.cells["date"] == dateStr && row.cells["status"] != "complete"
            }.sorted { a, b in
                let ta = a.cells["time"] ?? ""
                let tb = b.cells["time"] ?? ""
                if !ta.isEmpty && !tb.isEmpty { return ta < tb }
                if !ta.isEmpty { return true }
                if !tb.isEmpty { return false }
                return prioritySortValue(a) > prioritySortValue(b)
            }

            backlogTasks = all.filter { row in
                guard let d = row.cells["date"], !d.isEmpty else { return false }
                return d < todayStr && row.cells["status"] != "complete"
            }.sorted { a, b in
                (a.cells["date"] ?? "") < (b.cells["date"] ?? "")
            }
        } catch {
            lastError = "Failed to load tasks: \(error.localizedDescription)"
        }
    }

    func refreshSessions() async {
        guard let dbID = sessionsDatabaseID else { return }
        do {
            let all = try await _databaseRepo.allRows(databaseID: dbID)
            allSessions = all
            let dateStr = Self.dateString(selectedDate)

            todaySessions = all.filter { row in
                row.cells["date"] == dateStr
            }.sorted { a, b in
                (a.cells["startTime"] ?? "") < (b.cells["startTime"] ?? "")
            }
        } catch {
            lastError = "Failed to load sessions: \(error.localizedDescription)"
        }
    }

    // MARK: - Quick Add

    func quickAddTask(
        title: String,
        type: String = "academics",
        subject: String? = nil,
        date: Date? = nil,
        time: String? = nil,
        duration: Int? = nil,
        priority: String? = nil,
        project: String? = nil,
        sourceNoteID: UUID? = nil,
        forcedRowID: UUID? = nil
    ) async {
        guard let dbID = tasksDatabaseID else { return }
        var cells: [String: String] = [
            "title": title,
            "type": type,
            "date": Self.dateString(date ?? selectedDate),
            "status": "open",
        ]
        if let subject { cells["subject"] = subject }
        if let time { cells["time"] = time }
        if let duration { cells["duration"] = String(duration) }
        if let priority { cells["priority"] = priority }
        if let project { cells["project"] = project }
        if let sourceNoteID { cells["linkedNote"] = sourceNoteID.uuidString }

        do {
            let doc = try await _databaseRepo.openDocument(id: dbID)
            try await doc.loadIfNeeded()
            let desiredRowID = forcedRowID ?? UUID()
            let existing = await doc.allRows()
            if existing.contains(where: { $0.id == desiredRowID }) {
                return
            }
            await doc.insertRow(TableRowRecord(id: desiredRowID, cells: cells))
            try await doc.flushToDisk()
            await refreshTasks()
            onDataChanged?()
        } catch {
            lastError = "Failed to add task: \(error.localizedDescription)"
        }
    }

    func quickAddSession(
        title: String,
        type: String = "session",
        subject: String? = nil,
        topic: String? = nil,
        sessionType: String? = nil,
        date: Date? = nil,
        startTime: String? = nil,
        duration: Int? = nil,
        objective: String? = nil,
        sourceNoteID: UUID? = nil,
        forcedRowID: UUID? = nil
    ) async {
        guard let dbID = sessionsDatabaseID else { return }
        var cells: [String: String] = [
            "title": title,
            "type": type,
            "date": Self.dateString(date ?? selectedDate),
            "status": "planned",
        ]
        if let subject { cells["subject"] = subject }
        if let topic { cells["topic"] = topic }
        if let sessionType { cells["sessionType"] = sessionType }
        if let startTime { cells["startTime"] = startTime }
        if let duration { cells["duration"] = String(duration) }
        if let objective { cells["objective"] = objective }
        if let sourceNoteID { cells["linkedNote"] = sourceNoteID.uuidString }

        do {
            let doc = try await _databaseRepo.openDocument(id: dbID)
            try await doc.loadIfNeeded()
            let desiredRowID = forcedRowID ?? UUID()
            let existing = await doc.allRows()
            if existing.contains(where: { $0.id == desiredRowID }) {
                return
            }
            await doc.insertRow(TableRowRecord(id: desiredRowID, cells: cells))
            try await doc.flushToDisk()
            await refreshSessions()
            onDataChanged?()
        } catch {
            lastError = "Failed to add session: \(error.localizedDescription)"
        }
    }

    // MARK: - Task actions

    func toggleTaskComplete(rowID: UUID) async {
        guard let dbID = tasksDatabaseID else { return }
        do {
            let doc = try await _databaseRepo.openDocument(id: dbID)
            let rows = await doc.allRows()
            guard let row = rows.first(where: { $0.id == rowID }) else { return }
            let newStatus = row.cells["status"] == "complete" ? "open" : "complete"
            await doc.updateCell(rowID: rowID, columnID: "status", value: newStatus)
            try await doc.flushToDisk()
            await refreshTasks()
            onDataChanged?()
        } catch {
            lastError = "Failed to update task: \(error.localizedDescription)"
        }
    }

    func updateTask(rowID: UUID, cells: [String: String]) async {
        guard let dbID = tasksDatabaseID else { return }
        do {
            let doc = try await _databaseRepo.openDocument(id: dbID)
            await doc.updateRow(id: rowID, cells: cells)
            try await doc.flushToDisk()
            await refreshTasks()
            onDataChanged?()
        } catch {
            lastError = "Failed to update task: \(error.localizedDescription)"
        }
    }

    func deleteTask(rowID: UUID) async {
        guard let dbID = tasksDatabaseID else { return }
        do {
            let doc = try await _databaseRepo.openDocument(id: dbID)
            await doc.deleteRow(id: rowID)
            try await doc.flushToDisk()
            await refreshTasks()
            onDataChanged?()
        } catch {
            lastError = "Failed to delete task: \(error.localizedDescription)"
        }
    }

    // MARK: - Session actions

    func updateSessionStatus(rowID: UUID, status: String) async {
        guard let dbID = sessionsDatabaseID else { return }
        do {
            let doc = try await _databaseRepo.openDocument(id: dbID)
            await doc.updateCell(rowID: rowID, columnID: "status", value: status)
            try await doc.flushToDisk()
            await refreshSessions()
            onDataChanged?()
        } catch {
            lastError = "Failed to update session: \(error.localizedDescription)"
        }
    }

    func updateSession(rowID: UUID, cells: [String: String]) async {
        guard let dbID = sessionsDatabaseID else { return }
        do {
            let doc = try await _databaseRepo.openDocument(id: dbID)
            await doc.updateRow(id: rowID, cells: cells)
            try await doc.flushToDisk()
            await refreshSessions()
            onDataChanged?()
        } catch {
            lastError = "Failed to update session: \(error.localizedDescription)"
        }
    }

    func deleteSession(rowID: UUID) async {
        guard let dbID = sessionsDatabaseID else { return }
        do {
            let doc = try await _databaseRepo.openDocument(id: dbID)
            await doc.deleteRow(id: rowID)
            try await doc.flushToDisk()
            await refreshSessions()
            onDataChanged?()
        } catch {
            lastError = "Failed to delete session: \(error.localizedDescription)"
        }
    }

    func taskDatabaseID() -> UUID? { tasksDatabaseID }
    func sessionsDatabaseIDValue() -> UUID? { sessionsDatabaseID }

    // MARK: - Date-range queries

    func tasksForDateRange(_ range: DateInterval) async -> [TableRowRecord] {
        let startStr = Self.dateString(range.start)
        let endStr = Self.dateString(range.end)
        return allTasks.filter { row in
            guard let d = row.cells["date"], !d.isEmpty else { return false }
            return d >= startStr && d <= endStr
        }
    }

    func sessionsForDateRange(_ range: DateInterval) async -> [TableRowRecord] {
        let startStr = Self.dateString(range.start)
        let endStr = Self.dateString(range.end)
        return allSessions.filter { row in
            guard let d = row.cells["date"], !d.isEmpty else { return false }
            return d >= startStr && d <= endStr
        }
    }

    // MARK: - Weekly review

    func weeklyReviewMetrics(weekOf: Date) async -> WeeklyReviewMetrics {
        let cal = Calendar.current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: weekOf) else {
            return WeeklyReviewMetrics(weekRange: DateInterval(start: weekOf, duration: 604_800))
        }

        let tasks = await tasksForDateRange(weekStart)
        let sessions = await sessionsForDateRange(weekStart)
        let todayStr = Self.dateString(Date())

        var metrics = WeeklyReviewMetrics(weekRange: weekStart)
        metrics.tasksTotal = tasks.count
        metrics.tasksCompleted = tasks.filter { $0.cells["status"] == "complete" }.count

        metrics.backlogSize = allTasks.filter { row in
            guard let d = row.cells["date"], !d.isEmpty else { return false }
            return d < todayStr && row.cells["status"] != "complete"
        }.count

        metrics.sessionsPlanned = sessions.count
        metrics.sessionsCompleted = sessions.filter { $0.cells["status"] == "complete" }.count
        metrics.sessionsMissed = sessions.filter { $0.cells["status"] == "missed" }.count

        var bySubject: [String: SubjectSessionMetric] = [:]
        var timeBySubject: [String: Int] = [:]
        for session in sessions {
            let subj = session.cells["subject"] ?? "Other"
            var entry = bySubject[subj] ?? SubjectSessionMetric()
            entry.planned += 1
            if session.cells["status"] == "complete" {
                entry.completed += 1
                let dur = Int(session.cells["duration"] ?? "0") ?? 0
                timeBySubject[subj, default: 0] += dur
            }
            bySubject[subj] = entry
        }
        metrics.sessionsBySubject = bySubject
        metrics.timeBySubject = timeBySubject

        return metrics
    }

    // MARK: - Date navigation

    func selectDate(_ date: Date) async {
        selectedDate = Self.startOfDay(date)
        await refreshAll()
    }

    func navigateDay(_ offset: Int) async {
        guard let next = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        await selectDate(next)
    }

    // MARK: - Helpers

    private func prioritySortValue(_ row: TableRowRecord) -> Int {
        switch row.cells["priority"] {
        case "high": return 3
        case "medium": return 2
        case "low": return 1
        default: return 0
        }
    }

    static func dateString(_ date: Date) -> String {
        DatabaseDateParser.formatLoose(date)
    }

    static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}

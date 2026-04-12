import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

@MainActor
final class PlanningModelTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranPlanning-\(UUID().uuidString)", isDirectory: true)
    }

    private func ensureVault(_ url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.createDirectory(at: VaultPaths.miranDirectory(vaultURL: url), withIntermediateDirectories: true)
    }

    private func makeModel(_ vault: URL) -> PlanningModel {
        let dbRepo = DatabaseRepository(vaultURL: vault)
        let configManager = PlanningConfigManager(vaultURL: vault)
        return PlanningModel(databaseRepo: dbRepo, configManager: configManager)
    }

    // MARK: - Bootstrap

    func testBootstrapCreatesDatabases() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()

        XCTAssertTrue(model.isLoaded)
        XCTAssertNil(model.lastError)

        let dbRepo = DatabaseRepository(vaultURL: vault)
        let dbs = try await dbRepo.listDatabases()
        XCTAssertEqual(dbs.count, 2)
        XCTAssertTrue(dbs.contains(where: { $0.kind == .tasks }))
        XCTAssertTrue(dbs.contains(where: { $0.kind == .sessions }))
    }

    func testBootstrapIdempotent() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()
        await model.bootstrap()

        let dbRepo = DatabaseRepository(vaultURL: vault)
        let dbs = try await dbRepo.listDatabases()
        XCTAssertEqual(dbs.count, 2, "Second bootstrap should not duplicate databases")
    }

    // MARK: - Quick Add

    func testQuickAddTaskAppearsInTodayTasks() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()

        await model.quickAddTask(title: "Buy milk", type: "personal", date: model.selectedDate, priority: "high")
        XCTAssertEqual(model.todayTasks.count, 1)
        XCTAssertEqual(model.todayTasks.first?.cells["title"], "Buy milk")
        XCTAssertEqual(model.todayTasks.first?.cells["status"], "open")
    }

    func testQuickAddTaskFromNoteContextSetsLinkedNote() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()
        let noteID = UUID()

        await model.quickAddTask(
            title: "Linked task",
            date: model.selectedDate,
            sourceNoteID: noteID
        )

        let row = try XCTUnwrap(model.todayTasks.first(where: { $0.cells["title"] == "Linked task" }))
        XCTAssertEqual(row.cells["linkedNote"], noteID.uuidString)
    }

    func testQuickAddSessionAppearsInTodaySessions() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()

        await model.quickAddSession(
            title: "Integration Practice",
            type: "session",
            subject: "MathFM",
            date: model.selectedDate,
            startTime: "09:00",
            duration: 120
        )
        XCTAssertEqual(model.todaySessions.count, 1)
        XCTAssertEqual(model.todaySessions.first?.cells["subject"], "MathFM")
    }

    // MARK: - Toggle complete

    func testToggleTaskCompleteRemovesFromToday() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()

        await model.quickAddTask(title: "Test task", date: model.selectedDate)
        XCTAssertEqual(model.todayTasks.count, 1)

        let rowID = try XCTUnwrap(model.todayTasks.first?.id)
        await model.toggleTaskComplete(rowID: rowID)
        XCTAssertEqual(model.todayTasks.count, 0, "Completed task should not appear in today's open list")
    }

    func testToggleTaskCompleteTogglesBack() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()

        await model.quickAddTask(title: "Toggle test", date: model.selectedDate)
        let rowID = try XCTUnwrap(model.todayTasks.first?.id)

        await model.toggleTaskComplete(rowID: rowID)
        XCTAssertEqual(model.todayTasks.count, 0)

        await model.toggleTaskComplete(rowID: rowID)
        XCTAssertEqual(model.todayTasks.count, 1)
    }

    // MARK: - Backlog

    func testPastIncompletTasksAppearInBacklog() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        await model.quickAddTask(title: "Overdue task", date: yesterday)

        await model.refreshTasks()
        XCTAssertTrue(model.backlogTasks.contains(where: { $0.cells["title"] == "Overdue task" }))
    }

    // MARK: - Date navigation

    func testNavigateDayChangesSelectedDate() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()

        let before = model.selectedDate
        await model.navigateDay(1)
        let after = model.selectedDate

        let diff = Calendar.current.dateComponents([.day], from: before, to: after).day
        XCTAssertEqual(diff, 1)
    }

    // MARK: - Weekly review

    func testWeeklyReviewMetrics() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()

        let today = model.selectedDate
        await model.quickAddTask(title: "Task 1", date: today)
        await model.quickAddTask(title: "Task 2", date: today)
        await model.quickAddSession(title: "Session 1", subject: "MathFM", date: today, duration: 60)
        await model.quickAddSession(title: "Session 2", subject: "Economics", date: today, duration: 90)

        let rowID = try XCTUnwrap(model.todayTasks.first?.id)
        await model.toggleTaskComplete(rowID: rowID)

        await model.updateSessionStatus(rowID: model.todaySessions.first!.id, status: "complete")

        let metrics = await model.weeklyReviewMetrics(weekOf: today)
        XCTAssertEqual(metrics.tasksTotal, 2)
        XCTAssertEqual(metrics.tasksCompleted, 1)
        XCTAssertEqual(metrics.sessionsPlanned, 2)
        XCTAssertEqual(metrics.sessionsCompleted, 1)
        XCTAssertTrue(metrics.sessionsBySubject.keys.contains("MathFM"))
    }

    // MARK: - Delete

    func testDeleteTask() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()

        await model.quickAddTask(title: "To delete", date: model.selectedDate)
        XCTAssertEqual(model.todayTasks.count, 1)

        let rowID = try XCTUnwrap(model.todayTasks.first?.id)
        await model.deleteTask(rowID: rowID)
        XCTAssertEqual(model.todayTasks.count, 0)
    }

    func testDeleteSession() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()

        await model.quickAddSession(title: "To delete", date: model.selectedDate)
        XCTAssertEqual(model.todaySessions.count, 1)

        let rowID = try XCTUnwrap(model.todaySessions.first?.id)
        await model.deleteSession(rowID: rowID)
        XCTAssertEqual(model.todaySessions.count, 0)
    }

    // MARK: - Persistence round-trip

    func testDataPersistsAcrossModels() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)

        let model1 = makeModel(vault)
        await model1.bootstrap()
        await model1.quickAddTask(title: "Persistent task", date: model1.selectedDate)

        let model2 = makeModel(vault)
        await model2.bootstrap()
        await model2.selectDate(model1.selectedDate)
        XCTAssertEqual(model2.todayTasks.count, 1)
        XCTAssertEqual(model2.todayTasks.first?.cells["title"], "Persistent task")
    }

    // MARK: - Config

    func testDefaultConfigLoaded() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let model = makeModel(vault)
        await model.bootstrap()

        XCTAssertEqual(model.config.subjects, ["MathFM", "Economics", "English"])
        XCTAssertEqual(model.config.taskTypes, ["academics", "personal", "admin"])
    }
}

import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class DatabaseRepositoryTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranDB-\(UUID().uuidString)", isDirectory: true)
    }

    private func ensureVault(_ url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.createDirectory(at: VaultPaths.miranDirectory(vaultURL: url), withIntermediateDirectories: true)
    }

    // MARK: - Registry lifecycle

    func testCreateAndListDatabases() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        let record = try await repo.createDatabase(name: "Tasks", kind: .tasks, schema: DatabaseSchema(columns: [
            DatabaseColumnDefinition(id: "title", title: "Title", type: .string, required: true),
            DatabaseColumnDefinition(id: "status", title: "Status", type: .select, options: ["open", "complete"]),
        ]))

        let all = try await repo.listDatabases()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Tasks")
        XCTAssertEqual(all.first?.kind, .tasks)
        XCTAssertEqual(all.first?.id, record.id)

        let schemaURL = VaultPaths.databaseSchemaURL(vaultURL: vault, databaseID: record.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: schemaURL.path))

        let rowsURL = VaultPaths.databaseRowsURL(vaultURL: vault, databaseID: record.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rowsURL.path))
    }

    func testDeleteDatabaseRemovesFilesAndRegistry() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        let record = try await repo.createDatabase(name: "Temp", kind: .general)
        let beforeCount = try await repo.listDatabases().count
        XCTAssertEqual(beforeCount, 1)

        try await repo.deleteDatabase(id: record.id)
        let afterCount = try await repo.listDatabases().count
        XCTAssertEqual(afterCount, 0)

        let dbDir = VaultPaths.databaseDirectory(vaultURL: vault, databaseID: record.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbDir.path))
    }

    func testDuplicateDatabaseNameThrows() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        _ = try await repo.createDatabase(name: "Tasks", kind: .tasks)
        do {
            _ = try await repo.createDatabase(name: "Tasks", kind: .tasks)
            XCTFail("Expected error for duplicate database")
        } catch {
            XCTAssertTrue(error is DatabaseRepositoryError)
        }
    }

    func testDeleteNonexistentDatabaseThrows() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        do {
            try await repo.deleteDatabase(id: UUID())
            XCTFail("Expected error for missing database")
        } catch {
            XCTAssertTrue(error is DatabaseRepositoryError)
        }
    }

    // MARK: - Row operations

    func testInsertAndQueryRows() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        let schema = DatabaseSchema(columns: [
            DatabaseColumnDefinition(id: "title", title: "Title", type: .string),
            DatabaseColumnDefinition(id: "priority", title: "Priority", type: .select, options: ["low", "medium", "high"]),
        ])
        let record = try await repo.createDatabase(name: "Tasks", kind: .tasks, schema: schema)

        let doc = try await repo.openDocument(id: record.id)
        try await doc.loadIfNeeded()
        await doc.insertRow(TableRowRecord(cells: ["title": "Buy groceries", "priority": "high"]))
        await doc.insertRow(TableRowRecord(cells: ["title": "Read book", "priority": "low"]))
        try await doc.flushToDisk()

        let allView = DatabaseViewConfig(name: "All")
        let rows = await doc.filteredRows(view: allView)
        XCTAssertEqual(rows.count, 2)
    }

    func testFilteredRowsWithEqualsFilter() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        let schema = DatabaseSchema(columns: [
            DatabaseColumnDefinition(id: "title", title: "Title"),
            DatabaseColumnDefinition(id: "status", title: "Status", type: .select, options: ["open", "complete"]),
        ])
        let record = try await repo.createDatabase(name: "DB", schema: schema)
        let doc = try await repo.openDocument(id: record.id)
        try await doc.loadIfNeeded()

        await doc.insertRow(TableRowRecord(cells: ["title": "A", "status": "open"]))
        await doc.insertRow(TableRowRecord(cells: ["title": "B", "status": "complete"]))
        await doc.insertRow(TableRowRecord(cells: ["title": "C", "status": "open"]))

        let view = DatabaseViewConfig(
            name: "Open",
            filters: [DatabaseFilter(columnID: "status", op: .equals, value: "open")]
        )
        let filtered = await doc.filteredRows(view: view)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.cells["status"] == "open" })
    }

    func testSortedRows() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        let schema = DatabaseSchema(columns: [
            DatabaseColumnDefinition(id: "name", title: "Name"),
            DatabaseColumnDefinition(id: "priority", title: "Priority", type: .number),
        ])
        let record = try await repo.createDatabase(name: "Sorted", schema: schema)
        let doc = try await repo.openDocument(id: record.id)
        try await doc.loadIfNeeded()

        await doc.insertRow(TableRowRecord(cells: ["name": "C", "priority": "3"]))
        await doc.insertRow(TableRowRecord(cells: ["name": "A", "priority": "1"]))
        await doc.insertRow(TableRowRecord(cells: ["name": "B", "priority": "2"]))

        let view = DatabaseViewConfig(
            name: "By Priority",
            sortKeys: [DatabaseSortKey(columnID: "priority", ascending: true)]
        )
        let sorted = await doc.filteredRows(view: view)
        XCTAssertEqual(sorted.map { $0.cells["name"] ?? "" }, ["A", "B", "C"])
    }

    // MARK: - Persistence round-trip

    func testFlushAndReloadPreservesData() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        let schema = DatabaseSchema(columns: [
            DatabaseColumnDefinition(id: "title", title: "Title"),
        ])
        let record = try await repo.createDatabase(name: "Persist", schema: schema)

        let doc = try await repo.openDocument(id: record.id)
        try await doc.loadIfNeeded()
        let row = TableRowRecord(cells: ["title": "Test row"])
        await doc.insertRow(row)
        try await doc.flushToDisk()

        let doc2 = DatabaseDocument(vaultURL: vault, databaseID: record.id)
        try await doc2.loadIfNeeded()
        let rows = await doc2.allRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.cells["title"], "Test row")
    }

    func testRegistryPersistsAcrossInstances() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)

        let repo1 = DatabaseRepository(vaultURL: vault)
        _ = try await repo1.createDatabase(name: "Durable", kind: .general)

        let repo2 = DatabaseRepository(vaultURL: vault)
        let dbs = try await repo2.listDatabases()
        XCTAssertEqual(dbs.count, 1)
        XCTAssertEqual(dbs.first?.name, "Durable")
    }

    // MARK: - Schema operations

    func testAddAndRemoveColumn() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        let schema = DatabaseSchema(columns: [
            DatabaseColumnDefinition(id: "title", title: "Title"),
        ])
        let record = try await repo.createDatabase(name: "Schema", schema: schema)
        let doc = try await repo.openDocument(id: record.id)
        try await doc.loadIfNeeded()

        await doc.insertRow(TableRowRecord(cells: ["title": "Row 1", "extra": "val"]))

        await doc.addColumn(DatabaseColumnDefinition(id: "extra", title: "Extra", type: .string))
        let afterAdd = await doc.schema
        XCTAssertEqual(afterAdd.columns.count, 2)

        await doc.removeColumn(id: "extra")
        let afterRemove = await doc.schema
        XCTAssertEqual(afterRemove.columns.count, 1)

        let rows = await doc.allRows()
        XCTAssertNil(rows.first?.cells["extra"], "Column removal should strip cell data")
    }

    // MARK: - View operations

    func testAddAndQueryView() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        let record = try await repo.createDatabase(name: "Views", schema: DatabaseSchema(columns: [
            DatabaseColumnDefinition(id: "title", title: "Title"),
        ]))

        let doc = try await repo.openDocument(id: record.id)
        try await doc.loadIfNeeded()

        let view = DatabaseViewConfig(name: "Calendar", layout: .calendar, calendarDateColumnID: "date")
        await doc.addView(view)
        try await doc.flushToDisk()

        let doc2 = DatabaseDocument(vaultURL: vault, databaseID: record.id)
        try await doc2.loadIfNeeded()
        let views = await doc2.views
        XCTAssertEqual(views.count, 1)
        XCTAssertEqual(views.first?.name, "Calendar")
        XCTAssertEqual(views.first?.layout, .calendar)
    }

    // MARK: - Cell update with type validation

    func testUpdateCellRejectsInvalidType() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        let schema = DatabaseSchema(columns: [
            DatabaseColumnDefinition(id: "count", title: "Count", type: .number),
        ])
        let record = try await repo.createDatabase(name: "Typed", schema: schema)
        let doc = try await repo.openDocument(id: record.id)
        try await doc.loadIfNeeded()

        let row = TableRowRecord(cells: ["count": "42"])
        await doc.insertRow(row)
        await doc.updateCell(rowID: row.id, columnID: "count", value: "not-a-number")

        let rows = await doc.allRows()
        XCTAssertEqual(rows.first?.cells["count"], "42", "Invalid number should be rejected")
    }

    // MARK: - Delete row

    func testDeleteRow() async throws {
        let vault = try tempVaultURL()
        try ensureVault(vault)
        let repo = DatabaseRepository(vaultURL: vault)

        let record = try await repo.createDatabase(name: "Del")
        let doc = try await repo.openDocument(id: record.id)
        try await doc.loadIfNeeded()

        let row = TableRowRecord(cells: ["a": "1"])
        await doc.insertRow(row)
        let countAfterInsert = await doc.allRows().count
        XCTAssertEqual(countAfterInsert, 1)

        await doc.deleteRow(id: row.id)
        let countAfterDelete = await doc.allRows().count
        XCTAssertEqual(countAfterDelete, 0)
    }

    // MARK: - DatabaseColumnType validation

    func testDatabaseColumnTypeAccepts() {
        XCTAssertTrue(DatabaseColumnType.string.accepts("anything"))
        XCTAssertTrue(DatabaseColumnType.number.accepts("42"))
        XCTAssertTrue(DatabaseColumnType.number.accepts("3.14"))
        XCTAssertFalse(DatabaseColumnType.number.accepts("abc"))
        XCTAssertTrue(DatabaseColumnType.number.accepts(""))
        XCTAssertTrue(DatabaseColumnType.boolean.accepts("true"))
        XCTAssertTrue(DatabaseColumnType.boolean.accepts("false"))
        XCTAssertFalse(DatabaseColumnType.boolean.accepts("maybe"))
        XCTAssertTrue(DatabaseColumnType.date.accepts("2026-04-12"))
        XCTAssertTrue(DatabaseColumnType.duration.accepts("90"))
        XCTAssertFalse(DatabaseColumnType.duration.accepts("1h"))
        XCTAssertTrue(DatabaseColumnType.noteLink.accepts(UUID().uuidString))
        XCTAssertFalse(DatabaseColumnType.noteLink.accepts("not-a-uuid"))
    }

    // MARK: - LinkTarget new cases

    func testLinkTargetDatabaseCodableRoundTrip() throws {
        let dbID = UUID()
        let target: LinkTarget = .database(databaseID: dbID)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(LinkTarget.self, from: data)
        XCTAssertEqual(decoded, target)
    }

    func testLinkTargetDatabaseRowCodableRoundTrip() throws {
        let dbID = UUID()
        let rowID = UUID()
        let target: LinkTarget = .databaseRow(databaseID: dbID, rowID: rowID)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(LinkTarget.self, from: data)
        XCTAssertEqual(decoded, target)
    }
}

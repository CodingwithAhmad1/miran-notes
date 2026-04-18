import Foundation
import XCTest

@testable import MiranNotesApp

final class VaultTodaysTasksStoreTests: XCTestCase {
    func testDayFileRoundTripPreservesOrderAndFields() throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let day = VaultTasksCalendarDay(validatedStorageKey: "2026-04-17")
        let id1 = UUID()
        let id2 = UUID()
        let rows: [VaultTodaysTaskRow] = [
            VaultTodaysTaskRow(id: id1, lines: ["First"], isDone: true),
            VaultTodaysTaskRow(id: id2, lines: ["Second"], isDone: false),
        ]
        try VaultTodaysTasksDayStore.save(day: day, items: rows, vaultURL: vault)
        let loaded = VaultTodaysTasksDayStore.load(day: day, vaultURL: vault)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, id1)
        XCTAssertEqual(loaded[0].lines, ["First"])
        XCTAssertTrue(loaded[0].isDone)
        XCTAssertEqual(loaded[1].id, id2)
        XCTAssertEqual(loaded[1].lines, ["Second"])
        XCTAssertFalse(loaded[1].isDone)
    }

    func testDayFileRoundTripPreservesMultipleLines() throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let day = VaultTasksCalendarDay(validatedStorageKey: "2026-04-17")
        let id1 = UUID()
        let rows: [VaultTodaysTaskRow] = [
            VaultTodaysTaskRow(id: id1, lines: ["Buy milk", "2%", "before noon"], isDone: false),
        ]
        try VaultTodaysTasksDayStore.save(day: day, items: rows, vaultURL: vault)
        let loaded = VaultTodaysTasksDayStore.load(day: day, vaultURL: vault)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].lines, ["Buy milk", "2%", "before noon"])
    }

    func testDayFileSchemaVersion1WithTitleOnlyStillLoads() throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let day = VaultTasksCalendarDay(validatedStorageKey: "2026-04-17")
        let dir = VaultPaths.todaysTasksDaysDirectory(vaultURL: vault)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let noteID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
        let payload = """
        {"schemaVersion":1,"items":[{"id":"\(noteID.uuidString)","title":"Old format","isDone":true}]}
        """
        try Data(payload.utf8).write(to: VaultPaths.todaysTasksDayFileURL(vaultURL: vault, dayStorageKey: day.storageKey))
        let loaded = VaultTodaysTasksDayStore.load(day: day, vaultURL: vault)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].lines, ["Old format"])
        XCTAssertTrue(loaded[0].isDone)
    }

    func testDayFileUnknownSchemaVersionYieldsEmpty() throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let day = VaultTasksCalendarDay(validatedStorageKey: "2026-04-17")
        let dir = VaultPaths.todaysTasksDaysDirectory(vaultURL: vault)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = #"{"schemaVersion":999,"items":[]}"#
        try Data(payload.utf8).write(to: VaultPaths.todaysTasksDayFileURL(vaultURL: vault, dayStorageKey: day.storageKey))
        let loaded = VaultTodaysTasksDayStore.load(day: day, vaultURL: vault)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testIndexRoundTripSortsAndUniques() throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let d1 = VaultTasksCalendarDay(validatedStorageKey: "2026-04-02")
        let d2 = VaultTasksCalendarDay(validatedStorageKey: "2026-04-01")
        try VaultTodaysTasksIndexStore.saveSortedDays([d1, d2, d1], vaultURL: vault)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let loaded = try VaultTodaysTasksIndexStore.loadOrBootstrap(vaultURL: vault, calendar: cal)
        XCTAssertEqual(loaded, [d2, d1])
    }

    func testLegacySingleFileMigratesIntoTodayPage() throws {
        let vault = try VaultTestSupport.makeEmptyVaultDirectory()
        let miran = VaultPaths.miranDirectory(vaultURL: vault)
        try FileManager.default.createDirectory(at: miran, withIntermediateDirectories: true)
        let noteID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
        let legacy = """
        {"schemaVersion":1,"items":[{"id":"\(noteID.uuidString)","title":"Legacy task","isDone":false}]}
        """
        try Data(legacy.utf8).write(to: VaultPaths.todaysTasksURL(vaultURL: vault))

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let known = try VaultTodaysTasksIndexStore.loadOrBootstrap(vaultURL: vault, calendar: cal)
        let today = VaultTasksCalendarDay.today(calendar: cal)
        XCTAssertTrue(known.contains(today))
        let items = VaultTodaysTasksDayStore.load(day: today, vaultURL: vault)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].lines, ["Legacy task"])
        XCTAssertEqual(items[0].id, noteID)
    }
}

import Foundation
import MiranNotesCore
import XCTest

@testable import MiranNotesApp

final class TaskBlocksAndRolloverTests: XCTestCase {
    private func block(_ id: String, _ type: BlockType, _ start: Int, _ length: Int, isDone: Bool? = nil) -> Block {
        Block(id: id, type: type, range: TextRange(start: start, length: length), level: nil, icon: nil, isDone: isDone)
    }

    // MARK: - Engine

    func testChangeBlockTypeToTaskInitializesUnchecked() {
        var metadata = NoteMetadata.empty
        metadata.blocks = [block("b0", .paragraph, 0, 4)]
        var doc = NoteDocument(text: "todo", metadata: metadata)
        doc = EditCommandEngine.apply(.changeBlockType(blockID: "b0", type: .taskItem, headingLevel: nil), to: doc)
        XCTAssertEqual(doc.metadata.blocks[0].type, .taskItem)
        XCTAssertEqual(doc.metadata.blocks[0].isDone, false)

        doc = EditCommandEngine.apply(.setBlockDone(blockID: "b0", isDone: true), to: doc)
        XCTAssertEqual(doc.metadata.blocks[0].isDone, true)

        // Converting away clears the checkbox state.
        doc = EditCommandEngine.apply(.changeBlockType(blockID: "b0", type: .paragraph, headingLevel: nil), to: doc)
        XCTAssertNil(doc.metadata.blocks[0].isDone)
    }

    func testSetBlockDoneIgnoresNonTaskBlocks() {
        var metadata = NoteMetadata.empty
        metadata.blocks = [block("b0", .paragraph, 0, 2)]
        var doc = NoteDocument(text: "hi", metadata: metadata)
        doc = EditCommandEngine.apply(.setBlockDone(blockID: "b0", isDone: true), to: doc)
        XCTAssertNil(doc.metadata.blocks[0].isDone)
    }

    func testSplittingDoneTaskCreatesUncheckedContinuation() {
        let text = "one\ntwo"
        var metadata = NoteMetadata.empty
        metadata.blocks = [block("b0", .taskItem, 0, text.utf16.count, isDone: true)]
        var doc = NoteDocument(text: text, metadata: metadata)
        doc = EditCommandEngine.apply(.splitBlock(blockID: "b0", atOffset: 4), to: doc)
        XCTAssertEqual(doc.metadata.blocks.count, 2)
        XCTAssertEqual(doc.metadata.blocks[0].isDone, true)
        XCTAssertEqual(doc.metadata.blocks[1].type, .taskItem)
        XCTAssertEqual(doc.metadata.blocks[1].isDone, false)
    }

    func testTaskBlockSidecarRoundTripAndLegacyDecode() throws {
        var metadata = NoteMetadata.empty
        metadata.blocks = [block("b0", .taskItem, 0, 4, isDone: true)]
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(NoteMetadata.self, from: data)
        XCTAssertEqual(decoded.blocks[0].isDone, true)

        // Older sidecars have no isDone key.
        let legacy = """
        {"schemaVersion":2,"noteID":"\(UUID().uuidString)","blocks":[{"id":"b0","type":"paragraph","range":{"start":0,"length":2}}],"spans":[],"links":[],"properties":{}}
        """
        let legacyDecoded = try JSONDecoder().decode(NoteMetadata.self, from: Data(legacy.utf8))
        XCTAssertNil(legacyDecoded.blocks[0].isDone)
    }

    func testSlashTaskCommandRegistered() async throws {
        await MainActor.run {
            SlashCommandRegistry.registerBuiltins()
            let items = SlashCommandRegistry.catalogItems()
            let task = items.first { $0.id == "task" }
            XCTAssertNotNil(task)
            XCTAssertTrue(task?.aliases.contains("todo") ?? false)
        }
    }

    // MARK: - Row schema

    func testTaskRowSourceFieldsRoundTrip() throws {
        let noteID = UUID()
        let row = VaultTodaysTaskRow(
            id: UUID(),
            lines: ["linked task", "detail"],
            isDone: false,
            rolledFromDayKey: "2026-08-19",
            sourceNoteID: noteID,
            sourceBlockID: "blk-1"
        )
        let data = try JSONEncoder().encode(row)
        let decoded = try JSONDecoder().decode(VaultTodaysTaskRow.self, from: data)
        XCTAssertEqual(decoded, row)
        XCTAssertEqual(decoded.rolledFromDayKey, "2026-08-19")
        XCTAssertEqual(decoded.sourceNoteID, noteID)
        XCTAssertEqual(decoded.sourceBlockID, "blk-1")
    }

    func testLegacyRowWithoutSourceFieldsDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","lines":["old task"],"isDone":true}
        """
        let decoded = try JSONDecoder().decode(VaultTodaysTaskRow.self, from: Data(json.utf8))
        XCTAssertNil(decoded.rolledFromDayKey)
        XCTAssertNil(decoded.sourceNoteID)
        XCTAssertNil(decoded.sourceBlockID)
    }
}

@MainActor
final class TodaysTasksNavigationAndRolloverTests: XCTestCase {
    private func tempVaultURL() throws -> URL {
        try VaultTestSupport.makeEmptyVaultDirectory()
    }

    private func makeModel() throws -> (AppModel, URL) {
        let vault = try tempVaultURL()
        let repo = NoteRepository(vaultURL: vault)
        let model = AppModel(repository: repo)
        return (model, vault)
    }

    func testGoToArbitraryDayShowsEmptyListAndIndexesOnContent() async throws {
        let (model, vault) = try makeModel()
        try await model.repository.ensureVault()
        try model.loadVaultTodaysTasksStateAfterPreferences()

        let calendar = AppModel.vaultTasksCalendar()
        let pastDate = calendar.date(byAdding: .day, value: -10, to: Date())!
        let pastDay = VaultTasksCalendarDay.today(calendar: calendar, referenceDate: pastDate)

        model.goToTodaysTasksDay(pastDay)
        XCTAssertEqual(model.todaysTasksSelectedDay, pastDay)
        XCTAssertTrue(model.todaysTasksItems.isEmpty)
        XCTAssertFalse(model.todaysTasksKnownDays.contains(pastDay), "empty days are not indexed")

        _ = model.addTodaysTaskRow()
        model.setTodaysTaskLine(taskID: model.todaysTasksItems[0].id, lineIndex: 0, text: "past chore")
        model.persistTodaysTasksImmediatelyForSelectedDay()
        model.registerTodaysTasksDayInIndexIfNeeded(pastDay, hasItems: true)
        XCTAssertTrue(model.todaysTasksKnownDays.contains(pastDay))
        XCTAssertEqual(VaultTodaysTasksDayStore.load(day: pastDay, vaultURL: vault).count, 1)
    }

    func testRolloverCopiesOnlyUnfinishedAndTagsOrigin() async throws {
        let (model, vault) = try makeModel()
        try await model.repository.ensureVault()
        try model.loadVaultTodaysTasksStateAfterPreferences()

        let calendar = AppModel.vaultTasksCalendar()
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: Date())!
        let yesterday = VaultTasksCalendarDay.today(calendar: calendar, referenceDate: yesterdayDate)
        try VaultTodaysTasksDayStore.save(
            day: yesterday,
            items: [
                VaultTodaysTaskRow(id: UUID(), lines: ["unfinished"], isDone: false),
                VaultTodaysTaskRow(id: UUID(), lines: ["done already"], isDone: true)
            ],
            vaultURL: vault
        )
        model.todaysTasksKnownDays = try VaultTodaysTasksIndexStore.insertDayIfMissing(
            yesterday, vaultURL: vault, existing: model.todaysTasksKnownDays
        )

        XCTAssertEqual(model.todaysTasksRolloverSourceDay, yesterday)
        model.rollOverIncompleteTasksIntoSelectedDay()

        XCTAssertEqual(model.todaysTasksItems.count, 1)
        XCTAssertEqual(model.todaysTasksItems[0].lines, ["unfinished"])
        XCTAssertFalse(model.todaysTasksItems[0].isDone)
        XCTAssertEqual(model.todaysTasksItems[0].rolledFromDayKey, yesterday.storageKey)

        // Rolling again is a no-op (dedupe by primary line).
        model.rollOverIncompleteTasksIntoSelectedDay()
        XCTAssertEqual(model.todaysTasksItems.count, 1)
    }

    func testAddNoteBlockToTodaysTasksLinksRow() async throws {
        let (model, _) = try makeModel()
        try await model.repository.ensureVault()
        try model.loadVaultTodaysTasksStateAfterPreferences()

        let noteID = UUID()
        model.addNoteBlockToTodaysTasks(noteID: noteID, blockID: "blk-9", text: "  write report \n")
        XCTAssertEqual(model.todaysTasksItems.count, 1)
        XCTAssertEqual(model.todaysTasksItems[0].lines, ["write report"])
        XCTAssertEqual(model.todaysTasksItems[0].sourceNoteID, noteID)
        XCTAssertEqual(model.todaysTasksItems[0].sourceBlockID, "blk-9")
    }
}

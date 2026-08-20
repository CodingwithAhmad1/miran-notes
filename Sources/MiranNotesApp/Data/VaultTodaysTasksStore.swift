import Foundation

struct VaultTodaysTaskRow: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// Primary line is index 0 (beside checkbox); further indices are detail lines.
    var lines: [String]
    /// Session-stable keys for SwiftUI lists; not persisted (regenerated on decode).
    var lineIDs: [UUID]
    var isDone: Bool
    /// Storage key of the day this row was rolled over from (additive; nil for rows created in place).
    var rolledFromDayKey: String?
    /// Origin note when the row was created from a note's task block ("Add to Today's Tasks").
    var sourceNoteID: UUID?
    /// Origin block within ``sourceNoteID`` (advisory; the block may no longer exist).
    var sourceBlockID: String?

    init(
        id: UUID,
        lines: [String],
        isDone: Bool,
        rolledFromDayKey: String? = nil,
        sourceNoteID: UUID? = nil,
        sourceBlockID: String? = nil
    ) {
        self.id = id
        self.lines = lines.isEmpty ? [""] : lines
        self.lineIDs = self.lines.map { _ in UUID() }
        self.isDone = isDone
        self.rolledFromDayKey = rolledFromDayKey
        self.sourceNoteID = sourceNoteID
        self.sourceBlockID = sourceBlockID
    }

    init(id: UUID, title: String, isDone: Bool) {
        self.init(id: id, lines: [title], isDone: isDone)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case lines
        case isDone
        case rolledFromDayKey
        case sourceNoteID
        case sourceBlockID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        isDone = try c.decode(Bool.self, forKey: .isDone)
        if let decodedLines = try c.decodeIfPresent([String].self, forKey: .lines), !decodedLines.isEmpty {
            lines = decodedLines
        } else if let title = try c.decodeIfPresent(String.self, forKey: .title) {
            lines = [title]
        } else {
            lines = [""]
        }
        lineIDs = lines.map { _ in UUID() }
        rolledFromDayKey = try c.decodeIfPresent(String.self, forKey: .rolledFromDayKey)
        sourceNoteID = try c.decodeIfPresent(UUID.self, forKey: .sourceNoteID)
        sourceBlockID = try c.decodeIfPresent(String.self, forKey: .sourceBlockID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(lines, forKey: .lines)
        try c.encode(isDone, forKey: .isDone)
        try c.encodeIfPresent(rolledFromDayKey, forKey: .rolledFromDayKey)
        try c.encodeIfPresent(sourceNoteID, forKey: .sourceNoteID)
        try c.encodeIfPresent(sourceBlockID, forKey: .sourceBlockID)
    }

    static func == (lhs: VaultTodaysTaskRow, rhs: VaultTodaysTaskRow) -> Bool {
        lhs.id == rhs.id && lhs.lines == rhs.lines && lhs.isDone == rhs.isDone
            && lhs.rolledFromDayKey == rhs.rolledFromDayKey
            && lhs.sourceNoteID == rhs.sourceNoteID
            && lhs.sourceBlockID == rhs.sourceBlockID
    }
}

// MARK: - Per-day file

enum VaultTodaysTasksDayStore {
    private struct DayFileEnvelope: Decodable {
        var schemaVersion: Int
        var items: [VaultTodaysTaskRow]
    }

    private struct DayFileSavePayload: Encodable {
        static let currentSchemaVersion = 2
        var schemaVersion: Int
        var items: [VaultTodaysTaskRow]
    }

    static func load(day: VaultTasksCalendarDay, vaultURL: URL) -> [VaultTodaysTaskRow] {
        let url = VaultPaths.todaysTasksDayFileURL(vaultURL: vaultURL, dayStorageKey: day.storageKey)
        guard let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(DayFileEnvelope.self, from: data),
            payload.schemaVersion == 1 || payload.schemaVersion == 2
        else {
            return []
        }
        return payload.items
    }

    static func save(day: VaultTasksCalendarDay, items: [VaultTodaysTaskRow], vaultURL: URL) throws {
        let dir = VaultPaths.todaysTasksDaysDirectory(vaultURL: vaultURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = DayFileSavePayload(schemaVersion: DayFileSavePayload.currentSchemaVersion, items: items)
        let data = try JSONEncoder().encode(payload)
        let url = VaultPaths.todaysTasksDayFileURL(vaultURL: vaultURL, dayStorageKey: day.storageKey)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Index + bootstrap / legacy migration

enum VaultTodaysTasksIndexStore {
    private struct IndexPayload: Codable {
        static let currentSchemaVersion = 1
        var schemaVersion: Int
        var days: [String]
    }

    /// Loads sorted unique days; creates index from legacy single file when index is missing (legacy file left on disk).
    static func loadOrBootstrap(vaultURL: URL, calendar: Calendar) throws -> [VaultTasksCalendarDay] {
        let indexURL = VaultPaths.todaysTasksIndexURL(vaultURL: vaultURL)
        if let data = try? Data(contentsOf: indexURL),
            let payload = try? JSONDecoder().decode(IndexPayload.self, from: data),
            payload.schemaVersion == IndexPayload.currentSchemaVersion {
            return normalizeDays(payload.days)
        }

        let legacyItems = VaultTodaysTasksLegacySingleFile.loadItemsIfPresent(vaultURL: vaultURL)
        let today = VaultTasksCalendarDay.today(calendar: calendar)
        var keys: [String] = []
        if !legacyItems.isEmpty {
            try VaultTodaysTasksDayStore.save(day: today, items: legacyItems, vaultURL: vaultURL)
            keys = [today.storageKey]
        }
        try saveSortedDayKeys(keys, vaultURL: vaultURL)
        return normalizeDays(keys)
    }

    static func saveSortedDays(_ days: [VaultTasksCalendarDay], vaultURL: URL) throws {
        let keys = days.map(\.storageKey).sorted()
        try saveSortedDayKeys(keys, vaultURL: vaultURL)
    }

    static func insertDayIfMissing(_ day: VaultTasksCalendarDay, vaultURL: URL, existing: [VaultTasksCalendarDay]) throws -> [VaultTasksCalendarDay] {
        guard !existing.contains(day) else { return existing.sorted() }
        var next = existing
        next.append(day)
        let sorted = next.sorted()
        try saveSortedDays(sorted, vaultURL: vaultURL)
        return sorted
    }

    private static func saveSortedDayKeys(_ keys: [String], vaultURL: URL) throws {
        let miran = VaultPaths.miranDirectory(vaultURL: vaultURL)
        try FileManager.default.createDirectory(at: miran, withIntermediateDirectories: true)
        let uniqueSorted = Array(Set(keys)).sorted()
        let payload = IndexPayload(schemaVersion: IndexPayload.currentSchemaVersion, days: uniqueSorted)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: VaultPaths.todaysTasksIndexURL(vaultURL: vaultURL), options: .atomic)
    }

    private static func normalizeDays(_ raw: [String]) -> [VaultTasksCalendarDay] {
        let days = raw.compactMap { VaultTasksCalendarDay(storageKey: $0) }
        return Array(Set(days)).sorted()
    }
}

// MARK: - Legacy single file reader (`todays-tasks.json`)

enum VaultTodaysTasksLegacySingleFile {
    private struct FilePayload: Codable {
        static let currentSchemaVersion = 1
        var schemaVersion: Int
        var items: [VaultTodaysTaskRow]
    }

    static func loadItemsIfPresent(vaultURL: URL) -> [VaultTodaysTaskRow] {
        let url = VaultPaths.todaysTasksURL(vaultURL: vaultURL)
        guard let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(FilePayload.self, from: data),
            payload.schemaVersion == FilePayload.currentSchemaVersion
        else {
            return []
        }
        return payload.items
    }
}

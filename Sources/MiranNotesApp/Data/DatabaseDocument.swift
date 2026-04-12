import Foundation
import MiranNotesCore
import os.log

/// Manages a single vault-level database's schema, rows, and views on disk.
/// Uses atomic writes and debounced persistence. Rows stored as JSONL (ADR 0002 contract).
actor DatabaseDocument {
    private enum Budget {
        static let defaultPageSize = 500
        static let maxLoadedRows = 50_000
    }

    let databaseID: UUID
    private let schemaURL: URL
    private let rowsURL: URL
    private let viewsDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private(set) var schema: DatabaseSchema
    private(set) var rows: [TableRowRecord]
    private(set) var views: [DatabaseViewConfig]
    private var allRowsLoaded = false
    var isDirty = false

    init(vaultURL: URL, databaseID: UUID) {
        self.databaseID = databaseID
        self.schemaURL = VaultPaths.databaseSchemaURL(vaultURL: vaultURL, databaseID: databaseID)
        self.rowsURL = VaultPaths.databaseRowsURL(vaultURL: vaultURL, databaseID: databaseID)
        self.viewsDirectory = VaultPaths.databaseViewsDirectory(vaultURL: vaultURL, databaseID: databaseID)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
        self.schema = DatabaseSchema()
        self.rows = []
        self.views = []
    }

    // MARK: - Loading

    func loadIfNeeded() throws {
        try loadSchema()
        if !allRowsLoaded { try loadAllRows() }
        try loadViews()
    }

    private func loadSchema() throws {
        guard FileManager.default.fileExists(atPath: schemaURL.path),
              let data = try? Data(contentsOf: schemaURL),
              let decoded = try? decoder.decode(DatabaseSchema.self, from: data) else {
            return
        }
        schema = decoded
    }

    private func loadAllRows() throws {
        guard FileManager.default.fileExists(atPath: rowsURL.path) else {
            allRowsLoaded = true
            return
        }
        let data = try String(contentsOf: rowsURL, encoding: .utf8)
        var parsed: [TableRowRecord] = []
        for line in data.split(whereSeparator: \.isNewline) {
            if parsed.count >= Budget.maxLoadedRows { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let rowData = trimmed.data(using: .utf8),
               let row = try? decoder.decode(TableRowRecord.self, from: rowData) {
                parsed.append(row)
            }
        }
        rows = parsed
        allRowsLoaded = true
    }

    private func loadViews() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: viewsDirectory.path) else { return }
        let files = (try? fm.contentsOfDirectory(at: viewsDirectory, includingPropertiesForKeys: nil))
            ?? []
        var loaded: [DatabaseViewConfig] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let view = try? decoder.decode(DatabaseViewConfig.self, from: data) {
                loaded.append(view)
            }
        }
        views = loaded
    }

    // MARK: - Schema mutations

    func updateSchema(_ newSchema: DatabaseSchema) {
        schema = newSchema
        isDirty = true
    }

    func addColumn(_ column: DatabaseColumnDefinition) {
        schema.columns.append(column)
        isDirty = true
    }

    func removeColumn(id: String) {
        schema.columns.removeAll { $0.id == id }
        for i in rows.indices {
            rows[i].cells.removeValue(forKey: id)
        }
        isDirty = true
    }

    // MARK: - Row mutations

    func insertRow(_ row: TableRowRecord) {
        rows.append(row)
        isDirty = true
    }

    func updateRow(id: UUID, cells: [String: String]) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].cells = cells
        isDirty = true
    }

    func updateCell(rowID: UUID, columnID: String, value: String) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let colType = schema.columnType(for: columnID)
        guard colType.accepts(value) else { return }
        rows[index].cells[columnID] = value
        isDirty = true
    }

    func deleteRow(id: UUID) {
        let before = rows.count
        rows.removeAll { $0.id == id }
        if rows.count != before {
            isDirty = true
        }
    }

    func replaceAllRows(_ newRows: [TableRowRecord]) {
        rows = newRows
        isDirty = true
    }

    // MARK: - View mutations

    func addView(_ view: DatabaseViewConfig) {
        views.append(view)
        isDirty = true
    }

    func updateView(_ view: DatabaseViewConfig) {
        if let i = views.firstIndex(where: { $0.id == view.id }) {
            views[i] = view
        } else {
            views.append(view)
        }
        isDirty = true
    }

    func removeView(id: UUID) {
        views.removeAll { $0.id == id }
        isDirty = true
    }

    // MARK: - Query

    func filteredRows(view: DatabaseViewConfig) -> [TableRowRecord] {
        var result = rows

        for filter in view.filters {
            result = result.filter { row in
                DatabaseQueryEngine.matches(row: row, filter: filter, schema: schema)
            }
        }

        for sortKey in view.sortKeys.reversed() {
            let colType = schema.columnType(for: sortKey.columnID)
            result.sort { a, b in
                let va = a.cells[sortKey.columnID] ?? ""
                let vb = b.cells[sortKey.columnID] ?? ""
                let cmp = DatabaseQueryEngine.compare(va, vb, type: colType)
                return sortKey.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }

        return result
    }

    func allRows() -> [TableRowRecord] { rows }

    func snapshot() -> (schema: DatabaseSchema, rows: [TableRowRecord], views: [DatabaseViewConfig]) {
        (schema, rows, views)
    }

    // MARK: - Persistence

    func flushToDisk() throws {
        let fm = FileManager.default
        let dbDir = rowsURL.deletingLastPathComponent()
        try fm.createDirectory(at: dbDir, withIntermediateDirectories: true)

        let schemaData = try encoder.encode(schema)
        try atomicWrite(data: schemaData, to: schemaURL)

        var lines = ""
        let rowEncoder = JSONEncoder()
        rowEncoder.outputFormatting = [.sortedKeys]
        for row in rows {
            let data = try rowEncoder.encode(row)
            if let s = String(data: data, encoding: .utf8) {
                lines.append(s)
                lines.append("\n")
            }
        }
        try atomicWrite(data: Data(lines.utf8), to: rowsURL)

        try fm.createDirectory(at: viewsDirectory, withIntermediateDirectories: true)
        let viewEncoder = JSONEncoder()
        viewEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for view in views {
            let viewData = try viewEncoder.encode(view)
            let viewURL = viewsDirectory.appendingPathComponent("\(view.id.uuidString.lowercased()).json")
            try atomicWrite(data: viewData, to: viewURL)
        }

        isDirty = false
    }

    private func atomicWrite(data: Data, to url: URL) throws {
        let tmpURL = url.appendingPathExtension("tmp")
        try data.write(to: tmpURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } else {
            try FileManager.default.moveItem(at: tmpURL, to: url)
        }
    }

    func invalidateAndReload() throws {
        allRowsLoaded = false
        rows = []
        views = []
        isDirty = false
        try loadIfNeeded()
    }
}

// MARK: - Query engine

enum DatabaseQueryEngine {
    static func matches(row: TableRowRecord, filter: DatabaseFilter, schema: DatabaseSchema) -> Bool {
        let value = row.cells[filter.columnID] ?? ""
        switch filter.op {
        case .equals:
            return value == filter.value
        case .notEquals:
            return value != filter.value
        case .contains:
            return value.localizedCaseInsensitiveContains(filter.value)
        case .notContains:
            return !value.localizedCaseInsensitiveContains(filter.value)
        case .isEmpty:
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .isNotEmpty:
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .greaterThan:
            return compareNumericOrString(value, filter.value) == .orderedDescending
        case .lessThan:
            return compareNumericOrString(value, filter.value) == .orderedAscending
        case .before:
            return value < filter.value
        case .after:
            return value > filter.value
        }
    }

    static func compare(_ a: String, _ b: String, type: DatabaseColumnType) -> ComparisonResult {
        switch type {
        case .number, .duration:
            return compareNumericOrString(a, b)
        case .date:
            return a.compare(b)
        default:
            return a.localizedCaseInsensitiveCompare(b)
        }
    }

    private static func compareNumericOrString(_ a: String, _ b: String) -> ComparisonResult {
        if let na = Double(a), let nb = Double(b) {
            if na < nb { return .orderedAscending }
            if na > nb { return .orderedDescending }
            return .orderedSame
        }
        return a.localizedCaseInsensitiveCompare(b)
    }
}

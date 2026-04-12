import Foundation
import MiranNotesCore

/// In-memory JSONL table with debounced atomic persistence (lazy full read on load).
actor TableDocument {
    private enum Budget {
        static let maxLoadedRows = 20_000
    }

    private let jsonlURL: URL
    private let schemaURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private(set) var schema: TableSchemaRecord
    private(set) var rows: [TableRowRecord]
    /// Bounded undo: snapshots of row arrays.
    private var undoStack: [[TableRowRecord]] = []
    private let maxUndo = 50

    init(jsonlURL: URL, schemaURL: URL) {
        self.jsonlURL = jsonlURL
        self.schemaURL = schemaURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.schema = TableSchemaRecord(columns: [
            TableColumnRecord(id: "col1", title: "Column 1", type: "string"),
            TableColumnRecord(id: "col2", title: "Column 2", type: "string")
        ])
        self.rows = []
    }

    func loadIfNeeded() throws {
        if FileManager.default.fileExists(atPath: schemaURL.path),
           let data = try? Data(contentsOf: schemaURL),
           let decoded = try? decoder.decode(TableSchemaRecord.self, from: data) {
            schema = decoded
        }
        guard rows.isEmpty, FileManager.default.fileExists(atPath: jsonlURL.path) else { return }
        try readAllRows()
    }

    private func readAllRows() throws {
        let data = try String(contentsOf: jsonlURL, encoding: .utf8)
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
    }

    func replaceRows(_ newRows: [TableRowRecord], recordUndo: Bool = true) throws {
        let previous = rows
        if recordUndo {
            pushUndo()
        }
        do {
            try writeAtomic(rows: newRows, schema: schema)
            rows = newRows
        } catch {
            rows = previous
            if recordUndo, !undoStack.isEmpty {
                _ = undoStack.popLast()
            }
            throw error
        }
    }

    func appendRow(_ row: TableRowRecord, recordUndo: Bool = true) throws {
        var next = rows
        next.append(row)
        try replaceRows(next, recordUndo: recordUndo)
    }

    func updateCell(rowId: UUID, columnId: String, value: String, recordUndo: Bool = true) throws {
        guard let index = rows.firstIndex(where: { $0.id == rowId }) else { return }
        let columnType = schema.columnType(for: columnId)
        guard columnType.accepts(value) else { return }
        var next = rows
        next[index].cells[columnId] = value
        try replaceRows(next, recordUndo: recordUndo)
    }

    func undo() throws {
        guard let prev = undoStack.popLast() else { return }
        let current = rows
        rows = prev
        do {
            try writeAtomic(rows: rows, schema: schema)
        } catch {
            rows = current
            undoStack.append(prev)
            throw error
        }
    }

    private func pushUndo() {
        undoStack.append(rows)
        if undoStack.count > maxUndo {
            undoStack.removeFirst(undoStack.count - maxUndo)
        }
    }

    private func atomicWrite(data: Data, to url: URL) throws {
        let tmpURL = url.appendingPathExtension("tmp")
        var committed = false
        defer {
            if !committed {
                try? FileManager.default.removeItem(at: tmpURL)
            }
        }
        try data.write(to: tmpURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } else {
            try FileManager.default.moveItem(at: tmpURL, to: url)
        }
        committed = true
    }

    private func writeAtomic(rows: [TableRowRecord], schema: TableSchemaRecord) throws {
        try FileManager.default.createDirectory(at: jsonlURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lines = ""
        for row in rows {
            let data = try encoder.encode(row)
            if let s = String(data: data, encoding: .utf8) {
                lines.append(s)
                lines.append("\n")
            }
        }
        try atomicWrite(data: Data(lines.utf8), to: jsonlURL)
        let schemaData = try encoder.encode(schema)
        try atomicWrite(data: schemaData, to: schemaURL)
    }

    /// Persists current table state immediately (e.g. before closing sheet).
    func flushNow() throws {
        try writeAtomic(rows: rows, schema: schema)
    }

    func snapshot() -> (schema: TableSchemaRecord, rows: [TableRowRecord]) {
        (schema, rows)
    }

    /// Lightweight query primitive for table-backed filtering without requiring full DB subsystem yet.
    func filteredRows(columnId: String, contains query: String) -> [TableRowRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }
        return rows.filter { row in
            row.cells[columnId]?.localizedCaseInsensitiveContains(trimmed) == true
        }
    }
}

enum TableDocumentFactory {
    static func bootstrapEmptyTable(vaultURL: URL, noteID: UUID, artifactID: UUID) throws -> (relativePath: String, jsonl: URL, schema: URL) {
        let aux = VaultPaths.auxDirectory(vaultURL: vaultURL, noteID: noteID)
        let tablesDir = aux.appendingPathComponent("tables", isDirectory: true)
        try FileManager.default.createDirectory(at: tablesDir, withIntermediateDirectories: true)
        let base = artifactID.uuidString.lowercased()
        let jsonl = tablesDir.appendingPathComponent("\(base).jsonl")
        let schema = tablesDir.appendingPathComponent("\(base).schema.json")
        let relative = "tables/\(base).jsonl"
        if !FileManager.default.fileExists(atPath: jsonl.path) {
            try Data().write(to: jsonl, options: .atomic)
        }
        if !FileManager.default.fileExists(atPath: schema.path) {
            let defaultSchema = TableSchemaRecord(columns: [
                TableColumnRecord(id: "col1", title: "Column 1", type: "string"),
                TableColumnRecord(id: "col2", title: "Column 2", type: "string")
            ])
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(defaultSchema).write(to: schema, options: .atomic)
        }
        return (relative, jsonl, schema)
    }
}

import Foundation
import MiranNotesCore
import os.log

private let legacyVaultLogger = Logger(subsystem: "app.miran.notes", category: "Vault")

public enum DatabaseRepositoryError: LocalizedError, Equatable {
    case databaseNotFound(UUID)
    case databaseAlreadyExists(String)
    case schemaValidationFailed(String)
    case rowNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case let .databaseNotFound(id):
            return "Database not found: \(id.uuidString)"
        case let .databaseAlreadyExists(name):
            return "A database named '\(name)' already exists."
        case let .schemaValidationFailed(reason):
            return "Schema validation failed: \(reason)"
        case let .rowNotFound(id):
            return "Row not found: \(id.uuidString)"
        }
    }
}

/// Coordinates vault-level database CRUD, schema management, row operations, and view configurations.
/// Parallels ``NoteRepository`` for notes: provides the central facade for all database persistence.
///
/// **Build:** Lives in the `MiranNotesLegacyDatabase` library only; the shipping app executable does not link it.
public actor DatabaseRepository {
    public nonisolated let vaultURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var registry: DatabaseRegistry?
    private var openDocuments: [UUID: DatabaseDocument] = [:]

    public init(vaultURL: URL) {
        self.vaultURL = vaultURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    // MARK: - Registry

    public func loadRegistry() throws -> DatabaseRegistry {
        if let cached = registry { return cached }
        let loaded = try DatabaseRegistry.loadFromVault(vaultURL: vaultURL, decoder: decoder)
        registry = loaded
        return loaded
    }

    public func invalidateCaches() {
        registry = nil
        openDocuments.removeAll()
    }

    private func saveRegistry(_ reg: DatabaseRegistry) throws {
        let url = VaultDatabasePaths.databaseRegistryURL(vaultURL: vaultURL)
        let data = try encoder.encode(reg)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        var saved = reg
        saved.isDirty = false
        registry = saved
    }

    // MARK: - Database lifecycle

    @discardableResult
    public func createDatabase(
        name: String,
        kind: DatabaseKind = .general,
        schema: DatabaseSchema = DatabaseSchema(),
        views: [DatabaseViewConfig] = []
    ) throws -> DatabaseRegistryRecord {
        var reg = try loadRegistry()

        if reg.databases.contains(where: { $0.name == name && $0.kind == kind }) {
            throw DatabaseRepositoryError.databaseAlreadyExists(name)
        }

        let record = DatabaseRegistryRecord(name: name, kind: kind)
        reg.register(record)

        let dbDir = VaultDatabasePaths.databaseDirectory(vaultURL: vaultURL, databaseID: record.id)
        let fm = FileManager.default
        try fm.createDirectory(at: dbDir, withIntermediateDirectories: true)

        let viewsDir = VaultDatabasePaths.databaseViewsDirectory(vaultURL: vaultURL, databaseID: record.id)
        try fm.createDirectory(at: viewsDir, withIntermediateDirectories: true)

        let schemaData = try encoder.encode(schema)
        try schemaData.write(
            to: VaultDatabasePaths.databaseSchemaURL(vaultURL: vaultURL, databaseID: record.id),
            options: .atomic
        )

        let rowsURL = VaultDatabasePaths.databaseRowsURL(vaultURL: vaultURL, databaseID: record.id)
        if !fm.fileExists(atPath: rowsURL.path) {
            try Data().write(to: rowsURL, options: .atomic)
        }

        let viewEncoder = JSONEncoder()
        viewEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for view in views {
            let viewURL = VaultDatabasePaths.databaseViewURL(
                vaultURL: vaultURL,
                databaseID: record.id,
                viewID: view.id
            )
            let viewData = try viewEncoder.encode(view)
            try viewData.write(to: viewURL, options: .atomic)
        }

        try saveRegistry(reg)
        legacyVaultLogger.info(
            "Created database '\(name, privacy: .public)' kind=\(kind.rawValue, privacy: .public) id=\(record.id.uuidString, privacy: .public)"
        )
        return record
    }

    public func deleteDatabase(id: UUID) throws {
        var reg = try loadRegistry()
        guard reg.database(id: id) != nil else {
            throw DatabaseRepositoryError.databaseNotFound(id)
        }
        reg.remove(id: id)

        let dbDir = VaultDatabasePaths.databaseDirectory(vaultURL: vaultURL, databaseID: id)
        if FileManager.default.fileExists(atPath: dbDir.path) {
            try FileManager.default.removeItem(at: dbDir)
        }

        openDocuments.removeValue(forKey: id)
        try saveRegistry(reg)
        legacyVaultLogger.info("Deleted database id=\(id.uuidString, privacy: .public)")
    }

    public func listDatabases() throws -> [DatabaseRegistryRecord] {
        try loadRegistry().databases
    }

    public func databaseRecord(id: UUID) throws -> DatabaseRegistryRecord {
        guard let record = try loadRegistry().database(id: id) else {
            throw DatabaseRepositoryError.databaseNotFound(id)
        }
        return record
    }

    public func databaseRecord(kind: DatabaseKind) throws -> DatabaseRegistryRecord? {
        try loadRegistry().database(kind: kind)
    }

    // MARK: - Document access

    public func openDocument(id: UUID) throws -> DatabaseDocument {
        if let existing = openDocuments[id] { return existing }
        guard try loadRegistry().database(id: id) != nil else {
            throw DatabaseRepositoryError.databaseNotFound(id)
        }
        let doc = DatabaseDocument(vaultURL: vaultURL, databaseID: id)
        openDocuments[id] = doc
        return doc
    }

    // MARK: - Convenience row operations

    public func insertRow(databaseID: UUID, cells: [String: String]) throws -> TableRowRecord {
        let doc = try openDocument(id: databaseID)
        let row = TableRowRecord(cells: cells)
        Task { await doc.insertRow(row) }
        return row
    }

    public func updateCell(databaseID: UUID, rowID: UUID, columnID: String, value: String) throws {
        let doc = try openDocument(id: databaseID)
        Task { await doc.updateCell(rowID: rowID, columnID: columnID, value: value) }
    }

    public func deleteRow(databaseID: UUID, rowID: UUID) throws {
        let doc = try openDocument(id: databaseID)
        Task { await doc.deleteRow(id: rowID) }
    }

    public func queryRows(databaseID: UUID, view: DatabaseViewConfig) async throws -> [TableRowRecord] {
        let doc = try openDocument(id: databaseID)
        try await doc.loadIfNeeded()
        return await doc.filteredRows(view: view)
    }

    public func allRows(databaseID: UUID) async throws -> [TableRowRecord] {
        let doc = try openDocument(id: databaseID)
        try await doc.loadIfNeeded()
        return await doc.allRows()
    }

    public func loadSchema(databaseID: UUID) async throws -> DatabaseSchema {
        let doc = try openDocument(id: databaseID)
        try await doc.loadIfNeeded()
        return await doc.schema
    }

    public func loadViews(databaseID: UUID) async throws -> [DatabaseViewConfig] {
        let doc = try openDocument(id: databaseID)
        try await doc.loadIfNeeded()
        return await doc.views
    }

    /// Persists all dirty open documents to disk.
    public func flushAll() async throws {
        for (_, doc) in openDocuments {
            if await doc.isDirty {
                try await doc.flushToDisk()
            }
        }
    }

    /// Persists a specific database document to disk.
    public func flush(databaseID: UUID) async throws {
        guard let doc = openDocuments[databaseID] else { return }
        try await doc.flushToDisk()
    }
}

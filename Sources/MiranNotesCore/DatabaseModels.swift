import Foundation

// MARK: - Vault-level database contract

public enum DatabaseKind: String, Codable, Sendable, CaseIterable {
    case general
}

public enum DatabaseColumnType: String, Codable, CaseIterable, Sendable {
    case string
    case number
    case boolean
    case date
    case select
    case multiSelect
    case relation
    case noteLink
    case url
    case duration

    public func accepts(_ value: String) -> Bool {
        if value.isEmpty { return true }
        switch self {
        case .string, .url:
            return true
        case .number:
            return Double(value) != nil
        case .boolean:
            let n = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return n == "true" || n == "false"
        case .date:
            return ISO8601DateFormatter().date(from: value) != nil
                || DatabaseDateParser.parseLoose(value) != nil
        case .select:
            return true
        case .multiSelect:
            return true
        case .relation, .noteLink:
            return UUID(uuidString: value) != nil
        case .duration:
            return Int(value) != nil
        }
    }
}

public struct DatabaseColumnDefinition: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var type: DatabaseColumnType
    public var options: [String]?
    public var relationDatabaseID: UUID?
    public var required: Bool

    public init(
        id: String,
        title: String,
        type: DatabaseColumnType = .string,
        options: [String]? = nil,
        relationDatabaseID: UUID? = nil,
        required: Bool = false
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.options = options
        self.relationDatabaseID = relationDatabaseID
        self.required = required
    }
}

public struct DatabaseSchema: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var columns: [DatabaseColumnDefinition]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        columns: [DatabaseColumnDefinition] = []
    ) {
        self.schemaVersion = schemaVersion
        self.columns = columns
    }

    public func columnType(for columnID: String) -> DatabaseColumnType {
        columns.first(where: { $0.id == columnID })?.type ?? .string
    }

    public func column(id: String) -> DatabaseColumnDefinition? {
        columns.first(where: { $0.id == id })
    }
}

public struct DatabaseRegistryRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: DatabaseKind
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, kind: DatabaseKind = .general, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
    }
}

public struct DatabaseRegistry: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var databases: [DatabaseRegistryRecord]
    public var isDirty: Bool = false

    enum CodingKeys: String, CodingKey {
        case schemaVersion, databases
    }

    public init(schemaVersion: Int = currentSchemaVersion, databases: [DatabaseRegistryRecord] = []) {
        self.schemaVersion = schemaVersion
        self.databases = databases
    }

    public func database(id: UUID) -> DatabaseRegistryRecord? {
        databases.first(where: { $0.id == id })
    }

    public func database(kind: DatabaseKind) -> DatabaseRegistryRecord? {
        databases.first(where: { $0.kind == kind })
    }

    public mutating func register(_ record: DatabaseRegistryRecord) {
        if let i = databases.firstIndex(where: { $0.id == record.id }) {
            guard databases[i] != record else { return }
            databases[i] = record
        } else {
            databases.append(record)
        }
        isDirty = true
    }

    public mutating func remove(id: UUID) {
        let before = databases.count
        databases.removeAll { $0.id == id }
        if databases.count != before {
            isDirty = true
        }
    }
}

// MARK: - View configuration

public enum DatabaseViewLayout: String, Codable, Sendable, CaseIterable {
    case table
    case calendar
    case board
    case list
}

public struct DatabaseFilter: Codable, Equatable, Sendable {
    public var columnID: String
    public var op: FilterOp
    public var value: String

    public enum FilterOp: String, Codable, Sendable {
        case equals, notEquals
        case contains, notContains
        case greaterThan, lessThan
        case isEmpty, isNotEmpty
        case before, after
    }

    public init(columnID: String, op: FilterOp, value: String = "") {
        self.columnID = columnID
        self.op = op
        self.value = value
    }
}

public struct DatabaseSortKey: Codable, Equatable, Sendable {
    public var columnID: String
    public var ascending: Bool

    public init(columnID: String, ascending: Bool = true) {
        self.columnID = columnID
        self.ascending = ascending
    }
}

public struct DatabaseViewConfig: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var layout: DatabaseViewLayout
    public var filters: [DatabaseFilter]
    public var sortKeys: [DatabaseSortKey]
    public var groupByColumnID: String?
    public var calendarDateColumnID: String?
    public var calendarEndColumnID: String?
    public var visibleColumnIDs: [String]?

    public init(
        id: UUID = UUID(),
        name: String = "Default",
        layout: DatabaseViewLayout = .table,
        filters: [DatabaseFilter] = [],
        sortKeys: [DatabaseSortKey] = [],
        groupByColumnID: String? = nil,
        calendarDateColumnID: String? = nil,
        calendarEndColumnID: String? = nil,
        visibleColumnIDs: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.layout = layout
        self.filters = filters
        self.sortKeys = sortKeys
        self.groupByColumnID = groupByColumnID
        self.calendarDateColumnID = calendarDateColumnID
        self.calendarEndColumnID = calendarEndColumnID
        self.visibleColumnIDs = visibleColumnIDs
    }
}

// MARK: - Loose date parser for user-typed dates (YYYY-MM-DD)

public enum DatabaseDateParser {
    private static let looseDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    public static func parseLoose(_ string: String) -> Date? {
        looseDateFormatter.date(from: string)
    }

    public static func formatLoose(_ date: Date) -> String {
        looseDateFormatter.string(from: date)
    }
}

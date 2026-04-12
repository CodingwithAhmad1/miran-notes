import Foundation

// MARK: - JSONL table contract (ADR 0002)

public enum TableColumnType: String, Codable, CaseIterable, Sendable {
    case string
    case number
    case boolean
    case date

    public func accepts(_ value: String) -> Bool {
        switch self {
        case .string:
            return true
        case .number:
            return Double(value) != nil || value.isEmpty
        case .boolean:
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty || normalized == "true" || normalized == "false"
        case .date:
            if value.isEmpty { return true }
            return ISO8601DateFormatter().date(from: value) != nil
        }
    }
}

public struct TableColumnRecord: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var type: String

    public init(id: String, title: String, type: String = "string") {
        self.id = id
        self.title = title
        self.type = type
    }
}

public struct TableSchemaRecord: Codable, Equatable, Sendable {
    public var columns: [TableColumnRecord]

    public init(columns: [TableColumnRecord]) {
        self.columns = columns
    }

    public func columnType(for columnID: String) -> TableColumnType {
        let raw = columns.first(where: { $0.id == columnID })?.type ?? TableColumnType.string.rawValue
        return TableColumnType(rawValue: raw) ?? .string
    }
}

/// One JSONL line = one row.
public struct TableRowRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var cells: [String: String]

    public init(id: UUID = UUID(), cells: [String: String] = [:]) {
        self.id = id
        self.cells = cells
    }
}

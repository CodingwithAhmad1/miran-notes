import Foundation

// MARK: - JSONL table contract (ADR 0002)

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

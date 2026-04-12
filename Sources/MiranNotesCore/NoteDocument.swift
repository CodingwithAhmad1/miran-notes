import Foundation

public struct NoteDocument: Identifiable, Equatable {
    public var id: UUID
    public var text: String
    public var metadata: NoteMetadata

    public init(id: UUID = UUID(), text: String, metadata: NoteMetadata) {
        self.id = id
        self.text = text
        self.metadata = metadata
    }
}

public struct NoteMetadata: Codable, Equatable {
    public var schemaVersion: Int
    public var blocks: [Block]
    public var spans: [Span]

    public static let currentSchemaVersion = 1

    public static var empty: NoteMetadata {
        NoteMetadata(
            schemaVersion: currentSchemaVersion,
            blocks: [],
            spans: []
        )
    }

    public init(schemaVersion: Int, blocks: [Block], spans: [Span]) {
        self.schemaVersion = schemaVersion
        self.blocks = blocks
        self.spans = spans
    }
}

public struct Block: Codable, Identifiable, Equatable {
    public var id: String
    public var type: BlockType
    public var range: TextRange
    public var level: Int?
    public var icon: String?

    public init(id: String, type: BlockType, range: TextRange, level: Int?, icon: String?) {
        self.id = id
        self.type = type
        self.range = range
        self.level = level
        self.icon = icon
    }
}

public enum BlockType: String, Codable, CaseIterable {
    case paragraph
    case heading
    case listItem
    case callout
    case code
    case divider
}

public struct Span: Codable, Equatable {
    public var range: TextRange
    public var style: SpanStyle

    public init(range: TextRange, style: SpanStyle) {
        self.range = range
        self.style = style
    }
}

public enum SpanStyle: String, Codable, CaseIterable {
    case bold
    case italic
    case code
}

public struct TextRange: Codable, Equatable, Sendable {
    public var start: Int
    public var length: Int

    public var end: Int { start + length }
    public var isEmpty: Bool { length == 0 }

    public init(start: Int, length: Int) {
        self.start = start
        self.length = max(0, length)
    }
}

extension TextRange {
    public func contains(_ offset: Int) -> Bool {
        offset >= start && offset < end
    }

    public func intersects(_ other: TextRange) -> Bool {
        max(start, other.start) < min(end, other.end)
    }

    public func clamped(to upperBound: Int) -> TextRange {
        let boundedStart = min(max(0, start), upperBound)
        let boundedEnd = min(max(boundedStart, end), upperBound)
        return TextRange(start: boundedStart, length: boundedEnd - boundedStart)
    }
}

public struct MetadataValidationResult {
    public var normalizedMetadata: NoteMetadata
    public var warnings: [String]

    public init(normalizedMetadata: NoteMetadata, warnings: [String]) {
        self.normalizedMetadata = normalizedMetadata
        self.warnings = warnings
    }
}

import Foundation

public struct NoteDocument: Identifiable, Equatable, Sendable {
    /// Stable vault-wide identity; delegates to `metadata.noteID` so there is exactly one source of truth.
    public var id: UUID { metadata.noteID }
    public var text: String
    public var metadata: NoteMetadata

    public init(text: String, metadata: NoteMetadata) {
        self.text = text
        self.metadata = metadata
    }
}

public struct NoteMetadata: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    /// Stable vault-wide identity; persisted in sidecar (v2+). Assigned on migrate for legacy notes.
    public var noteID: UUID
    public var blocks: [Block]
    public var spans: [Span]
    public var links: [NoteLink]
    /// Small key-value properties for queries / front-matter style use (v2+).
    public var properties: [String: String]

    public static let currentSchemaVersion = 2

    public static var empty: NoteMetadata {
        NoteMetadata(
            schemaVersion: currentSchemaVersion,
            noteID: UUID(),
            blocks: [],
            spans: [],
            links: [],
            properties: [:]
        )
    }

    public init(
        schemaVersion: Int,
        noteID: UUID,
        blocks: [Block],
        spans: [Span],
        links: [NoteLink] = [],
        properties: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.noteID = noteID
        self.blocks = blocks
        self.spans = spans
        self.links = links
        self.properties = properties
    }

    /// Legacy sidecar keys (`artifacts`, `databaseRowReferences`) are ignored on decode and no longer written.
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case noteID
        case blocks
        case spans
        case links
        case properties
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        noteID = try c.decodeIfPresent(UUID.self, forKey: .noteID) ?? UUID()
        blocks = try c.decodeIfPresent([Block].self, forKey: .blocks) ?? []
        spans = try c.decodeIfPresent([Span].self, forKey: .spans) ?? []
        links = try c.decodeIfPresent([NoteLink].self, forKey: .links) ?? []
        properties = try c.decodeIfPresent([String: String].self, forKey: .properties) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(noteID, forKey: .noteID)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(spans, forKey: .spans)
        try c.encode(links, forKey: .links)
        try c.encode(properties, forKey: .properties)
    }
}

public struct Block: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var type: BlockType
    public var range: TextRange
    public var level: Int?
    public var icon: String?
    /// `taskItem` blocks only: checkbox state. Additive optional so older sidecars decode unchanged.
    public var isDone: Bool?

    public init(id: String, type: BlockType, range: TextRange, level: Int?, icon: String?, isDone: Bool? = nil) {
        self.id = id
        self.type = type
        self.range = range
        self.level = level
        self.icon = icon
        self.isDone = isDone
    }
}

public enum BlockType: String, Codable, CaseIterable, Sendable {
    case paragraph
    case heading
    case listItem
    case callout
    case code
    case divider
    case taskItem
}

public struct Span: Codable, Equatable, Sendable {
    public var range: TextRange
    public var style: SpanStyle

    public init(range: TextRange, style: SpanStyle) {
        self.range = range
        self.style = style
    }
}

public enum SpanStyle: String, Codable, CaseIterable, Sendable {
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

public struct MetadataValidationResult: Sendable {
    public var normalizedMetadata: NoteMetadata
    public var warnings: [String]

    public init(normalizedMetadata: NoteMetadata, warnings: [String]) {
        self.normalizedMetadata = normalizedMetadata
        self.warnings = warnings
    }
}

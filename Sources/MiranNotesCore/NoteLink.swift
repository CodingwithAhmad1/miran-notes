import Foundation

/// A wiki-style link: parallel metadata for `[[...]]` (or other) text in the note body. Ranges are UTF-16.
public struct NoteLink: Codable, Equatable, Sendable {
    public var range: TextRange
    public var targetNoteID: UUID
    /// Optional display hint; visible text normally comes from `note.text` at `range`.
    public var label: String?

    public init(range: TextRange, targetNoteID: UUID, label: String? = nil) {
        self.range = range
        self.targetNoteID = targetNoteID
        self.label = label
    }
}

public enum EmbeddedArtifactKind: String, Codable, Sendable, CaseIterable {
    case databaseRow
    case databaseView
}

/// Reference to auxiliary storage under `vault/_aux/{noteID}/` (paths relative to that directory).
public struct EmbeddedArtifact: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: EmbeddedArtifactKind
    public var relativePath: String

    public init(id: UUID, kind: EmbeddedArtifactKind, relativePath: String) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
    }
}

public struct DatabaseRowReference: Codable, Equatable, Sendable {
    public var databaseID: UUID
    public var rowID: UUID
    public var blockID: String?

    public init(databaseID: UUID, rowID: UUID, blockID: String? = nil) {
        self.databaseID = databaseID
        self.rowID = rowID
        self.blockID = blockID
    }
}

public enum LinkAdjuster {
    public static func adjust(
        links: [NoteLink],
        replacedRange: TextRange,
        replacementUTF16Length: Int,
        constrainedTo blocks: [Block]
    ) -> [NoteLink] {
        let delta = replacementUTF16Length - replacedRange.length

        let shifted: [NoteLink] = links.compactMap { link in
            if link.range.end <= replacedRange.start {
                return link
            }

            if link.range.start >= replacedRange.end {
                let shiftedStart = max(0, link.range.start + delta)
                return NoteLink(
                    range: TextRange(start: shiftedStart, length: link.range.length),
                    targetNoteID: link.targetNoteID,
                    label: link.label
                )
            }

            let newStart = min(link.range.start, replacedRange.start)
            let newEnd = max(newStart, link.range.end + delta)
            let updated = TextRange(start: newStart, length: max(0, newEnd - newStart))
            guard !updated.isEmpty else { return nil }
            return NoteLink(range: updated, targetNoteID: link.targetNoteID, label: link.label)
        }

        return splitAcrossBlockBoundaries(links: shifted, blocks: blocks)
    }

    /// Clips links so that none cross a block boundary. Called after `splitBlock` to keep link metadata consistent.
    static func constrainToBlocks(links: [NoteLink], blocks: [Block]) -> [NoteLink] {
        splitAcrossBlockBoundaries(links: links, blocks: blocks)
    }

    private static func splitAcrossBlockBoundaries(links: [NoteLink], blocks: [Block]) -> [NoteLink] {
        guard !blocks.isEmpty else { return [] }
        var adjusted: [NoteLink] = []

        for link in links {
            let intersections = blocks.compactMap { block -> NoteLink? in
                let start = max(link.range.start, block.range.start)
                let end = min(link.range.end, block.range.end)
                guard end > start else { return nil }
                return NoteLink(
                    range: TextRange(start: start, length: end - start),
                    targetNoteID: link.targetNoteID,
                    label: link.label
                )
            }
            adjusted.append(contentsOf: intersections)
        }

        return adjusted
    }
}

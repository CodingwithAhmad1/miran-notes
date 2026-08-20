import Foundation

/// A wiki-style link: parallel metadata for `[[...]]` (or other) text in the note body. Ranges are UTF-16.
///
/// **Persistence / engine:** This type and link adjustment logic stay active regardless of app UI settings.
/// The app styles links and routes clicks per `WikiLinkPresentationPolicy`; link data on disk is unaffected by those toggles.
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

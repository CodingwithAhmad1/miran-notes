import Foundation

public enum RangeNormalizer {
    public static func utf16Length(of text: String) -> Int {
        text.utf16.count
    }

    public static func normalize(metadata: NoteMetadata, for text: String) -> MetadataValidationResult {
        let totalLength = utf16Length(of: text)
        var warnings: [String] = []

        var blocks = metadata.blocks
            .sorted { $0.range.start < $1.range.start }
            .map { block -> Block in
                var next = block
                next.range = block.range.clamped(to: totalLength)
                return next
            }

        if blocks.isEmpty {
            blocks = [
                Block(
                    id: UUID().uuidString,
                    type: .paragraph,
                    range: TextRange(start: 0, length: totalLength),
                    level: nil,
                    icon: nil
                )
            ]
            warnings.append("No blocks found. Inserted one paragraph block.")
        } else {
            blocks = closeBlockGaps(blocks, totalLength: totalLength, warnings: &warnings)
        }

        var spans = metadata.spans.map { span -> Span in
            var next = span
            next.range = span.range.clamped(to: totalLength)
            return next
        }
        spans.removeAll { $0.range.isEmpty }

        var links = metadata.links.map { link -> NoteLink in
            NoteLink(
                range: link.range.clamped(to: totalLength),
                targetNoteID: link.targetNoteID,
                label: link.label
            )
        }
        links.removeAll { $0.range.isEmpty }

        let normalized = NoteMetadata(
            schemaVersion: max(metadata.schemaVersion, NoteMetadata.currentSchemaVersion),
            noteID: metadata.noteID,
            blocks: blocks,
            spans: spans,
            links: links,
            artifacts: metadata.artifacts,
            properties: metadata.properties
        )
        return MetadataValidationResult(normalizedMetadata: normalized, warnings: warnings)
    }

    public static func isValid(metadata: NoteMetadata, for text: String) -> Bool {
        let totalLength = utf16Length(of: text)
        let sorted = metadata.blocks.sorted(by: { $0.range.start < $1.range.start })
        guard !sorted.isEmpty else { return false }

        var cursor = 0
        for block in sorted {
            if block.range.start != cursor { return false }
            if block.range.end > totalLength { return false }
            cursor = block.range.end
        }

        guard cursor == totalLength else { return false }

        for span in metadata.spans {
            if span.range.start < 0 || span.range.end > totalLength {
                return false
            }
        }

        for link in metadata.links {
            if link.range.start < 0 || link.range.end > totalLength {
                return false
            }
        }

        return true
    }

    private static func closeBlockGaps(_ blocks: [Block], totalLength: Int, warnings: inout [String]) -> [Block] {
        var normalized: [Block] = []
        var cursor = 0

        for var block in blocks {
            if block.range.start > cursor {
                warnings.append("Found a block gap. Expanded previous block coverage.")
                if var last = normalized.popLast() {
                    last.range = TextRange(start: last.range.start, length: block.range.start - last.range.start)
                    normalized.append(last)
                } else {
                    block.range = TextRange(start: 0, length: block.range.length + block.range.start)
                }
            }

            if block.range.start < cursor {
                let shiftedStart = cursor
                let newLength = max(0, block.range.end - shiftedStart)
                block.range = TextRange(start: shiftedStart, length: newLength)
                warnings.append("Adjusted overlapping block ranges.")
            }

            cursor = block.range.end
            normalized.append(block)
        }

        if let lastIndex = normalized.indices.last, normalized[lastIndex].range.end != totalLength {
            normalized[lastIndex].range = TextRange(
                start: normalized[lastIndex].range.start,
                length: max(0, totalLength - normalized[lastIndex].range.start)
            )
            warnings.append("Adjusted trailing block to cover text end.")
        }

        if normalized.count == 1, normalized[0].range.length != totalLength {
            normalized[0].range = TextRange(start: 0, length: totalLength)
            warnings.append("Adjusted single block to cover entire text.")
        }

        return normalized
    }
}

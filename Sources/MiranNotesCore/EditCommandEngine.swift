import Foundation

public enum EditCommand {
    case replaceText(range: TextRange, replacement: String)
    case splitBlock(blockID: String, atOffset: Int)
    case mergeWithPrevious(blockID: String)
    case changeBlockType(blockID: String, type: BlockType)
    case toggleSpanStyle(range: TextRange, style: SpanStyle)
    case repairMetadata
}

public struct EditCommandEngine {
    public static func apply(_ command: EditCommand, to document: NoteDocument) -> NoteDocument {
        var next = document

        switch command {
        case let .replaceText(range, replacement):
            next = applyTextReplacement(document: next, range: range, replacement: replacement)
        case let .splitBlock(blockID, atOffset):
            next = splitBlock(document: next, blockID: blockID, atOffset: atOffset)
        case let .mergeWithPrevious(blockID):
            next = mergeBlock(document: next, blockID: blockID)
        case let .changeBlockType(blockID, type):
            next = updateBlockType(document: next, blockID: blockID, type: type)
        case let .toggleSpanStyle(range, style):
            next = toggleSpan(document: next, range: range, style: style)
        case .repairMetadata:
            next = repair(document: next)
        }

#if DEBUG
        let integrity = NoteIntegrity.check(document: next)
        assert(integrity.isValid, "\(integrity.issues)")
#endif
        return next
    }

    private static func applyTextReplacement(document: NoteDocument, range: TextRange, replacement: String) -> NoteDocument {
        var next = document
        let utf16Length = RangeNormalizer.utf16Length(of: next.text)
        let safeRange = range.clamped(to: utf16Length)

        guard let swiftRange = nsRangeToStringRange(safeRange, in: next.text) else {
            return next
        }

        next.text.replaceSubrange(swiftRange, with: replacement)
        next.metadata.blocks = adjustBlocks(
            blocks: next.metadata.blocks,
            replacedRange: safeRange,
            replacementUTF16Length: replacement.utf16.count,
            text: next.text
        )
        next.metadata.spans = SpanAdjuster.adjust(
            spans: next.metadata.spans,
            replacedRange: safeRange,
            replacementUTF16Length: replacement.utf16.count,
            constrainedTo: next.metadata.blocks
        )

        if !RangeNormalizer.isValid(metadata: next.metadata, for: next.text) {
            let repaired = RangeNormalizer.normalize(metadata: next.metadata, for: next.text)
            next.metadata = repaired.normalizedMetadata
        }
        return next
    }

    private static func splitBlock(document: NoteDocument, blockID: String, atOffset: Int) -> NoteDocument {
        var next = document
        guard let index = next.metadata.blocks.firstIndex(where: { $0.id == blockID }) else {
            return next
        }

        let block = next.metadata.blocks[index]
        let splitOffset = min(max(block.range.start, atOffset), block.range.end)
        let leftLength = max(0, splitOffset - block.range.start)
        let rightLength = max(0, block.range.end - splitOffset)

        next.metadata.blocks[index].range = TextRange(start: block.range.start, length: leftLength)
        let newBlock = Block(
            id: UUID().uuidString,
            type: block.type,
            range: TextRange(start: splitOffset, length: rightLength),
            level: block.level,
            icon: block.icon
        )
        next.metadata.blocks.insert(newBlock, at: index + 1)
        return next
    }

    private static func mergeBlock(document: NoteDocument, blockID: String) -> NoteDocument {
        var next = document
        guard
            let index = next.metadata.blocks.firstIndex(where: { $0.id == blockID }),
            index > 0
        else {
            return next
        }

        let previous = next.metadata.blocks[index - 1]
        let current = next.metadata.blocks[index]
        let mergedRange = TextRange(start: previous.range.start, length: current.range.end - previous.range.start)

        next.metadata.blocks[index - 1].range = mergedRange
        next.metadata.blocks.remove(at: index)
        return next
    }

    private static func updateBlockType(document: NoteDocument, blockID: String, type: BlockType) -> NoteDocument {
        var next = document
        guard let index = next.metadata.blocks.firstIndex(where: { $0.id == blockID }) else {
            return next
        }

        next.metadata.blocks[index].type = type
        if type != .heading {
            next.metadata.blocks[index].level = nil
        } else if next.metadata.blocks[index].level == nil {
            next.metadata.blocks[index].level = 1
        }
        return next
    }

    private static func toggleSpan(document: NoteDocument, range: TextRange, style: SpanStyle) -> NoteDocument {
        var next = document
        let utf16Length = RangeNormalizer.utf16Length(of: next.text)
        let safeRange = range.clamped(to: utf16Length)
        if safeRange.isEmpty {
            if !RangeNormalizer.isValid(metadata: next.metadata, for: next.text) {
                let repaired = RangeNormalizer.normalize(metadata: next.metadata, for: next.text)
                next.metadata = repaired.normalizedMetadata
            }
            return next
        }

        if let existing = next.metadata.spans.firstIndex(where: { $0.range == safeRange && $0.style == style }) {
            next.metadata.spans.remove(at: existing)
        } else {
            next.metadata.spans.append(Span(range: safeRange, style: style))
        }

        if !RangeNormalizer.isValid(metadata: next.metadata, for: next.text) {
            let repaired = RangeNormalizer.normalize(metadata: next.metadata, for: next.text)
            next.metadata = repaired.normalizedMetadata
        }
        return next
    }

    private static func repair(document: NoteDocument) -> NoteDocument {
        var next = document
        let normalized = RangeNormalizer.normalize(metadata: next.metadata, for: next.text)
        next.metadata = normalized.normalizedMetadata
        return next
    }

    /// Exposed for unit tests (`@testable import`); production callers use `apply(.replaceText, ...)`.
    static func adjustBlocks(
        blocks: [Block],
        replacedRange: TextRange,
        replacementUTF16Length: Int,
        text: String
    ) -> [Block] {
        let delta = replacementUTF16Length - replacedRange.length
        let totalLength = RangeNormalizer.utf16Length(of: text)
        guard let affectedIndex = blocks.firstIndex(where: { $0.range.contains(replacedRange.start) || $0.range.end == replacedRange.start }) else {
            return RangeNormalizer.normalize(
                metadata: NoteMetadata(schemaVersion: NoteMetadata.currentSchemaVersion, blocks: blocks, spans: []),
                for: text
            ).normalizedMetadata.blocks
        }

        var next = blocks

        if next.indices.contains(affectedIndex) {
            let old = next[affectedIndex]
            let newLength = max(0, old.range.length + delta)
            next[affectedIndex].range = TextRange(start: old.range.start, length: newLength)
        }

        if affectedIndex + 1 < next.count {
            for index in (affectedIndex + 1)..<next.count {
                let shifted = max(0, next[index].range.start + delta)
                next[index].range = TextRange(start: shifted, length: next[index].range.length)
            }
        }

        // If the edit spans multiple blocks, or if ranges drift, repair deterministically.
        let overlapsMultipleBlocks = blocks.filter { $0.range.intersects(replacedRange) }.count > 1
        if overlapsMultipleBlocks {
            return RangeNormalizer.normalize(
                metadata: NoteMetadata(
                    schemaVersion: NoteMetadata.currentSchemaVersion,
                    blocks: next,
                    spans: []
                ),
                for: text
            ).normalizedMetadata.blocks
        }

        let clamped = next.map { block in
            var adjusted = block
            adjusted.range = block.range.clamped(to: totalLength)
            return adjusted
        }
        return clamped
    }

    private static func nsRangeToStringRange(_ range: TextRange, in text: String) -> Range<String.Index>? {
        let nsRange = NSRange(location: range.start, length: range.length)
        return Range(nsRange, in: text)
    }
}

extension EditCommand {
    public static func insertText(range: TextRange, text: String) -> EditCommand {
        .replaceText(range: range, replacement: text)
    }

    public static func delete(range: TextRange) -> EditCommand {
        .replaceText(range: range, replacement: "")
    }
}

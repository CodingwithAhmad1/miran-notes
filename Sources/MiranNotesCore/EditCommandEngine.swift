import Foundation
import os.log

public enum EditCommand {
    case replaceText(range: TextRange, replacement: String)
    case splitBlock(blockID: String, atOffset: Int)
    case mergeWithPrevious(blockID: String)
    /// `headingLevel` applies when `type == .heading` (1–6); ignored for other types.
    case changeBlockType(blockID: String, type: BlockType, headingLevel: Int?)
    case toggleSpanStyle(range: TextRange, style: SpanStyle)
    /// Inserts `[[displayText]]` at UTF-16 offset and records a wiki link to `targetNoteID` over the inserted token.
    case insertWikiLink(utf16Offset: Int, targetNoteID: UUID, displayText: String)
    /// Registers an inline database row reference in note metadata.
    case registerDatabaseRow(databaseID: UUID, rowID: UUID)
    case repairMetadata
    /// Replaces `metadata.blocks` after a full-buffer text sync, reconstraining spans and links. Text must already match `document.text`.
    case replaceMetadataBlocks(blocks: [Block])
    /// Inserts a copy of the block’s UTF-16 text immediately after the block, then splits so the duplicate becomes its own block (same type/level).
    case duplicateBlock(blockID: String)
    /// Removes the block’s text range via `replaceText`; metadata follows `adjustBlocks` (merge/split) rules.
    case deleteBlock(blockID: String)
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
        case let .changeBlockType(blockID, type, headingLevel):
            next = updateBlockType(document: next, blockID: blockID, type: type, headingLevel: headingLevel)
        case let .toggleSpanStyle(range, style):
            next = toggleSpan(document: next, range: range, style: style)
        case let .insertWikiLink(utf16Offset, targetNoteID, displayText):
            next = insertWikiLink(document: next, utf16Offset: utf16Offset, targetNoteID: targetNoteID, displayText: displayText)
        case let .registerDatabaseRow(databaseID, rowID):
            next = registerDatabaseRow(document: next, databaseID: databaseID, rowID: rowID)
        case .repairMetadata:
            next = repair(document: next)
        case let .replaceMetadataBlocks(blocks):
            next = replaceMetadataBlocks(document: next, blocks: blocks)
        case let .duplicateBlock(blockID):
            next = duplicateBlock(document: next, blockID: blockID)
        case let .deleteBlock(blockID):
            next = deleteBlock(document: next, blockID: blockID)
        }

        return next
    }

    private static func replaceMetadataBlocks(document: NoteDocument, blocks: [Block]) -> NoteDocument {
        var next = document
        next.metadata.blocks = blocks
        next.metadata.spans = SpanAdjuster.constrainToBlocks(spans: next.metadata.spans, blocks: blocks)
        next.metadata.links = LinkAdjuster.constrainToBlocks(links: next.metadata.links, blocks: blocks)
        if !RangeNormalizer.isValid(metadata: next.metadata, for: next.text) {
            let repaired = RangeNormalizer.normalize(metadata: next.metadata, for: next.text, stripZeroLengthBlocks: false)
            next.metadata = repaired.normalizedMetadata
        }
        return next
    }

    private static func applyTextReplacement(document: NoteDocument, range: TextRange, replacement: String) -> NoteDocument {
        var next = document
        let utf16Length = RangeNormalizer.utf16Length(of: next.text)
        let safeRange = range.clamped(to: utf16Length)

        guard let swiftRange = nsRangeToStringRange(safeRange, in: next.text) else {
            return next
        }

        let metadataBeforeEdit = next.metadata
        next.text.replaceSubrange(swiftRange, with: replacement)
        next.metadata.blocks = adjustBlocks(
            blocks: next.metadata.blocks,
            replacedRange: safeRange,
            replacementUTF16Length: replacement.utf16.count,
            text: next.text,
            contextMetadata: metadataBeforeEdit
        )
        next.metadata.spans = SpanAdjuster.adjust(
            spans: next.metadata.spans,
            replacedRange: safeRange,
            replacementUTF16Length: replacement.utf16.count,
            constrainedTo: next.metadata.blocks
        )
        next.metadata.links = LinkAdjuster.adjust(
            links: next.metadata.links,
            replacedRange: safeRange,
            replacementUTF16Length: replacement.utf16.count,
            constrainedTo: next.metadata.blocks
        )

        // Safety net: if adjustBlocks produced an invalid partition (edge cases not yet covered
        // deterministically), normalize and log so the failure is visible in Console.
        if !RangeNormalizer.isValid(metadata: next.metadata, for: next.text) {
            let logger = Logger(subsystem: "app.miran.notes", category: "EditEngine")
            let issues = NoteIntegrity.check(document: next).issues
            logger.error("adjustBlocks fallback triggered — \(issues.map { String(describing: $0) }.joined(separator: "; "), privacy: .public)")
            let repaired = RangeNormalizer.normalize(metadata: next.metadata, for: next.text, stripZeroLengthBlocks: false)
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

        if leftLength == 0 {
            // Degenerate split (would create two blocks with the same `start`); keep a single partition.
            next.metadata.blocks[index].range = TextRange(start: splitOffset, length: rightLength)
            return next
        }

        next.metadata.blocks[index].range = TextRange(start: block.range.start, length: leftLength)
        let newBlock = Block(
            id: UUID().uuidString,
            type: block.type,
            range: TextRange(start: splitOffset, length: rightLength),
            level: block.level,
            icon: block.icon
        )
        next.metadata.blocks.insert(newBlock, at: index + 1)

        // Constrain spans and links to the new block boundaries so neither crosses the split point.
        next.metadata.spans = SpanAdjuster.constrainToBlocks(spans: next.metadata.spans, blocks: next.metadata.blocks)
        next.metadata.links = LinkAdjuster.constrainToBlocks(links: next.metadata.links, blocks: next.metadata.blocks)

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

        next.metadata.spans = SpanAdjuster.constrainToBlocks(spans: next.metadata.spans, blocks: next.metadata.blocks)
        next.metadata.links = LinkAdjuster.constrainToBlocks(links: next.metadata.links, blocks: next.metadata.blocks)

        return next
    }

    private static func updateBlockType(document: NoteDocument, blockID: String, type: BlockType, headingLevel: Int?) -> NoteDocument {
        var next = document
        guard let index = next.metadata.blocks.firstIndex(where: { $0.id == blockID }) else {
            return next
        }

        next.metadata.blocks[index].type = type
        if type != .heading {
            next.metadata.blocks[index].level = nil
        } else if let level = headingLevel {
            next.metadata.blocks[index].level = min(max(level, 1), 6)
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
                let repaired = RangeNormalizer.normalize(metadata: next.metadata, for: next.text, stripZeroLengthBlocks: false)
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
            let repaired = RangeNormalizer.normalize(metadata: next.metadata, for: next.text, stripZeroLengthBlocks: false)
            next.metadata = repaired.normalizedMetadata
        }
        return next
    }

    private static func insertWikiLink(document: NoteDocument, utf16Offset: Int, targetNoteID: UUID, displayText: String) -> NoteDocument {
        let token = "[[\(displayText)]]"
        let len = RangeNormalizer.utf16Length(of: document.text)
        let safeOffset = min(max(0, utf16Offset), len)
        var next = applyTextReplacement(
            document: document,
            range: TextRange(start: safeOffset, length: 0),
            replacement: token
        )
        let linkRange = TextRange(start: safeOffset, length: token.utf16.count)
        next.metadata.links.append(NoteLink(range: linkRange, targetNoteID: targetNoteID, label: displayText))
        if !RangeNormalizer.isValid(metadata: next.metadata, for: next.text) {
            let repaired = RangeNormalizer.normalize(metadata: next.metadata, for: next.text, stripZeroLengthBlocks: false)
            next.metadata = repaired.normalizedMetadata
        }
        return next
    }

    private static func registerDatabaseRow(document: NoteDocument, databaseID: UUID, rowID: UUID) -> NoteDocument {
        var next = document
        if !next.metadata.databaseRowReferences.contains(where: { $0.databaseID == databaseID && $0.rowID == rowID }) {
            next.metadata.databaseRowReferences.append(
                DatabaseRowReference(databaseID: databaseID, rowID: rowID, blockID: nil)
            )
        }
        return next
    }

    private static func repair(document: NoteDocument) -> NoteDocument {
        var next = document
        let normalized = RangeNormalizer.normalize(metadata: next.metadata, for: next.text)
        next.metadata = normalized.normalizedMetadata
        return next
    }

    private static func duplicateBlock(document: NoteDocument, blockID: String) -> NoteDocument {
        guard let block = document.metadata.blocks.first(where: { $0.id == blockID }) else {
            return document
        }
        let r = block.range
        let slice = utf16Slice(text: document.text, range: r)
        guard !slice.isEmpty else { return document }

        let afterInsert = applyTextReplacement(
            document: document,
            range: TextRange(start: r.end, length: 0),
            replacement: slice
        )
        return splitBlock(document: afterInsert, blockID: blockID, atOffset: r.end)
    }

    private static func deleteBlock(document: NoteDocument, blockID: String) -> NoteDocument {
        guard let block = document.metadata.blocks.first(where: { $0.id == blockID }) else {
            return document
        }
        var next = applyTextReplacement(document: document, range: block.range, replacement: "")
        // `applyTextReplacement` no longer auto-merges empty blocks (intentionally, so that slash
        // commands can find the block by id in a subsequent changeBlockType). For deleteBlock we do
        // want to remove the now-empty block; merge it into its neighbour explicitly here.
        if let idx = next.metadata.blocks.firstIndex(where: { $0.id == blockID }) {
            guard !(idx == 0 && next.metadata.blocks.count == 1) else { return next }
            if idx > 0 {
                next.metadata.blocks[idx - 1].range = TextRange(
                    start: next.metadata.blocks[idx - 1].range.start,
                    length: next.metadata.blocks[idx - 1].range.length + next.metadata.blocks[idx].range.length
                )
            } else {
                next.metadata.blocks[idx + 1].range = TextRange(
                    start: next.metadata.blocks[idx].range.start,
                    length: next.metadata.blocks[idx + 1].range.length
                )
            }
            next.metadata.blocks.remove(at: idx)
        }
        return next
    }

    private static func utf16Slice(text: String, range: TextRange) -> String {
        let ns = text as NSString
        let len = ns.length
        let safe = range.clamped(to: len)
        guard safe.length > 0 else { return "" }
        return ns.substring(with: NSRange(location: safe.start, length: safe.length))
    }

    /// Deterministic re-parser after a full-buffer replacement. Produces a valid block partition by
    /// splitting on newlines (pass 1), then recovers block types and stable IDs from `oldBlocks`
    /// using content matching against `oldText` (pass 2).
    public static func reconcileBlocksFromText(document: NoteDocument, oldText: String, oldBlocks: [Block]) -> NoteDocument {
        var next = document
        let text = next.text
        let ns = text as NSString
        let oldNS = oldText as NSString

        // --- Pass 1: structural line split → always-valid partition ---
        let lines = text.components(separatedBy: "\n")
        var lineRanges: [TextRange] = []
        var offset = 0
        for (i, line) in lines.enumerated() {
            let length = line.utf16.count
            let includesNewline = i < lines.count - 1
            let range = TextRange(start: offset, length: includesNewline ? length + 1 : length)
            lineRanges.append(range)
            offset += range.length
        }

        // --- Build content lookup from old blocks using the old text ---
        struct OldBlockEntry {
            let block: Block
            let content: String
        }
        let oldEntries: [OldBlockEntry] = oldBlocks.map { block in
            let safe = block.range.clamped(to: oldNS.length)
            let content = safe.length > 0
                ? oldNS.substring(with: NSRange(location: safe.start, length: safe.length))
                : ""
            return OldBlockEntry(block: block, content: content)
        }
        var consumedOldIndices: Set<Int> = []

        // --- Pass 2: type recovery + stable ID assignment ---
        var recovered: [Block] = []
        for range in lineRanges {
            let lineContent = range.length > 0
                ? ns.substring(with: NSRange(location: range.start, length: range.length))
                : ""

            // Try to find an old block with matching text content (non-paragraph types first).
            var matchedOldIndex: Int?
            for (idx, entry) in oldEntries.enumerated() where !consumedOldIndices.contains(idx) {
                if entry.content == lineContent && entry.block.type != .paragraph {
                    matchedOldIndex = idx
                    break
                }
            }
            // Fall back to paragraph matches for stable ID reuse.
            if matchedOldIndex == nil {
                for (idx, entry) in oldEntries.enumerated() where !consumedOldIndices.contains(idx) {
                    if entry.content == lineContent {
                        matchedOldIndex = idx
                        break
                    }
                }
            }

            if let idx = matchedOldIndex {
                consumedOldIndices.insert(idx)
                let old = oldEntries[idx].block
                recovered.append(Block(
                    id: old.id,
                    type: old.type,
                    range: range,
                    level: old.level,
                    icon: old.icon
                ))
            } else {
                recovered.append(Block(
                    id: UUID().uuidString,
                    type: .paragraph,
                    range: range,
                    level: nil,
                    icon: nil
                ))
            }
        }

        if !recovered.isEmpty {
            next.metadata.blocks = recovered
        }
        return next
    }

    /// Adjusts block ranges after a UTF-16 text replacement without calling `RangeNormalizer.normalize`.
    /// All cases that arise during normal editing are handled deterministically:
    ///   - Single-block edits: delta-adjust the affected block and shift following blocks.
    ///   - Zero-length result: the empty block is preserved as a valid structural unit so that a
    ///     subsequent `changeBlockType` in the same command batch can still find it by ID. Only an
    ///     explicit `mergeWithPrevious` (or `deleteBlock`) should remove blocks.
    ///   - Multi-block replacement: collapse all intersecting blocks into the first, shift the rest.
    ///   - Out-of-bounds edit: should not occur during normal editing; logged and returns current blocks unchanged.
    ///
    /// Exposed for unit tests (`@testable import`); production callers use `apply(.replaceText, ...)`.
    static func adjustBlocks(
        blocks: [Block],
        replacedRange: TextRange,
        replacementUTF16Length: Int,
        text: String,
        contextMetadata: NoteMetadata
    ) -> [Block] {
        let delta = replacementUTF16Length - replacedRange.length
        let totalLength = RangeNormalizer.utf16Length(of: text)

        // Find all blocks that are affected by this edit:
        // - Insertions (zero-length) affect exactly one block — the one that contains the insertion
        //   point, or whose end equals it (handles block-boundary insertions).
        // - Replacements (non-zero) affect all blocks whose ranges overlap the replaced range.
        let intersecting: [Int]
        if replacedRange.isEmpty {
            // Insertion: `intersects` is always false for empty ranges; use contains/end check.
            if let idx = blocks.indices.first(where: {
                blocks[$0].range.contains(replacedRange.start) || blocks[$0].range.end == replacedRange.start
            }) {
                intersecting = [idx]
            } else {
                intersecting = []
            }
        } else {
            intersecting = blocks.indices.filter { blocks[$0].range.intersects(replacedRange) }
        }

        guard let firstIntersectingIndex = intersecting.first else {
            // Edit offset is entirely outside all blocks — should not happen in normal editing.
            assertionFailure("adjustBlocks: no block found for edit at \(replacedRange.start)–\(replacedRange.end) (text length \(totalLength)); blocks: \(blocks.map { $0.range })")
            return blocks
        }

        var next = blocks

        if intersecting.count == 1 {
            // Common case: edit within or at boundary of a single block.
            let i = firstIntersectingIndex
            let old = next[i]
            let newLength = max(0, old.range.length + delta)
            next[i].range = TextRange(start: old.range.start, length: newLength)

            // Shift all subsequent blocks.
            for j in (i + 1)..<next.count {
                next[j].range = TextRange(start: max(0, next[j].range.start + delta), length: next[j].range.length)
            }
            // A block that becomes zero-length is intentionally preserved as an empty structural unit.
            // It represents a valid empty line or a block whose content was just cleared (e.g. after a
            // slash-command token is removed). Only an explicit `mergeWithPrevious` command should merge
            // blocks; auto-merging here would destroy the block before a subsequent `changeBlockType`
            // command in the same batch can find it by ID.
        } else {
            // Multi-block replacement: collapse all intersecting blocks into the first one,
            // preserving the first block's id and type. Shift remaining blocks by delta.
            let lastIntersectingIndex = intersecting.last!
            let firstBlock = next[firstIntersectingIndex]
            let lastBlock = next[lastIntersectingIndex]
            // Content before the replaced range (from firstBlock's start) + replacement + content after (from lastBlock's end).
            let prefixLen = max(0, replacedRange.start - firstBlock.range.start)
            let suffixLen = max(0, lastBlock.range.end - replacedRange.end)
            let newLength = prefixLen + replacementUTF16Length + suffixLen
            next[firstIntersectingIndex].range = TextRange(start: firstBlock.range.start, length: newLength)

            // Remove all other intersecting blocks (in reverse order to preserve indices).
            for i in intersecting.dropFirst().reversed() {
                next.remove(at: i)
            }

            // Shift all blocks after the (now collapsed) first block.
            let shiftFrom = firstIntersectingIndex + 1
            for j in shiftFrom..<next.count {
                next[j].range = TextRange(start: max(0, next[j].range.start + delta), length: next[j].range.length)
            }
        }

        // Final clamp to new text length (defensive — should be a no-op for well-formed input).
        return next.map { block in
            var adjusted = block
            adjusted.range = block.range.clamped(to: totalLength)
            return adjusted
        }
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

import Foundation
import MiranNotesCore

enum DocumentLayoutController {
    static func commandsForEdit(
        document: NoteDocument,
        affectedRange: NSRange,
        replacement: String,
        selectedLocation: Int
    ) -> [EditCommand]? {
        let isInsertion = affectedRange.length == 0 && !replacement.isEmpty
        let isBackspaceDelete = replacement.isEmpty && affectedRange.length == 1

        if isInsertion, replacement == "\n" {
            if let selectedBlockIndex = blockIndex(at: selectedLocation, blocks: document.metadata.blocks) {
                let selectedBlock = document.metadata.blocks[selectedBlockIndex]
                if selectedBlock.type == .listItem,
                   isBlockTextEmpty(selectedBlock, in: document.text) {
                    return [
                        .changeBlockType(blockID: selectedBlock.id, type: .paragraph, headingLevel: nil)
                    ]
                }
            }

            // Match `EditCommandEngine.adjustBlocks`: insertion at offset O is attributed to the first block
            // where `contains(O) || end == O`. That is the *previous* block at an inter-block boundary, not the
            // following one — splitting the wrong block produced duplicate `range.start` values and tripped
            // `NoteIntegrity` (blocksNotSorted).
            guard let blockIndex = blockIndexMatchingTextEngineInsertion(at: affectedRange.location, blocks: document.metadata.blocks) else {
                return nil
            }
            let block = document.metadata.blocks[blockIndex]
            let insert = EditCommand.replaceText(
                range: TextRange(start: affectedRange.location, length: 0),
                replacement: "\n"
            )
            let p = affectedRange.location
            let isBetweenExistingBlocks = (p == block.range.end && blockIndex < document.metadata.blocks.count - 1)
            if isBetweenExistingBlocks {
                return [insert]
            }
            let split = EditCommand.splitBlock(blockID: block.id, atOffset: p + 1)
            return [insert, split]
        }

        guard let blockIndex = blockIndex(at: selectedLocation, blocks: document.metadata.blocks) else {
            return nil
        }

        let block = document.metadata.blocks[blockIndex]

        if isBackspaceDelete,
           selectedLocation == block.range.start,
           blockIndex > 0,
           charBefore(offset: selectedLocation, in: document.text) == "\n" {
            let merge = EditCommand.mergeWithPrevious(blockID: block.id)
            let deleteNewline = EditCommand.replaceText(
                range: TextRange(start: affectedRange.location, length: affectedRange.length),
                replacement: ""
            )
            return [merge, deleteNewline]
        }

        return nil
    }

    /// Same rule as `EditCommandEngine.adjustBlocks` for which block owns an insertion at `utf16Offset`.
    private static func blockIndexMatchingTextEngineInsertion(at utf16Offset: Int, blocks: [Block]) -> Int? {
        blocks.firstIndex { $0.range.contains(utf16Offset) || $0.range.end == utf16Offset }
    }

    static func blockIndex(at utf16Offset: Int, blocks: [Block]) -> Int? {
        for (index, block) in blocks.enumerated() {
            if block.range.contains(utf16Offset) {
                return index
            }
        }
        if let last = blocks.indices.last, utf16Offset == blocks[last].range.end {
            return last
        }
        return nil
    }

    private static func charBefore(offset: Int, in text: String) -> Character? {
        guard offset > 0 else { return nil }
        let nsRange = NSRange(location: offset - 1, length: 1)
        guard let range = Range(nsRange, in: text) else { return nil }
        return text[range].first
    }

    private static func isBlockTextEmpty(_ block: Block, in text: String) -> Bool {
        let ns = text as NSString
        let len = ns.length
        let start = min(max(0, block.range.start), len)
        let end = min(max(start, block.range.end), len)
        let content = ns.substring(with: NSRange(location: start, length: end - start))
        return content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

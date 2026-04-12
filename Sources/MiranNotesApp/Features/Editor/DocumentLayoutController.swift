import Foundation
import MiranNotesCore

enum DocumentLayoutController {
    static func commandsForEdit(
        document: NoteDocument,
        affectedRange: NSRange,
        replacement: String,
        selectedLocation: Int
    ) -> [EditCommand]? {
        guard let blockIndex = blockIndex(at: selectedLocation, blocks: document.metadata.blocks) else {
            return nil
        }

        let block = document.metadata.blocks[blockIndex]
        let isInsertion = affectedRange.length == 0 && !replacement.isEmpty
        let isBackspaceDelete = replacement.isEmpty && affectedRange.length == 1

        if isInsertion, replacement == "\n" {
            let insert = EditCommand.replaceText(
                range: TextRange(start: affectedRange.location, length: 0),
                replacement: "\n"
            )
            let split = EditCommand.splitBlock(blockID: block.id, atOffset: affectedRange.location + 1)
            return [insert, split]
        }

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
}

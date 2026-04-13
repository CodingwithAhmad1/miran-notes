import Foundation
import MiranNotesCore

enum DocumentLayoutController {
    @MainActor
    static func commandsForEdit(
        document: NoteDocument,
        affectedRange: NSRange,
        replacement: String,
        selectedLocation: Int
    ) -> [EditCommand]? {
        let isInsertion = affectedRange.length == 0 && !replacement.isEmpty
        let isBackspaceDelete = replacement.isEmpty && affectedRange.length == 1

        if isInsertion, replacement == "\n" {
            // Use the text-engine insertion rule so we identify the same block that adjustBlocks would.
            if let selectedBlockIndex = blockIndexMatchingTextEngineInsertion(at: selectedLocation, blocks: document.metadata.blocks) {
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

            // Newline-commit slash command: if the line from block start to the cursor is a registered
            // slash token (e.g. "/h1\n"), combine the slash commands with the structural split so that
            // the Enter key both applies the command and creates the new paragraph block below.
            if let slashCommands = slashCommandsForNewlineCommit(
                document: document,
                block: block,
                cursorUTF16: affectedRange.location
            ) {
                // Simple slash commands (e.g. /h1) only delete the token and change the block type,
                // leaving the block empty. We can safely append a newline insert + split at the
                // (now stable) block start to create the new paragraph below.
                //
                // Multi-step commands (e.g. /task, /session) insert additional text after deleting
                // the token, which shifts UTF-16 offsets. Appending structural commands with pre-
                // computed offsets would corrupt the document. For these, return only the slash
                // commands -- the user presses Enter again for the next line.
                let replaceTextCount = slashCommands.filter {
                    if case .replaceText = $0 { return true }; return false
                }.count
                if replaceTextCount > 1 {
                    return slashCommands
                }
                let lineStart = block.range.start
                let newlineInsert = EditCommand.replaceText(
                    range: TextRange(start: lineStart, length: 0),
                    replacement: "\n"
                )
                let split = EditCommand.splitBlock(blockID: block.id, atOffset: lineStart + 1)
                return slashCommands + [newlineInsert, split]
            }

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

        // Backspace path uses blockIndex (contains semantics) because the cursor is at block.range.start,
        // which is *inside* the block's range. blockIndexMatchingTextEngineInsertion would return the
        // *preceding* block at that boundary, which would make the merge target check fail.
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
    /// Uses `range.end == offset` as a tiebreaker at block boundaries, so the block that *ends* at the
    /// insertion point is preferred over the block that *starts* there. This matches adjustBlocks ownership
    /// and must be used whenever resolving a block for an insertion-point event (slash commands, bullet
    /// triggers, list-exit checks).
    static func blockIndexMatchingTextEngineInsertion(at utf16Offset: Int, blocks: [Block]) -> Int? {
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

    /// If the text from `block.range.start` to `cursorUTF16` is exactly a registered slash token (e.g.
    /// "/h1"), returns the corresponding edit commands (changeBlockType + replaceText to delete the
    /// token). Returns nil if the line doesn't start with "/" or the token doesn't match any command.
    ///
    /// This is used by the newline-commit path so that pressing Enter after "/h1" applies the slash
    /// command and creates the new paragraph below — the same behaviour as committing with Space.
    @MainActor
    private static func slashCommandsForNewlineCommit(
        document: NoteDocument,
        block: Block,
        cursorUTF16: Int
    ) -> [EditCommand]? {
        let lineStart = block.range.start
        guard cursorUTF16 > lineStart else { return nil }

        let ns = document.text as NSString
        guard lineStart < ns.length else { return nil }

        let firstChar = ns.substring(with: NSRange(location: lineStart, length: 1))
        guard firstChar == "/" else { return nil }

        let tokenLen = cursorUTF16 - lineStart
        guard tokenLen >= 2 else { return nil } // need at least "/x"

        let tokenWithSlash = ns.substring(with: NSRange(location: lineStart, length: tokenLen))
        let tokenWithoutSlash = String(tokenWithSlash.dropFirst())
        guard !tokenWithoutSlash.isEmpty else { return nil }

        let match = SlashCommitMatch(
            lineStartUTF16: lineStart,
            commitUTF16Index: cursorUTF16,
            commitCharacter: .newline,
            tokenWithoutSlash: tokenWithoutSlash
        )
        return SlashCommandRegistry.editCommands(for: match, blockID: block.id, blockType: block.type)
    }
}

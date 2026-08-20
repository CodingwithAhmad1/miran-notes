import Foundation
import MiranNotesCore

/// Stored undo boundary: full snapshot, or replace-text-only chain (inverse commands for hybrid undo).
enum UndoCheckpoint {
    case full(NoteDocument)
    case replaceTextOnly(forward: [EditCommand], undoCommands: [EditCommand])
}

enum UndoCheckpointSupport {
    static func materialize(checkpoints: [UndoCheckpoint], at index: Int) -> NoteDocument {
        switch checkpoints[index] {
        case .full(let d):
            return d
        case .replaceTextOnly(let forward, _):
            var doc = materialize(checkpoints: checkpoints, at: index - 1)
            for c in forward {
                doc = EditCommandEngine.apply(c, to: doc)
            }
            return doc
        }
    }

    static func checkpointForRecordedStep(
        after: NoteDocument,
        before: NoteDocument,
        intercepted: [EditCommand]
    ) -> UndoCheckpoint {
        if let chain = UndoInverseSupport.replaceTextChainUndoCommands(forward: intercepted, documentBefore: before),
           chain.after == after {
            return .replaceTextOnly(forward: intercepted, undoCommands: chain.undoCommands)
        }
        return .full(after)
    }
}

enum UndoActionNaming {
    static func isSingleReplaceTextOnly(_ commands: [EditCommand]) -> Bool {
        guard commands.count == 1, case .replaceText = commands[0] else { return false }
        return true
    }

    static func actionName(for commands: [EditCommand]) -> String {
        if commands.count >= 2 {
            let head = Array(commands.prefix(2))
            if head.count == 2 {
                switch (head[0], head[1]) {
                case let (.replaceText(range, replacement), .splitBlock):
                    if range.length == 0, replacement == "\n" {
                        return "Split Block"
                    }
                case (.mergeWithPrevious, .replaceText):
                    return "Merge Blocks"
                case let (.replaceText(range, replacement), .changeBlockType):
                    if replacement.isEmpty, range.length > 0 {
                        return "Slash Command"
                    }
                case (.replaceText, .replaceMetadataBlocks):
                    return "Full Buffer Edit"
                default:
                    break
                }
            }
        }

        let kinds = Set(commands.map { command -> String in
            switch command {
            case .replaceText: return "Edit"
            case .splitBlock: return "Split Block"
            case .mergeWithPrevious: return "Merge Blocks"
            case .changeBlockType: return "Change Block"
            case .toggleSpanStyle: return "Toggle Style"
            case .insertWikiLink: return "Insert Link"
            case .setProperty: return "Edit Properties"
            case .setBlockDone: return "Toggle Task"
            case .repairMetadata: return "Repair Note"
            case .replaceMetadataBlocks: return "Recover Blocks"
            case .duplicateBlock: return "Duplicate Block"
            case .deleteBlock: return "Delete Block"
            }
        })
        if kinds.count == 1, let only = kinds.first {
            return only
        }
        return "Edit"
    }
}

import Foundation

/// Hybrid-undo helper: inverse of a single ``EditCommand/replaceText`` for snapshot-based undo systems.
public enum UndoInverseSupport {
    /// When the batch is exactly one `replaceText`, returns commands that restore `documentBefore.text` when applied to the post-edit document.
    /// Returns `nil` for structural commands or multi-command batches.
    public static func inverseCommands(for commands: [EditCommand], documentBefore: NoteDocument) -> [EditCommand]? {
        guard commands.count == 1, case let .replaceText(range, replacement) = commands[0] else { return nil }
        let ns = documentBefore.text as NSString
        let len = ns.length
        guard range.start >= 0, range.length >= 0, range.start + range.length <= len else { return nil }
        let oldSlice = ns.substring(with: NSRange(location: range.start, length: range.length))
        let newLen = (replacement as NSString).length
        let inverseRange = TextRange(start: range.start, length: newLen)
        return [.replaceText(range: inverseRange, replacement: oldSlice)]
    }

    /// When every command is ``EditCommand/replaceText``, returns the final document and a flat undo list:
    /// applying ``undoCommands`` in order to `after` yields `documentBefore`.
    public static func replaceTextChainUndoCommands(
        forward: [EditCommand],
        documentBefore: NoteDocument
    ) -> (after: NoteDocument, undoCommands: [EditCommand])? {
        var doc = documentBefore
        var undoCommands: [EditCommand] = []
        for c in forward {
            guard case .replaceText = c else { return nil }
            guard let inv = inverseCommands(for: [c], documentBefore: doc) else { return nil }
            doc = EditCommandEngine.apply(c, to: doc)
            undoCommands.insert(contentsOf: inv, at: 0)
        }
        return (doc, undoCommands)
    }
}

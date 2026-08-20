// In-note find next/previous and replace (find bar under the note header).
import Foundation
import MiranNotesCore

extension AppModel {
    func findMatches(forPane pane: Int) -> [MiranNotesCore.TextRange] {
        guard workspacePanes.indices.contains(pane), let doc = workspacePanes[pane].activeDocument else { return [] }
        return NoteFindController.matches(of: workspacePanes[pane].editorFindQuery, in: doc.text)
    }

    /// 1-based index of the match at/after the caret, for "2 of 7" display. 0 when none.
    func currentFindMatchOrdinal(forPane pane: Int, matches: [MiranNotesCore.TextRange]) -> Int {
        guard workspacePanes.indices.contains(pane), !matches.isEmpty else { return 0 }
        let selection = workspacePanes[pane].editorTextSelection
        if let exact = matches.firstIndex(where: { $0.start == selection.start && $0.length == selection.length }) {
            return exact + 1
        }
        return (NoteFindController.nextMatchIndex(matches: matches, fromCaret: selection.start) ?? 0) + 1
    }

    func findNext(pane: Int) {
        jumpToFindMatch(pane: pane) { matches, caret in
            NoteFindController.nextMatchIndex(matches: matches, fromCaret: caret + 1)
        }
    }

    func findPrevious(pane: Int) {
        jumpToFindMatch(pane: pane) { matches, caret in
            NoteFindController.previousMatchIndex(matches: matches, fromCaret: caret)
        }
    }

    /// Replaces the currently selected match (or the next one) in one undo step, then advances.
    func replaceCurrentFindMatch(with replacement: String, pane: Int) {
        guard workspacePanes.indices.contains(pane), workspacePanes[pane].activeDocument != nil else { return }
        let matches = findMatches(forPane: pane)
        guard !matches.isEmpty else { return }
        let selection = workspacePanes[pane].editorTextSelection
        let target = matches.first(where: { $0.start == selection.start && $0.length == selection.length })
            ?? matches[NoteFindController.nextMatchIndex(matches: matches, fromCaret: selection.start) ?? 0]
        if pane != activePaneIndex { activatePaneForEditingSync(pane) }
        let newDoc = apply([.replaceText(range: target, replacement: replacement)])
        pendingEditorScroll = nil
        // Jump to the next remaining match after the replacement.
        let after = NoteFindController.matches(of: workspacePanes[pane].editorFindQuery, in: newDoc.text)
        if let idx = NoteFindController.nextMatchIndex(matches: after, fromCaret: target.start + replacement.utf16.count) {
            pendingEditorScroll = PendingEditorScroll(noteID: newDoc.metadata.noteID, range: after[idx])
        }
    }

    /// Replaces every match in one atomic batch = one undo step.
    func replaceAllFindMatches(with replacement: String, pane: Int) {
        guard workspacePanes.indices.contains(pane) else { return }
        let matches = findMatches(forPane: pane)
        guard !matches.isEmpty else { return }
        if pane != activePaneIndex { activatePaneForEditingSync(pane) }
        _ = apply(NoteFindController.replacementCommands(matches: matches, replacement: replacement))
    }

    private func jumpToFindMatch(
        pane: Int,
        pick: ([MiranNotesCore.TextRange], Int) -> Int?
    ) {
        guard workspacePanes.indices.contains(pane), let doc = workspacePanes[pane].activeDocument else { return }
        let matches = findMatches(forPane: pane)
        let caret = workspacePanes[pane].editorTextSelection.start
        guard let idx = pick(matches, caret) else { return }
        pendingEditorScroll = PendingEditorScroll(noteID: doc.metadata.noteID, range: matches[idx])
    }
}

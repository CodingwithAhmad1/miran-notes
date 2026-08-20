// Wiki-link navigation, autocomplete candidates, and create-from-link (knowledge layer).
import Foundation
import MiranNotesCore

extension AppModel {
    /// Opens the target of a clicked wiki link; explains dangling targets instead of failing silently.
    func openWikiLink(targetNoteID: UUID, pane: Int? = nil) {
        let pane = pane ?? activePaneIndex
        guard noteSummaries.contains(where: { $0.noteID == targetNoteID }) else {
            userAlert = .message(
                "The linked note isn’t in this vault anymore. It may have been deleted, or the link was created in a different vault."
            )
            return
        }
        activatePane(index: pane)
        openNote(noteID: targetNoteID, pane: pane)
    }

    /// Ranked note candidates for the `[[` autocomplete popover (title match beats path match; capped at 8).
    /// The current note is excluded, and a "Create" row is appended when no title matches the query exactly.
    func wikiLinkMenuEntries(matching query: String, pane: Int? = nil) -> [WikiLinkMenuEntry] {
        let pane = pane ?? activePaneIndex
        let currentNoteID = workspacePanes.indices.contains(pane) ? workspacePanes[pane].selectedNoteID : nil
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let q = trimmed.lowercased()

        let pool = noteSummaries.filter { $0.noteID != currentNoteID }
        let ranked: [(score: Int, summary: NoteSummary)]
        if q.isEmpty {
            ranked = pool.map { (4, $0) }
        } else {
            ranked = pool.compactMap { summary in
                let title = summary.title.lowercased()
                if title == q { return (0, summary) }
                if title.hasPrefix(q) { return (1, summary) }
                if title.contains(q) { return (2, summary) }
                if summary.relativePath.lowercased().contains(q) { return (3, summary) }
                return nil
            }
        }
        let top = ranked
            .sorted {
                if $0.score != $1.score { return $0.score < $1.score }
                return $0.summary.title.localizedCaseInsensitiveCompare($1.summary.title) == .orderedAscending
            }
            .prefix(8)

        var entries: [WikiLinkMenuEntry] = top.map {
            .note(noteID: $0.summary.noteID, title: $0.summary.title, relativePath: $0.summary.relativePath)
        }
        if !trimmed.isEmpty,
           canCreateWikiLinkTarget(pane: pane),
           !top.contains(where: { $0.summary.title.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            entries.append(.create(title: trimmed))
        }
        return entries
    }

    /// Creates a titled note in the current note's folder (no navigation) and reports its `noteID`,
    /// so the editor can commit an `insertWikiLink` pointing at it. `nil` on failure (alert already shown).
    func createWikiLinkTarget(title: String, pane: Int? = nil, completion: @escaping @MainActor (UUID?) -> Void) {
        let pane = pane ?? activePaneIndex
        guard let folderID = wikiLinkCreationFolderID(pane: pane) else {
            userAlert = .message("Can’t create a linked note here: the current folder doesn’t accept notes.")
            completion(nil)
            return
        }
        let bodyExtension = resolvedBodyExtensionForNewNote(in: folderID)
            ?? resolvedBodyFileExtensionForSelectedNote(pane: pane)
        Task { @MainActor in
            do {
                let (document, _) = try await repository.createNote(
                    named: title,
                    folderID: folderID,
                    bodyFileExtension: bodyExtension
                )
                await refreshNotes()
                completion(document.metadata.noteID)
            } catch {
                userAlert = .message("Could not create the linked note: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    private func canCreateWikiLinkTarget(pane: Int) -> Bool {
        wikiLinkCreationFolderID(pane: pane) != nil
    }

    /// Folder for a note created from a `[[` link: the current note's folder when it accepts notes.
    private func wikiLinkCreationFolderID(pane: Int) -> UUID? {
        guard workspacePanes.indices.contains(pane) else { return nil }
        let folderID: UUID?
        if let noteID = workspacePanes[pane].selectedNoteID,
           let summary = noteSummaries.first(where: { $0.noteID == noteID }) {
            folderID = summary.folderID
        } else {
            folderID = workspacePanes[pane].selectedFolderID
        }
        guard let folderID, folderID != FolderCatalog.rootFolderID || hasRootLevelNotes else { return nil }
        guard folderCatalog.allowsNotes(in: folderID) else { return nil }
        return folderID
    }
}

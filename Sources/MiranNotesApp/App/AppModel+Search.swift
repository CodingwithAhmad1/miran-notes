// Note filtering, vault search (title/path/body), snippets, body-index scheduling.
import AppKit
import Foundation
import MiranNotesCore
import Observation
import os.log
import SwiftUI

/// How a note matched the vault search query; lower ranks sort first.
enum NoteSearchMatchKind: Int, Comparable {
    case title = 0
    case path = 1
    case body = 2

    static func < (lhs: NoteSearchMatchKind, rhs: NoteSearchMatchKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension AppModel {
    func scheduleBodySearchIndexRebuild() {
        bodySearchIndex = [:]
        isBodySearchIndexBuilding = true
        bodySearchIndexController.scheduleRebuild(
            repository: repository,
            apply: { [weak self] indexes in
                guard let self else { return }
                self.bodySearchIndex = indexes.bodies
                self.tagIndex = indexes.tags
                self.isBodySearchIndexBuilding = false
            },
            onFailure: { [weak self] in
                guard let self else { return }
                self.isBodySearchIndexBuilding = false
                self.userAlert = .recoverable(
                    message: "Could not update text search for this library.",
                    kind: .retryBodySearchIndex
                )
            }
        )
    }

    /// Body-text preview for a search result (context around the first match), nil when the
    /// match is title/path-only or the body index hasn't caught up yet.
    func searchSnippet(for summary: NoteSummary) -> String? {
        searchSnippet(for: summary, pane: activePaneIndex)
    }

    func searchSnippet(for summary: NoteSummary, pane: Int) -> String? {
        guard workspacePanes.indices.contains(pane) else { return nil }
        let q = workspacePanes[pane].vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let body = bodySearchIndex[summary.noteID] else { return nil }
        let snippet = SearchSnippetBuilder.snippet(for: q, in: body)
        return snippet.isEmpty ? nil : snippet
    }

    var filteredNoteSummaries: [NoteSummary] {
        filteredNoteSummaries(forPane: activePaneIndex)
    }

    func filteredNoteSummaries(forPane pane: Int) -> [NoteSummary] {
        let q = workspacePanes[pane].vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return noteSummaries }
        return noteSummaries.filter { searchMatchKind($0, queryLowercased: q) != nil }
    }

    /// Vault-wide note rows matching the pane's vault search, ranked title > path > body match.
    var vaultSearchMatchingNoteSummaries: [NoteSummary] {
        vaultSearchMatchingNoteSummaries(forPane: activePaneIndex)
    }

    func vaultSearchMatchingNoteSummaries(forPane pane: Int) -> [NoteSummary] {
        let q = workspacePanes[pane].vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return noteSummaries
            .compactMap { summary -> (NoteSearchMatchKind, NoteSummary)? in
                guard let kind = searchMatchKind(summary, queryLowercased: q) else { return nil }
                return (kind, summary)
            }
            .sorted {
                if $0.0 != $1.0 { return $0.0 < $1.0 }
                return $0.1.title.localizedCaseInsensitiveCompare($1.1.title) == .orderedAscending
            }
            .map(\.1)
    }

    /// Secondary line for vault search results (folder label and path).
    func vaultSearchResultSubtitle(for summary: NoteSummary) -> String {
        let folderLabel =
            summary.folderID == FolderCatalog.rootFolderID ? "Vault"
            : (folderCatalog.folder(id: summary.folderID)?.name ?? "Folder")
        return "\(folderLabel) — \(summary.relativePath)"
    }

    /// Title and path match from summaries; body match from the background ``bodySearchIndex``
    /// (built by `NoteBodySearchIndexController`; results may lag a rebuild by a moment).
    /// A `#tag` query matches only notes whose tags start with the typed tag.
    func searchMatchKind(_ summary: NoteSummary, queryLowercased q: String) -> NoteSearchMatchKind? {
        if q.hasPrefix("#") {
            let tagQuery = NoteTags.normalize(q)
            guard !tagQuery.isEmpty else { return nil }
            let tags = tagIndex[summary.noteID] ?? []
            return tags.contains(where: { $0.hasPrefix(tagQuery) }) ? .title : nil
        }
        if summary.title.lowercased().contains(q) { return .title }
        if summary.relativePath.lowercased().contains(q) { return .path }
        if let body = bodySearchIndex[summary.noteID],
           body.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return .body
        }
        return nil
    }
}

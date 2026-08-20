// Quick-open palette results (⌘P): ranked search over all notes; pinned + recents when idle.
import Foundation

/// One row in the quick-open palette.
struct QuickOpenResult: Identifiable, Equatable {
    enum Section: Equatable {
        case pinned
        case recent
        case match
    }

    var id: UUID { noteID }
    var noteID: UUID
    var title: String
    var relativePath: String
    var snippet: String?
    var section: Section
}

extension AppModel {
    /// Empty query: pinned notes then recents. Otherwise: notes ranked title > path > body,
    /// with a body-context snippet where the body matched.
    func quickOpenResults(query: String) -> [QuickOpenResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let pinned = pinnedNoteSummaries.map {
                QuickOpenResult(noteID: $0.noteID, title: $0.title, relativePath: $0.relativePath, snippet: nil, section: .pinned)
            }
            let recents = recentNoteSummaries.prefix(8).map {
                QuickOpenResult(noteID: $0.noteID, title: $0.title, relativePath: $0.relativePath, snippet: nil, section: .recent)
            }
            return pinned + recents
        }

        let q = trimmed.lowercased()
        return noteSummaries
            .compactMap { summary -> (NoteSearchMatchKind, NoteSummary)? in
                guard let kind = searchMatchKind(summary, queryLowercased: q) else { return nil }
                return (kind, summary)
            }
            .sorted {
                if $0.0 != $1.0 { return $0.0 < $1.0 }
                return $0.1.title.localizedCaseInsensitiveCompare($1.1.title) == .orderedAscending
            }
            .prefix(12)
            .map { kind, summary in
                var snippet: String?
                if kind == .body, let body = bodySearchIndex[summary.noteID] {
                    let s = SearchSnippetBuilder.snippet(for: trimmed, in: body)
                    snippet = s.isEmpty ? nil : s
                }
                return QuickOpenResult(
                    noteID: summary.noteID,
                    title: summary.title,
                    relativePath: summary.relativePath,
                    snippet: snippet,
                    section: .match
                )
            }
    }

    func openQuickOpenResult(_ result: QuickOpenResult) {
        quickOpen.dismiss()
        openNote(noteID: result.noteID, pane: activePaneIndex)
    }
}

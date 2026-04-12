import Foundation

struct SlashCommandMatch: Equatable {
    var item: SlashCommandCatalogItem
    var score: Int
}

enum SlashCommandMatcher {
    static func filterAndRank(
        query: String,
        catalog: [SlashCommandCatalogItem]
    ) -> [SlashCommandMatch] {
        let normalized = normalize(query)
        if normalized.isEmpty {
            return catalog.map { SlashCommandMatch(item: $0, score: 0) }
        }

        var matches: [SlashCommandMatch] = []
        for item in catalog {
            if let score = score(item: item, query: normalized) {
                matches.append(SlashCommandMatch(item: item, score: score))
            }
        }

        return matches.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.item.title.localizedCaseInsensitiveCompare($1.item.title) == .orderedAscending
        }
    }

    private static func score(item: SlashCommandCatalogItem, query: String) -> Int? {
        let id = normalize(item.id)
        let title = normalize(item.title)
        let aliases = item.aliases.map(normalize)
        let keywords = item.keywords.map(normalize)

        if id.hasPrefix(query) { return 500 }
        if aliases.contains(where: { $0.hasPrefix(query) }) { return 460 }
        if title.hasPrefix(query) { return 430 }
        if id.contains(query) { return 340 }
        if aliases.contains(where: { $0.contains(query) }) { return 300 }
        if keywords.contains(where: { $0.hasPrefix(query) }) { return 260 }
        if keywords.contains(where: { $0.contains(query) }) { return 230 }
        if title.contains(query) { return 210 }

        return nil
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

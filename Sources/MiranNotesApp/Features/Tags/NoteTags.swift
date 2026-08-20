import Foundation
import MiranNotesCore

/// Tag convention on `NoteMetadata.properties`: `properties["tags"]` holds a comma-joined,
/// lowercased, deduplicated list (`"project,ideas,swift"`). Parsing is tolerant of whitespace
/// and stray `#` prefixes typed by the user.
enum NoteTags {
    static let propertyKey = "tags"

    static func parse(_ properties: [String: String]) -> [String] {
        parseList(properties[propertyKey] ?? "")
    }

    static func parseList(_ raw: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for piece in raw.split(separator: ",") {
            let tag = normalize(String(piece))
            guard !tag.isEmpty, !seen.contains(tag) else { continue }
            seen.insert(tag)
            result.append(tag)
        }
        return result
    }

    /// nil when the list is empty so the property is removed rather than stored as `""`.
    static func serialized(_ tags: [String]) -> String? {
        let cleaned = parseList(tags.joined(separator: ","))
        return cleaned.isEmpty ? nil : cleaned.joined(separator: ",")
    }

    static func normalize(_ raw: String) -> String {
        var tag = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while tag.hasPrefix("#") { tag.removeFirst() }
        return tag.replacingOccurrences(of: ",", with: "")
    }
}

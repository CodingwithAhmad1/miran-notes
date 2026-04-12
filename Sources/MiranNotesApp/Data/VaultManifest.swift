import Foundation
import MiranNotesCore

/// Maps `noteID` ↔ current `baseName` for O(1) resolution after renames.
struct VaultManifest: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var entries: [ManifestEntry]

    init(schemaVersion: Int = currentSchemaVersion, entries: [ManifestEntry] = []) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    func entry(noteID: UUID) -> ManifestEntry? {
        entries.first { $0.noteID == noteID }
    }

    func entry(baseName: String) -> ManifestEntry? {
        entries.first { $0.baseName == baseName }
    }

    mutating func upsert(noteID: UUID, baseName: String, title: String?) {
        if let i = entries.firstIndex(where: { $0.noteID == noteID }) {
            entries[i].baseName = baseName
            entries[i].title = title
        } else {
            entries.append(ManifestEntry(noteID: noteID, baseName: baseName, title: title))
        }
    }

    mutating func remove(noteID: UUID) {
        entries.removeAll { $0.noteID == noteID }
    }
}

struct ManifestEntry: Codable, Equatable, Hashable {
    var noteID: UUID
    var baseName: String
    var title: String?
}

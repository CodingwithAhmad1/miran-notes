import Foundation
import MiranNotesCore

/// Maps `noteID` ↔ current relative path for O(1) resolution after renames.
struct VaultManifest: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var entries: [ManifestEntry]

    init(schemaVersion: Int = currentSchemaVersion, entries: [ManifestEntry] = []) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    func entry(noteID: UUID) -> ManifestEntry? {
        entries.first { $0.noteID == noteID }
    }

    func entry(relativePath: String) -> ManifestEntry? {
        entries.first { $0.relativePath == relativePath }
    }

    /// Legacy alias used while migrating call sites.
    func entry(baseName: String) -> ManifestEntry? {
        entry(relativePath: baseName)
    }

    mutating func upsert(noteID: UUID, relativePath: String, title: String?) {
        if let i = entries.firstIndex(where: { $0.noteID == noteID }) {
            entries[i].relativePath = relativePath
            entries[i].title = title
        } else {
            entries.append(ManifestEntry(noteID: noteID, relativePath: relativePath, title: title))
        }
    }

    mutating func remove(noteID: UUID) {
        entries.removeAll { $0.noteID == noteID }
    }
}

struct ManifestEntry: Codable, Equatable, Hashable {
    var noteID: UUID
    /// Path under the vault root without extension, e.g. `notes/alpha` or flat `alpha`.
    var relativePath: String
    var title: String?

    enum CodingKeys: String, CodingKey {
        case noteID
        case relativePath
        case title
        case baseName
    }

    init(noteID: UUID, relativePath: String, title: String?) {
        self.noteID = noteID
        self.relativePath = relativePath
        self.title = title
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noteID = try c.decode(UUID.self, forKey: .noteID)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        if let rp = try c.decodeIfPresent(String.self, forKey: .relativePath) {
            relativePath = rp
        } else if let bn = try c.decodeIfPresent(String.self, forKey: .baseName) {
            relativePath = bn
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing relativePath/baseName")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(noteID, forKey: .noteID)
        try c.encode(relativePath, forKey: .relativePath)
        try c.encodeIfPresent(title, forKey: .title)
    }
}

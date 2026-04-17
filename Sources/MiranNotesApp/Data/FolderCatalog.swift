import Foundation
import MiranNotesCore

struct FolderCatalog: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2
    static let rootFolderID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var schemaVersion: Int
    var folders: [FolderEntry]
    var isDirty: Bool = false

    enum CodingKeys: String, CodingKey {
        case schemaVersion, folders
    }

    init(schemaVersion: Int = currentSchemaVersion, folders: [FolderEntry] = [FolderEntry.root]) {
        self.schemaVersion = schemaVersion
        self.folders = folders
    }

    mutating func ensureRoot() {
        if !folders.contains(where: { $0.id == Self.rootFolderID }) {
            folders.insert(.root, at: 0)
            isDirty = true
        }
        ensureStorageSegments()
    }
}

struct FolderEntry: Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Stable on-disk segment used for directory layout (independent from display `name`).
    var storageSegment: String
    var parentFolderID: UUID?

    init(id: UUID, name: String, storageSegment: String? = nil, parentFolderID: UUID?) {
        self.id = id
        self.name = name
        if let storageSegment {
            self.storageSegment = storageSegment
        } else {
            self.storageSegment = id == FolderCatalog.rootFolderID ? "" : VaultPath.slugifySegment(name)
        }
        self.parentFolderID = parentFolderID
    }

    enum CodingKeys: String, CodingKey {
        case id, name, storageSegment, parentFolderID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        parentFolderID = try container.decodeIfPresent(UUID.self, forKey: .parentFolderID)
        if let stored = try container.decodeIfPresent(String.self, forKey: .storageSegment), !stored.isEmpty || id == FolderCatalog.rootFolderID {
            storageSegment = id == FolderCatalog.rootFolderID ? "" : stored
        } else {
            storageSegment = id == FolderCatalog.rootFolderID ? "" : VaultPath.slugifySegment(name)
        }
    }

    static let root = FolderEntry(
        id: FolderCatalog.rootFolderID,
        name: "Vault",
        storageSegment: "",
        parentFolderID: nil
    )
}

struct PathIndex: Codable, Equatable, Sendable {
    /// Bumped when ``PathIndexEntry/bodyFileExtension`` was added (v1 entries default to `txt` on decode).
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var entries: [PathIndexEntry]
    var isDirty: Bool = false

    enum CodingKeys: String, CodingKey {
        case schemaVersion, entries
    }

    init(schemaVersion: Int = currentSchemaVersion, entries: [PathIndexEntry] = []) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    mutating func upsert(
        noteID: UUID,
        folderID: UUID,
        relativePath: String,
        aliases: [String] = [],
        bodyFileExtension: String? = nil
    ) {
        if let index = entries.firstIndex(where: { $0.noteID == noteID }) {
            entries[index].folderID = folderID
            entries[index].relativePath = relativePath
            entries[index].aliases = aliases
            if let bodyFileExtension {
                entries[index].bodyFileExtension = PathIndexEntry.normalizeBodyFileExtension(bodyFileExtension)
            }
        } else {
            entries.append(
                PathIndexEntry(
                    noteID: noteID,
                    folderID: folderID,
                    relativePath: relativePath,
                    aliases: aliases,
                    bodyFileExtension: PathIndexEntry.normalizeBodyFileExtension(bodyFileExtension ?? "txt")
                )
            )
        }
        isDirty = true
    }

    mutating func remove(noteID: UUID) {
        let before = entries.count
        entries.removeAll { $0.noteID == noteID }
        if entries.count != before {
            isDirty = true
        }
    }

    /// Updates the row for `relativePath` when manifest/note identity was repaired (e.g. sidecar overrode a stale manifest `noteID`).
    mutating func replaceNoteID(forRelativePath relativePath: String, newNoteID: UUID) {
        guard let i = entries.firstIndex(where: { $0.relativePath == relativePath }) else { return }
        guard entries[i].noteID != newNoteID else { return }
        entries[i].noteID = newNoteID
        isDirty = true
    }
}

struct PathIndexEntry: Codable, Equatable, Hashable, Sendable {
    var noteID: UUID
    var folderID: UUID
    var relativePath: String
    var aliases: [String]
    /// On-disk body: `txt` or `md`.
    var bodyFileExtension: String

    init(
        noteID: UUID,
        folderID: UUID,
        relativePath: String,
        aliases: [String],
        bodyFileExtension: String = "txt"
    ) {
        self.noteID = noteID
        self.folderID = folderID
        self.relativePath = relativePath
        self.aliases = aliases
        self.bodyFileExtension = Self.normalizeBodyFileExtension(bodyFileExtension)
    }

    enum CodingKeys: String, CodingKey {
        case noteID, folderID, relativePath, aliases, bodyFileExtension
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noteID = try c.decode(UUID.self, forKey: .noteID)
        folderID = try c.decode(UUID.self, forKey: .folderID)
        relativePath = try c.decode(String.self, forKey: .relativePath)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        bodyFileExtension = Self.normalizeBodyFileExtension(try c.decodeIfPresent(String.self, forKey: .bodyFileExtension) ?? "txt")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(noteID, forKey: .noteID)
        try c.encode(folderID, forKey: .folderID)
        try c.encode(relativePath, forKey: .relativePath)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(bodyFileExtension, forKey: .bodyFileExtension)
    }

    static func normalizeBodyFileExtension(_ raw: String) -> String {
        NoteBodyFileExtension.normalize(raw).fileExtension
    }
}

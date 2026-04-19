import Foundation
import MiranNotesCore

/// How a non-root folder behaves in the main content column: navigation hub vs note container.
enum FolderRole: String, Codable, Equatable, Hashable, Sendable {
    /// Lists child folders only; may not contain notes.
    case dashboard
    /// Lists notes (classic folder page); may not contain nested folders from the app.
    case repository
}

struct FolderCatalog: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3
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
        applyFolderRoleSchemaV3MigrationIfNeeded()
    }

    /// Pre-v3 catalogs had no roles. Assign ``FolderRole/repository`` to every non-root folder once so existing vaults keep note-only folder pages without a classification prompt.
    mutating func applyFolderRoleSchemaV3MigrationIfNeeded() {
        guard schemaVersion < Self.currentSchemaVersion else { return }
        for i in folders.indices {
            if folders[i].id == Self.rootFolderID { continue }
            if folders[i].role == nil {
                folders[i].role = .repository
            }
        }
        schemaVersion = Self.currentSchemaVersion
        isDirty = true
    }

    /// Vault root and folders classified as repositories may contain notes. Unclassified non-root folders do not until the user picks a role.
    func allowsNotes(in folderID: UUID) -> Bool {
        if folderID == Self.rootFolderID { return true }
        guard let entry = folder(id: folderID) else { return false }
        return entry.role == .repository
    }

    /// Vault root and dashboard folders may contain nested catalog folders.
    func allowsNestedFolders(in parentID: UUID) -> Bool {
        if parentID == Self.rootFolderID { return true }
        guard let entry = folder(id: parentID) else { return false }
        return entry.role == .dashboard
    }
}

struct FolderEntry: Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Stable on-disk segment used for directory layout (independent from display `name`).
    var storageSegment: String
    var parentFolderID: UUID?
    /// `nil` for the vault root (ignored). For other folders, `nil` until the user classifies the folder once.
    var role: FolderRole?

    init(id: UUID, name: String, storageSegment: String? = nil, parentFolderID: UUID?, role: FolderRole? = nil) {
        self.id = id
        self.name = name
        if let storageSegment {
            self.storageSegment = storageSegment
        } else {
            self.storageSegment = id == FolderCatalog.rootFolderID ? "" : VaultPath.slugifySegment(name)
        }
        self.parentFolderID = parentFolderID
        self.role = id == FolderCatalog.rootFolderID ? nil : role
    }

    enum CodingKeys: String, CodingKey {
        case id, name, storageSegment, parentFolderID, role
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        parentFolderID = try container.decodeIfPresent(UUID.self, forKey: .parentFolderID)
        role = try container.decodeIfPresent(FolderRole.self, forKey: .role)
        if let stored = try container.decodeIfPresent(String.self, forKey: .storageSegment), !stored.isEmpty || id == FolderCatalog.rootFolderID {
            storageSegment = id == FolderCatalog.rootFolderID ? "" : stored
        } else {
            storageSegment = id == FolderCatalog.rootFolderID ? "" : VaultPath.slugifySegment(name)
        }
        if id == FolderCatalog.rootFolderID {
            role = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(storageSegment, forKey: .storageSegment)
        try container.encodeIfPresent(parentFolderID, forKey: .parentFolderID)
        try container.encodeIfPresent(role, forKey: .role)
    }

    static let root = FolderEntry(
        id: FolderCatalog.rootFolderID,
        name: "Vault",
        storageSegment: "",
        parentFolderID: nil,
        role: nil
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

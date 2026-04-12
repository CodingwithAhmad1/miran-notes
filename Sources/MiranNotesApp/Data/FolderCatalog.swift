import Foundation
import MiranNotesCore

struct FolderCatalog: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let rootFolderID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var schemaVersion: Int
    var folders: [FolderEntry]

    init(schemaVersion: Int = currentSchemaVersion, folders: [FolderEntry] = [FolderEntry.root]) {
        self.schemaVersion = schemaVersion
        self.folders = folders
    }

    mutating func ensureRoot() {
        if !folders.contains(where: { $0.id == Self.rootFolderID }) {
            folders.insert(.root, at: 0)
        }
    }
}

struct FolderEntry: Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var parentFolderID: UUID?

    static let root = FolderEntry(
        id: FolderCatalog.rootFolderID,
        name: "Vault",
        parentFolderID: nil
    )
}

struct PathIndex: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var entries: [PathIndexEntry]

    init(schemaVersion: Int = currentSchemaVersion, entries: [PathIndexEntry] = []) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    mutating func upsert(noteID: UUID, folderID: UUID, relativePath: String, aliases: [String] = []) {
        if let index = entries.firstIndex(where: { $0.noteID == noteID }) {
            entries[index].folderID = folderID
            entries[index].relativePath = relativePath
            entries[index].aliases = aliases
        } else {
            entries.append(PathIndexEntry(noteID: noteID, folderID: folderID, relativePath: relativePath, aliases: aliases))
        }
    }
}

struct PathIndexEntry: Codable, Equatable, Hashable {
    var noteID: UUID
    var folderID: UUID
    var relativePath: String
    var aliases: [String]
}

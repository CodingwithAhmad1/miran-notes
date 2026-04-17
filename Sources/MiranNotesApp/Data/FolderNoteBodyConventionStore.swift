import Foundation

/// Persists the user's chosen on-disk note body format (`.txt` vs `.md`) for topic folders that have not yet gained a note on disk.
enum FolderNoteBodyConventionStore {
    private struct FilePayload: Codable {
        static let currentSchemaVersion = 1
        var schemaVersion: Int
        /// Folder ID (lower UUID string) → `txt` or `md`.
        var folders: [String: String]
    }

    static func load(vaultURL: URL) -> [UUID: String] {
        let url = VaultPaths.folderNoteBodyConventionURL(vaultURL: vaultURL)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(FilePayload.self, from: data),
              payload.schemaVersion == FilePayload.currentSchemaVersion
        else {
            return [:]
        }
        var out: [UUID: String] = [:]
        for (key, value) in payload.folders {
            guard let id = UUID(uuidString: key) else { continue }
            out[id] = PathIndexEntry.normalizeBodyFileExtension(value)
        }
        return out
    }

    static func save(_ map: [UUID: String], vaultURL: URL) throws {
        let miran = VaultPaths.miranDirectory(vaultURL: vaultURL)
        try FileManager.default.createDirectory(at: miran, withIntermediateDirectories: true)
        let sortedIDs = map.keys.sorted { $0.uuidString.localizedStandardCompare($1.uuidString) == .orderedAscending }
        var folders: [String: String] = [:]
        for id in sortedIDs {
            guard let ext = map[id] else { continue }
            folders[id.uuidString.lowercased()] = PathIndexEntry.normalizeBodyFileExtension(ext)
        }
        let payload = FilePayload(schemaVersion: FilePayload.currentSchemaVersion, folders: folders)
        let data = try JSONEncoder().encode(payload)
        let url = VaultPaths.folderNoteBodyConventionURL(vaultURL: vaultURL)
        try data.write(to: url, options: .atomic)
    }
}

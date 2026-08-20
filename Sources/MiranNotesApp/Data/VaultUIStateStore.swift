import Foundation

/// Presentation-only per-vault state under `.miran/ui-state/` (recents, pins, icon layouts,
/// view-mode choices). **Deliberately not a `VaultCommitParticipant`**: losing one of these files
/// is cosmetic, and keeping the two-phase commit set closed protects the recovery path
/// (see Constraints.md § Atomic vault commits). Writes are single-file atomic; decodes are
/// tolerant — a corrupt file reads as absent, never as an error surfaced to the user.
struct VaultUIStateStore: Sendable {
    let vaultURL: URL

    static func directory(vaultURL: URL) -> URL {
        VaultPaths.miranDirectory(vaultURL: vaultURL).appendingPathComponent("ui-state", isDirectory: true)
    }

    private func fileURL(name: String) -> URL {
        Self.directory(vaultURL: vaultURL).appendingPathComponent(name, isDirectory: false)
    }

    /// Nil when missing or undecodable (tolerant read).
    func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        let url = fileURL(name: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable>(_ value: T, name: String) throws {
        let url = fileURL(name: name)
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    func remove(name: String) {
        try? FileManager.default.removeItem(at: fileURL(name: name))
    }
}

/// Pinned notes (`pins.json`).
struct VaultPinnedNotesState: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var noteIDs: [UUID] = []
}

/// Recently opened notes, most recent first (`recents.json`).
struct VaultRecentNotesState: Codable, Equatable, Sendable {
    static let maxCount = 20
    var schemaVersion: Int = 1
    var noteIDs: [UUID] = []
}

/// One icon's saved position in a folder's browser canvas (top-leading coordinate space, points).
struct FolderIconPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
}

/// User-arranged icon positions for one folder's browser (`icon-layout/<folderID>.json`).
/// Keys are item UUID strings (noteID or child folderID); items without an entry auto-flow into
/// the default grid. Stale IDs are pruned lazily on save.
struct FolderIconLayoutState: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var positions: [String: FolderIconPoint] = [:]
}

/// Per-folder browser view mode (`folder-view-modes.json`); folders default to icons.
struct FolderViewModesState: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    /// Folder UUID string → raw ``FolderPageViewMode``.
    var modes: [String: String] = [:]
}

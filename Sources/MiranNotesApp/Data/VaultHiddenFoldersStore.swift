import CryptoKit
import Foundation

/// Persists top-level folder IDs hidden from the sidebar (per vault), without writing into the vault.
enum VaultHiddenFoldersStore {
    private static let userDefaultsKeyPrefix = "MiranNotes.hiddenTopLevelFolderIDs."

    private static func userDefaultsKey(for vaultURL: URL) -> String {
        let path = vaultURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return userDefaultsKeyPrefix + hex
    }

    static func load(vaultURL: URL) -> Set<UUID> {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey(for: vaultURL)),
              let strings = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        var result = Set<UUID>()
        for s in strings {
            if let u = UUID(uuidString: s) {
                result.insert(u)
            }
        }
        return result
    }

    static func save(_ ids: Set<UUID>, vaultURL: URL) {
        let sorted = ids.map(\.uuidString).sorted()
        let data = try? JSONEncoder().encode(sorted)
        UserDefaults.standard.set(data, forKey: userDefaultsKey(for: vaultURL))
    }

    /// Drops IDs that are not direct children of `parentFolderID` in `catalog` or no longer exist.
    static func pruned(
        _ ids: Set<UUID>,
        folderCatalog: FolderCatalog,
        parentFolderID: UUID
    ) -> Set<UUID> {
        let validChildIDs = Set(folderCatalog.childFolders(of: parentFolderID).map(\.id))
        return ids.intersection(validChildIDs)
    }
}

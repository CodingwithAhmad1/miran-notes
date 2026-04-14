import Foundation

/// Owns the resolved vault root URL and security-scoped access for that directory.
/// The app shell uses this only on the main thread. See ADR 0006 (`docs/adr/0006-threat-model-app-sandbox-vault-access.md`).
final class VaultWorkspaceAccess {
    private(set) var vaultRootURL: URL
    private var isSecurityScopedAccessActive: Bool

    init(vaultRootURL: URL, isSecurityScopedAccessActive: Bool) {
        self.vaultRootURL = vaultRootURL.standardizedFileURL
        self.isSecurityScopedAccessActive = isSecurityScopedAccessActive
    }

    func stopAccessingIfNeeded() {
        if isSecurityScopedAccessActive {
            vaultRootURL.stopAccessingSecurityScopedResource()
            isSecurityScopedAccessActive = false
        }
    }

    /// Restore saved bookmark, or use `defaultVaultURL` when none / stale / invalid.
    static func bootstrap(defaultVaultURL: URL) -> VaultWorkspaceAccess {
        if let data = VaultRootBookmarkStore.loadBookmarkData() {
            if let restored = resolveBookmarkData(data) {
                let started = restored.startAccessingSecurityScopedResource()
                return VaultWorkspaceAccess(vaultRootURL: restored, isSecurityScopedAccessActive: started)
            }
            VaultRootBookmarkStore.clearBookmarkData()
        }
        let url = defaultVaultURL.standardizedFileURL
        let started = url.startAccessingSecurityScopedResource()
        return VaultWorkspaceAccess(vaultRootURL: url, isSecurityScopedAccessActive: started)
    }

    /// Call after the user selects a directory from ``NSOpenPanel``. Persists a bookmark for the next launch.
    /// Caller should invoke ``stopAccessingIfNeeded()`` on the previous instance before replacing it.
    static func adoptUserSelectedVaultRoot(_ url: URL) throws -> VaultWorkspaceAccess {
        let standardized = url.standardizedFileURL
        let started = standardized.startAccessingSecurityScopedResource()
        let data = try makeBookmarkData(for: standardized)
        try VaultRootBookmarkStore.saveBookmarkData(data)
        return VaultWorkspaceAccess(vaultRootURL: standardized, isSecurityScopedAccessActive: started)
    }

    private static func resolveBookmarkData(_ data: Data) -> URL? {
        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale { return nil }
            if directoryExists(url) { return url }
        } catch {}

        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale { return nil }
            if directoryExists(url) { return url }
        } catch {}

        return nil
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func makeBookmarkData(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }
}

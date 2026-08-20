import Foundation

/// Result of resolving vault access at launch before the user picks a folder from ``NSOpenPanel``.
enum VaultBootstrapOutcome {
    /// Security-scoped vault access ready (`defaultVaultURL` or unit-test bookmark restore).
    case resolved(VaultWorkspaceAccess)
    /// No valid bookmark and no fallback URL — show the open-vault welcome UI.
    case needsUserSelectedVault
}

/// The chosen folder failed the workspace layout gate (see ``WorkspaceCompatibilityScanner``).
enum VaultWorkspaceAdoptionError: LocalizedError, Equatable {
    case incompatibleVault(CompatibilityReport)

    init(report: CompatibilityReport) {
        self = .incompatibleVault(report)
    }

    var errorDescription: String? {
        switch self {
        case .incompatibleVault(let report):
            return report.summary
        }
    }
}

/// Owns the resolved vault root URL and security-scoped access for that directory.
/// The app shell uses this only on the main thread. See ADR 0006 (`docs/adr/0006-threat-model-app-sandbox-vault-access.md`).
final class VaultWorkspaceAccess {
    private(set) var vaultRootURL: URL
    private var isSecurityScopedAccessActive: Bool

    init(vaultRootURL: URL, isSecurityScopedAccessActive: Bool) {
        self.vaultRootURL = vaultRootURL.standardizedFileURL
        self.isSecurityScopedAccessActive = isSecurityScopedAccessActive
    }

    /// Security-scoped access is managed by ``VaultSecurityScopeCoordinator`` via ``AppModel`` lifetime.
    func stopAccessingIfNeeded() {
        if isSecurityScopedAccessActive {
            vaultRootURL.stopAccessingSecurityScopedResource()
            isSecurityScopedAccessActive = false
        }
    }

    /// Restores the last vault from its persisted security-scoped bookmark when the
    /// "Reopen last vault at launch" preference is on (the default); otherwise — and when the
    /// bookmark is stale, missing, or points at an incompatible workspace — falls back to
    /// `defaultVaultURL` (e.g. `MIRAN_USE_DEFAULT_VAULT`) or the open-vault welcome UI.
    /// See ADR 0006 (amended: production persists the vault-root bookmark).
    static func bootstrap(defaultVaultURL: URL?) -> VaultBootstrapOutcome {
        if AppSettings.reopenLastVaultAtLaunchPreference(), let data = VaultRootBookmarkStore.loadBookmarkData() {
            if let restored = resolveBookmarkData(data) {
                switch WorkspaceCompatibilityScanner.scan(vaultRoot: restored.url) {
                case .incompatible:
                    if restored.isSecurityScopeActive {
                        restored.url.stopAccessingSecurityScopedResource()
                    }
                    VaultRootBookmarkStore.clearBookmarkData()
                case .empty, .compatible:
                    return .resolved(
                        VaultWorkspaceAccess(
                            vaultRootURL: restored.url,
                            isSecurityScopedAccessActive: restored.isSecurityScopeActive
                        )
                    )
                }
            } else {
                VaultRootBookmarkStore.clearBookmarkData()
            }
        }
        guard let defaultVaultURL else {
            return .needsUserSelectedVault
        }
        let url = defaultVaultURL.standardizedFileURL
        switch WorkspaceCompatibilityScanner.scan(vaultRoot: url) {
        case .incompatible:
            return .needsUserSelectedVault
        case .empty, .compatible:
            return .resolved(
                VaultWorkspaceAccess(vaultRootURL: url, isSecurityScopedAccessActive: false)
            )
        }
    }

    /// Call after the user selects a directory from ``NSOpenPanel``.
    /// Persists a vault-root bookmark (best-effort) so the next launch can reopen the vault.
    /// Caller should invoke ``stopAccessingIfNeeded()`` on the previous instance before replacing it.
    static func adoptUserSelectedVaultRoot(_ url: URL) throws -> VaultWorkspaceAccess {
        let standardized = url.standardizedFileURL
        switch WorkspaceCompatibilityScanner.scan(vaultRoot: standardized) {
        case .incompatible(let report):
            throw VaultWorkspaceAdoptionError(report: report)
        case .empty, .compatible:
            break
        }
        if let data = try? makeBookmarkData(for: standardized) {
            try? VaultRootBookmarkStore.saveBookmarkData(data)
        }
        return VaultWorkspaceAccess(vaultRootURL: standardized, isSecurityScopedAccessActive: false)
    }

    private static func resolveBookmarkData(_ data: Data) -> (url: URL, isSecurityScopeActive: Bool)? {
        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if !stale, directoryExists(url) {
                let started = url.startAccessingSecurityScopedResource()
                return (url, started)
            }
        } catch {}

        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if !stale, directoryExists(url) {
                return (url, false)
            }
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

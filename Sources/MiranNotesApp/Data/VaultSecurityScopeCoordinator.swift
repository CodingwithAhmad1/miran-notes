import Foundation

/// Balances `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` for vault roots.
/// Each ``AppModel`` calls ``retain`` in `init` and ``release`` in `deinit`` for its ``NoteRepository/vaultURL``.
@MainActor
final class VaultSecurityScopeCoordinator {
    static let shared = VaultSecurityScopeCoordinator()

    private var counts: [String: Int] = [:]

    private init() {}

    /// Increments the retain count for `vaultURL` and starts security-scoped access when transitioning 0 → 1.
    func retain(_ vaultURL: URL) {
        let key = vaultURL.standardizedFileURL.path
        let next = (counts[key] ?? 0) + 1
        counts[key] = next
        if next == 1 {
            _ = vaultURL.standardizedFileURL.startAccessingSecurityScopedResource()
        }
    }

    /// Decrements the retain count and stops security-scoped access when transitioning to 0.
    func release(_ vaultURL: URL) {
        let key = vaultURL.standardizedFileURL.path
        guard let c = counts[key], c > 0 else { return }
        let next = c - 1
        if next == 0 {
            counts[key] = nil
            vaultURL.standardizedFileURL.stopAccessingSecurityScopedResource()
        } else {
            counts[key] = next
        }
    }

#if DEBUG
    /// Resets internal state for unit tests (does not call `stopAccessing` — tests use temp dirs).
    func resetCountsForUnitTests() {
        counts.removeAll()
    }
#endif
}

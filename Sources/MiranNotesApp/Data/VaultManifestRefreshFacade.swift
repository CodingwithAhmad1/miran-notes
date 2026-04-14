import Foundation

/// Policy boundary for “disk may have changed” versus read-only listing over the persisted manifest.
///
/// **Read-only sidebar data:** use ``NoteRepository/listNotes()`` and ``NoteRepository/loadFolderCatalog()`` after the manifest matches disk—typically following
/// vault open or a vault watcher event. Those APIs do not reconcile; see
/// `docs/architecture/vault-data-layer.md`. Manifest and folder/path invariants:
/// `docs/adr/0003-folders-paths-and-manifest-v2.md`.
@MainActor
final class VaultManifestRefreshFacade {
    /// Optional ``NoteRepository/invalidateIndexCaches()`` then ``NoteRepository/reconcileManifest()``.
    /// - Returns: `nil` on success, or a user-facing error string consistent with `AppModel` copy.
    func reconcileAfterDiskChange(
        repository: NoteRepository,
        invalidateCaches: Bool
    ) async -> String? {
        if invalidateCaches {
            await repository.invalidateIndexCaches()
        }
        do {
            try await repository.reconcileManifest()
            return nil
        } catch {
            return "Manifest reconciliation failed: \(error.localizedDescription)"
        }
    }
}

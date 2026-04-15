# Architectural refinements (implementation notes)

This document tracks major structural work aligned with the long-term plan:

## Editor sync boundary

- [`EditorSyncController`](../../Sources/MiranNotesApp/Features/Editor/EditorSyncController.swift) is the **only** supported path for syncing canonical `NoteDocument.text` to `NSTextView` (except IME composition).
- SHA-256 **fingerprints** detect drift between model and view (DEBUG sampling by default).
- [`SingleSurfaceNoteEditor`](../../Sources/MiranNotesApp/Features/Editor/SingleSurfaceNoteEditor.swift) routes `applyDocumentText` and post-command sync through this controller.

## Extension registry

- [`ExtensionRegistry`](../../Sources/MiranNotesCore/ExtensionRegistry.swift) is a **synchronous**, thread-safe registration API (not an actor) so `AppModel.apply` can call it on the main actor without `await`.
- Pipeline order: **registry interceptors** (sorted by id) → **closure interceptors** (registration order) → `EditCommandEngine`.
- [`CommandContext.selectionRange`](../../Sources/MiranNotesCore/ExtensionRegistry.swift) is filled from `AppModel.editorTextSelection`.

## Vault indexes

- [`VaultIndexSubsystem`](../../Sources/MiranNotesApp/Data/VaultIndexSubsystem.swift) centralizes **static** load helpers for `.miran/` JSON. [`VaultIndexActor`](../../Sources/MiranNotesApp/Data/VaultIndexActor.swift) owns manifest encoding, **in-memory caching** of all vault indexes after load/commit, `invalidateCaches()` for external changes, and atomic index commits; [`NoteFileActor`](../../Sources/MiranNotesApp/Data/NoteFileActor.swift) owns per-note `.txt` / `.meta.json` I/O. [`NoteRepository`](../../Sources/MiranNotesApp/Data/NoteRepository.swift) coordinates both actors, exposes **`reconcileManifest()`** (disk scan + optional `commitIndexOnly`) and read-only **`listNotes()`** over the persisted manifest. See [vault-data-layer.md](vault-data-layer.md).
- **[`VaultManifestRefreshFacade`](../../Sources/MiranNotesApp/Data/VaultManifestRefreshFacade.swift)** is the app’s entry point for the policy “filesystem may have changed → optionally invalidate index caches, then `reconcileManifest()`” before relying on read-only listing; see the type’s header for ADR pointers.
- **`AppModel/processVaultFilesystemRefreshPipeline()`** ([`AppModel.swift`](../../Sources/MiranNotesApp/App/AppModel.swift)) is the **single** implementation shared by the vault watcher and test helper `simulateWatcherEvent`: workspace compatibility scan, then `reconcileVaultState` (facade), then deferred external-edit reconciliation. Keeps FS-driven refresh behavior aligned across paths.

## AppModel collaborators (ongoing decomposition)

- [`NoteBodySearchIndexController`](../../Sources/MiranNotesApp/Data/NoteBodySearchIndexController.swift) — async body-text map for search snippets; `AppModel` applies results and user-visible errors.
- [`DebouncedAsyncWorkScheduler`](../../Sources/MiranNotesApp/Data/DebouncedAsyncWorkScheduler.swift) — debounced main-actor async work (e.g. backlink refresh).
- [`FolderPageNoteLoading`](../../Sources/MiranNotesApp/Data/FolderPageNoteLoading.swift) — loads folder-page note buffers from `NoteRepository`.
- [`AppModelUndoCheckpointSupport.swift`](../../Sources/MiranNotesApp/App/AppModelUndoCheckpointSupport.swift) — `UndoCheckpoint` state, materialization, and action naming shared with `AppModel` undo registration (still registers on `AppModel` via `UndoManager`).

## Vault-level database paths (core only)

- On-disk paths for `_databases/` and `database-registry.json` live in **`MiranNotesCore`** as [`VaultDatabasePaths`](../../Sources/MiranNotesCore/VaultDatabasePaths.swift), alongside [`DatabaseModels`](../../Sources/MiranNotesCore/DatabaseModels.swift), so vaults created by older builds remain interpretable. The **`DatabaseDocument` / `DatabaseRepository`** persistence layer described in [ADR 0004](../adr/0004-vault-level-databases-and-planning.md) was **removed** from the repository during the Apr 2026 minimal-product pivot.

## Undo (hybrid roadmap)

- [`UndoInverseSupport`](../../Sources/MiranNotesCore/UndoInverseSupport.swift) computes inverse `replaceText` batches for hybrid undo; full `AppModel` integration can build on this without changing on-disk formats.
- Checkpoint materialization and menu action names live in [`AppModelUndoCheckpointSupport.swift`](../../Sources/MiranNotesApp/App/AppModelUndoCheckpointSupport.swift); stack mutation and `UndoManager` registration remain on `AppModel`.

## External edits

- [`ActiveNoteFilePresenter`](../../Sources/MiranNotesApp/Data/ActiveNoteFilePresenter.swift) registers an `NSFilePresenter` for the active note’s `.txt` in addition to the subtree watcher. When the presenter fires, `AppModel` compares the on-disk `.txt` SHA256 to the last known body fingerprint; if they match, reconciliation is skipped (same body bytes as after load/save). The vault-wide watcher path is unchanged.
- Compare UI uses `ExternalTextComparePayload` and plain-text side-by-side view.

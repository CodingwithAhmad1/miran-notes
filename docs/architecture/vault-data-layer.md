# Vault data layer

This note summarizes how on-disk vault state, the repository, and `AppModel` fit together. It complements [architectural-refinements.md](architectural-refinements.md) and [Constraints.md](../../Constraints.md). Vault **root** access and security-scoped bookmarks are described in [ADR 0006](../adr/0006-threat-model-app-sandbox-vault-access.md) and [app-sandbox-readiness.md](../guides/app-sandbox-readiness.md).

## `NoteRepository` (coordinator actor)

- **`NoteRepository`** composes **`NoteFileActor`** (note body + sidecar files, hashes, disk enumeration) and **`VaultIndexActor`** (manifest, `.miran/` indexes, `executeNoteCommit` / `commitIndexOnly`). Call sites use a single `NoteRepository` instance per vault; cross-cutting operations (save, folder moves, manifest reconciliation) run in the coordinator so atomic commit plans stay consistent.
- **Disk vs listing at the UI boundary:** `AppModel` routes “invalidate caches + reconcile manifest” through **`VaultManifestRefreshFacade`** (`Sources/MiranNotesApp/Data/VaultManifestRefreshFacade.swift`) so the policy stays in one place; see also [architectural-refinements.md](architectural-refinements.md).
- **Per-note files:** `{relativePath}.txt` (canonical body bytes) and `{relativePath}.meta.json` (structured metadata). Paths are validated with `VaultPath` helpers. Display titles for list UI use `VaultPath.displayTitle(forRelativePath:)` (last path segment, dash → space, capitalized).
- **Body fingerprint:** `noteTextFileSHA256(relativePath:)` returns a hex SHA256 of the raw `.txt` file bytes. It does not parse or repair; it is suitable for detecting body-only drift and for TOCTOU checks before loading external edits.
- **Revision token:** `noteRevisionToken` combines text and metadata for a coarser “whole note file set” identity (see repository implementation). Use tokens for fast “anything changed?” checks; use the text SHA256 when the concern is specifically the body file.

## Manifest reconciliation vs listing

- **`reconcileManifest()`** (public) runs the full **load-or-rebuild** path: if `manifest.json` exists, it runs `reconcileManifestWithDisk` (drop missing `.txt` entries, discover new on-disk notes, optionally materialize missing `.meta.json` via save). If no manifest exists, it **rebuilds** from a vault scan and commits indexes. It then **compares** the canonical encoded manifest to bytes on disk and, if they differ, commits via `commitIndexOnly`. Call this at **vault open** and when **external filesystem changes** are suspected so the manifest and indexes match reality before relying on `listNotes()`.
- **`listNotes()`** is a **read-only listing** over the current in-memory/disk-backed manifest: it loads the manifest via `VaultIndexActor.loadManifestFromDiskOnly()` (no reconcile) and joins **`PathIndex`** for `folderID`. It does **not** scan the vault or write indexes. If `manifest.json` is absent, it returns an empty array until `reconcileManifest()` (or another operation that builds the manifest) has run.
- **`invalidateIndexCaches()`** on the repository forwards to `VaultIndexActor.invalidateCaches()` so the next index load re-reads `.miran/` JSON (used after startup recovery, after reconcile detected manifest changes, and when the vault watcher fires).

## `VaultIndexActor` (indexes + commits)

- **In-memory caches** for `VaultManifest`, `LinkGraph`, `RelationshipIndex`, `FolderCatalog`, and `PathIndex`: loads hit the cache when present; successful `executeNoteCommit` / `commitIndexOnly` calls **`storeCommittedState`** to refresh caches with post-commit copies (`isDirty` cleared on cached structs). Avoids re-reading every index file on hot paths such as autosave.
- **Dirty flags:** `VaultManifest` participates like the other indexes: `ManifestCommitParticipant` skips a write when `!manifest.isDirty`. Schema bumps use `ensureSchemaVersionIsCurrent()`.
- **`VaultCommitContext`** uses optional `document` / `textURL` / `metaURL` for index-only commits (`commitIndexOnly`); note payloads are omitted instead of dummy URLs.
- **`ensureVault()`** in both `NoteFileActor` and `VaultIndexActor` uses a one-shot flag after the first successful directory creation to avoid redundant `createDirectory` syscalls.

## `AppModel` and disk

- After load, successful save/autosave, and when resolving “keep local” after a conflict, `AppModel` refreshes **modified date**, **revision token**, and **text SHA256** together via `refreshOnDiskFingerprints(for:)`.
- **`loadVault`** calls `reconcileManifest()` after startup recovery and before `refreshNotes()`, so the sidebar sees notes that exist only on disk.
- The **vault watcher** calls `invalidateIndexCaches()`, then `reconcileManifest()`, then defers external-edit reconciliation (existing autosave gating unchanged).
- Backlinks use `repository.loadLinkGraph()`; the graph is served from **`VaultIndexActor`** cache after the first load in a session, not a separate `AppModel` field.
- When reconciling external changes, if a full load is required, the model performs **two consecutive** `noteTextFileSHA256` reads; a mismatch logs `VaultTelemetry.logToctouTextHashDrift()` and still proceeds to `loadNote`, which remains the authority for semantic comparison to the buffer.

## Path containment and symlinks

- **User-chosen root:** All vault I/O is rooted at the directory the user opens. `NoteRepository` and `VaultPath` build URLs from that root plus manifest-relative paths (see [ADR 0003](../adr/0003-folders-paths-and-manifest-v2.md) for canonical `relativePath` rules).
- **Workspace gate:** On vault load and on vault watch refresh, `WorkspaceCompatibilityScanner` performs a **structural** scan of the vault root. It **rejects symbolic links** in vault data directories, allows **nested subfolders** under topic folders (for **dashboard** hubs), and rejects a directory that **mixes direct note files and subfolders** in the same folder (matching dashboard vs repository layout). Paths that appear only after reconcile still flow through normal file APIs; the app does not treat symlink targets as a separate security boundary.

## Folder catalog roles (`folder-catalog.json` v3)

- Each **non-root** folder has an optional **FolderRole**: **dashboard** (nested folders only—no notes) or **repository** (notes—classic folder page). New folders stay unclassified until the user chooses once in the folder page; that choice is persisted and is not changed afterward.
- **Migration:** Catalogs with `schemaVersion` below 3 are upgraded in `FolderCatalog.ensureRoot()`: every existing non-root folder gets **repository** so current vaults keep working without a mass classification prompt.
- **Enforcement:** `NoteRepository` blocks `createNote` / `moveNote` into dashboards and unclassified folders, and blocks `createFolder` under repositories. Helpers: `FolderCatalog.allowsNotes(in:)` and `allowsNestedFolders(in:)`.
- **Inferring folder for a path:** When reconciling or materializing sidecars, owning `folderID` is ``FolderCatalog/folderIDOwningNote(relativePathWithoutExtension:)`` (parent directory must match ``relativeDirectoryPath(for:)`` for a catalog folder), with a legacy first-segment fallback for unmatched paths. Paths whose resolved folder does not allow notes are skipped and logged instead of failing the whole reconcile.
- **Environmental risk:** If the vault lives in a cloud-sync folder or contains items created outside Miran, containment is ultimately **filesystem + user process** behavior. Prefer normal directories for vault data; see [VaultSafety.md](../guides/VaultSafety.md).

## Telemetry

- Vault-scoped logging uses `Logger` (`Vault` category) and `VaultTelemetry` helpers for conflicts, autosave latency, manifest reconcile, repair warnings, and TOCTOU drift.

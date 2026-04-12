# Vault data layer

This note summarizes how on-disk vault state, the repository, and `AppModel` fit together. It complements [architectural-refinements.md](architectural-refinements.md) and [Constraints.md](../../Constraints.md).

## `NoteRepository` (coordinator actor)

- **`NoteRepository`** composes **`NoteFileActor`** (note body + sidecar files, hashes, disk enumeration) and **`VaultIndexActor`** (manifest, `.miran/` indexes, `executeNoteCommit` / `commitIndexOnly`). Call sites use a single `NoteRepository` instance per vault; cross-cutting operations (save, folder moves, manifest reconciliation) run in the coordinator so atomic commit plans stay consistent.
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

## Telemetry

- Vault-scoped logging uses `Logger` (`Vault` category) and `VaultTelemetry` helpers for conflicts, autosave latency, manifest reconcile, repair warnings, and TOCTOU drift.

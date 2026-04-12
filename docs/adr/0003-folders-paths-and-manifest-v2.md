# ADR 0003: Folders, relative paths, and manifest v2

## Status

Accepted (implementation follows this ADR).

## Context

Notes were stored flat at the vault root as `{baseName}.txt` with a single-path segment identifier. `FolderCatalog` and `PathIndex` existed on disk but only the root folder was used; `PathIndex.relativePath` duplicated the flat slug.

The product requires **arbitrary-depth folders**, **stable `noteID`-based links**, and **one canonical addressing string** for note files relative to the vault root (without ` .txt`), e.g. `work/client/meeting-notes`.

## Audit summary (pre-change vs target)

| Topic | Before | After |
|-------|--------|--------|
| Editor / list selection | `selectedBaseName` (ambiguous if two notes shared a slug in different folders) | `selectedNoteID` |
| Manifest | `ManifestEntry.baseName` (single segment) | `ManifestEntry.relativePath` (full relative path without extension); JSON may still decode legacy `baseName` |
| On-disk note files | `vault/{slug}.txt` | `vault/{relativePath}.txt` with intermediate directories |
| Folder tree | Catalog only had root | Full `FolderCatalog` mutations; disk directories aligned with slugified folder names |
| Link resolution | `noteID` → manifest path | Unchanged principle: **wikilinks use `noteID`**, manifest stores current path |

## Decisions

### Canonical note address

- **`relativePath`**: POSIX-style path relative to the vault root **without** file extension, using `/`. Segments are slugified folder or note titles (same character rules as legacy `slugify` for note filenames).
- **Files:** `{vaultURL}/{relativePath}.txt` and `{vaultURL}/{relativePath}.meta.json` with parent directories created as needed.
- **`.miran/`** and **`_aux/`** remain reserved; path validation rejects segments that would collide with those names.

### Manifest schema

- **`VaultManifest.schemaVersion`**: bump to **2** on write.
- **`ManifestEntry`**: stores `relativePath` (encode key `relativePath`). Decoder accepts legacy **`baseName`** and treats it as `relativePath` for migration.

### FolderCatalog and PathIndex

- **`FolderCatalog`**: user-created folders are `FolderEntry` rows with `parentFolderID`; the **on-disk folder path** for a folder node is derived by walking ancestors and joining **slugified** `name` segments.
- **`PathIndex`**: for each note, `folderID` is the containing folder’s id (root for top-level notes); `relativePath` matches the manifest and filesystem.

### Empty folders

- Creating a folder creates the corresponding directory under the vault when possible; the catalog remains authoritative if disk creation fails (surfaced as error).

### Delete policy (v1)

- **Delete folder:** rejected if the folder contains child folders or any note (by `PathIndex` / manifest). User must move or delete contents first.
- **Delete note:** removes `.txt` + `.meta.json`, updates manifest, indexes, and link graph entries; does not delete `_aux/{noteID}/` in v1 unless explicitly extended (aux is keyed by noteID and remains for potential recovery—optional follow-up).

### Selection invariant

- UI and `AppModel` use **`noteID`** as the primary selection key; `relativePath` is resolved through the manifest for I/O.

## Consequences

- External tools may place `.txt` files in subfolders; `reconcileManifestWithDisk` recursively discovers notes.
- Vault filesystem watching should cover the **entire subtree** (FSEventStream).
- Rename/move operations should prefer **one commit plan** plus **post-commit deletion** of replaced paths to avoid duplicate note files during migration.

## Related

- [Constraints.md](../../Constraints.md) — semantic reconciliation still applies when plain text is edited outside the app.
- [0001-wiki-links-and-identity.md](0001-wiki-links-and-identity.md) — `noteID` remains the link identity.

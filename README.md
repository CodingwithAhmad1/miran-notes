# Miran Notes (macOS)

A simple, minimalistic, Mac-native knowledge storer. Local-first, plain-text storage, zero cloud dependency.

> **Pivot note (Apr 2026):** Miran Notes is being refocused as a pure knowledge-storage tool. The Miran Planning / calendar feature set (menu-bar extra, task and session databases, dashboard, calendar views) has been **removed from the codebase** as part of that pivot. The shipping product is a clean, distraction-free note-taking experience native to macOS.

**Documentation hub:** [docs/README.md](docs/README.md) — index of [Constraints.md](Constraints.md), ADRs, architecture notes, plans, and code pointers. **Product / engineering brief:** [docs/investor-and-engineering-brief.md](docs/investor-and-engineering-brief.md).

## Implemented architecture

- **On-disk layout:** Canonical body in `{relativePath}.txt`, metadata in `{relativePath}.meta.json` relative to the vault root. Notes may live in **nested folders** (manifest v2, `FolderCatalog` / `PathIndex`; see [ADR 0003](docs/adr/0003-folders-paths-and-manifest-v2.md)). Indexes and staging live under `.miran/`. Optional per-note **`_aux/{noteID}/`** directories are removed when a note is deleted; legacy JSONL from an older **per-note table** experiment may still exist on disk until cleaned up (metadata no longer references those tables; see [ADR 0002](docs/adr/0002-auxiliary-storage-jsonl.md)). **Vault-level databases** under `_databases/{databaseID}/` with schema, JSONL rows, and view configs per [ADR 0004](docs/adr/0004-vault-level-databases-and-planning.md).
- **Single source of truth for note identity:** `NoteDocument.id` is a computed property delegating to `metadata.noteID`.
- **App state:** `AppModel` is `@MainActor @Observable` (Swift `Observation`); the app entry holds it with `@State`, and views that need bindings use `@Bindable`.
- **Editing pipeline:** All structural mutations go through `EditCommandEngine`; `AppModel.apply(_:)` returns the resulting `NoteDocument` synchronously. `splitBlock` runs `SpanAdjuster` / `LinkAdjuster` `constrainToBlocks` after splits.
- **Persistence:** Two-phase **atomic** vault commits (`VaultCommitCoordinator`); **dirty-flag** index participants skip unchanged `VaultManifest`, `LinkGraph`, `RelationshipIndex`, `FolderCatalog`, `PathIndex`. Startup **recovery** for interrupted commits under `.miran/pending-commits/`; **`reconcileManifest()`** scans/repairs manifest vs disk at vault open and on vault watch events; **`listNotes()`** reads the manifest only (no reconcile). In-memory **index caches** in `VaultIndexActor` avoid re-reading `.miran/` JSON on every save. Debounced autosave; load returns `NoteLoadResult` with repair warnings.
- **Editor:** SwiftUI shell; single-surface `NSTextView` with `EditorVisualStyle`, slash discovery, wiki links, optional block chrome overlay. **1 MB (UTF-16)** note size cap with user-visible notice.
- **Undo:** `NSUndoManager` with a checkpoint timeline. **Hybrid undo** stores inverse `replaceText` chains (`UndoInverseSupport`, `UndoCheckpoint`) for pure replace-text steps; **full snapshots** for structural or mixed batches. **Coalescing** of rapid single-`replaceText` edits (default 300 ms window). **Prune** to `UndoPolicy.maxUndoSteps` (default 200) rebases oldest entries to full snapshots. See [Constraints.md](Constraints.md) § Undo.
- **Extension hooks:** `SlashCommandRegistry` (open registration), `ExtensionRegistry` + ordered closure interceptors on `AppModel` (see [extension-registry-and-interceptors.md](docs/architecture/extension-registry-and-interceptors.md)).
- **Navigation / search:** Folder sidebar outline, searchable list with body snippets, backlinks panel with snippets; vault-wide filesystem watch (subtree) and optional active-note file coordination where implemented.
- **Backlinks:** Debounced refresh; `LinkGraph` is cached inside `VaultIndexActor` (invalidated on external vault events and updated after commits).
- **Vault-level databases (on-disk):** Vaults may still contain `_databases/{databaseID}/` trees and `database-registry.json` under `.miran/` from earlier builds ([ADR 0004](docs/adr/0004-vault-level-databases-and-planning.md)). **`MiranNotesCore`** keeps **`DatabaseModels`**, **`VaultDatabasePaths`**, and related types so those artifacts remain interpretable; the app does not ship persistence actors for structured databases or Planning UI.
- **Miran Planning:** Removed. Prior integration (dashboard, calendar, task/session databases, Zora migration, `/task` and `/session`) is described only in ADRs and archived docs for historical context.

## Module layout

- `Sources/MiranNotesCore` — `NoteDocument`, `EditCommandEngine`, `UndoInverseSupport`, `TextEditDiff`, `NoteIntegrity`, `ExtensionRegistry`, `CommandPipelineContract`, `DatabaseModels`, `LinkTarget`.
- `Sources/MiranNotesApp/Data` — `AppModel`, `NoteRepository`, vault/commit/index types (`VaultCommitCoordinator`, `LinkGraph`, `RelationshipIndex`, `FolderCatalog`, `PathIndex`, …).
- `Sources/MiranNotesApp/Features/Editor` — `SingleSurfaceNoteEditor`, `SlashCommandRegistry`, editor features.
- `Tests/MiranNotesTests`, `Tests/MiranNotesAppTests` — `swift test`.

## Milestones (historical)

1. **M1 Foundation** — model, schema, repository, invariants.  
2. **M2 Editor shell** — TextKit bridge.  
3. **M3 Core edits** — split/merge, block types, spans.  
4. **M4 Quality** — autosave, atomic persistence.  
5. **M5 Hardening** — migration seam, malformed metadata handling.
6. **M6 Databases & Planning** — vault-level database layer, Miran Planning integration (dashboard, calendar, task/session databases, cross-feature linking, Zora migration). *(M6 planning features deactivated in pivot to minimalistic knowledge storer.)*

## Acceptance checklist (high level)

- [x] Local vault with `.txt` + `.meta.json`; nested paths and manifest v2.  
- [x] Command-based edit pipeline; synchronous `apply` results.  
- [x] Atomic multi-file commits + dirty index writes + startup recovery.  
- [x] Repair / advisory surfaces for load repair, integrity, conflicts, size limit (see `RepairAdvisory`).  
- [x] Hybrid + snapshot undo with cap, coalescing, and safe prune.  
- [x] Slash commands + discovery menu; open registry.  
- [~] Vault-level databases: on-disk format and core **types** preserved; **persistence/UI** removed (see [ADR 0004](docs/adr/0004-vault-level-databases-and-planning.md) amendment).
- [~] Miran Planning: dashboard, calendar, task/session databases — **deactivated** during pivot.
- [~] Zora vault migration engine and CSV export — **deactivated** during pivot.
- [~] `/task` and `/session` slash commands — **deactivated** during pivot.  
- [x] Project builds; `swift test` passes (268 tests).

## Vault (first launch)

Each time you start the app, it shows **Open a vault** until you pick or create a folder; notes and folders live under that directory for the session. Production builds do not persist a vault-root bookmark (legacy files under Application Support are cleared on launch). To skip the picker during development, run with **`MIRAN_USE_DEFAULT_VAULT=1`** (uses `~/MiranNotesVault`).

## Run

```bash
swift build
swift test
swift run
```

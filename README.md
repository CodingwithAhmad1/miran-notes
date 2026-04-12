# Miran Notes MVP (macOS)

Local-first, Swift-native notes editor with plain-text storage and sidecar metadata.

**Documentation hub:** [docs/README.md](docs/README.md) — index of [Constraints.md](Constraints.md), ADRs, architecture notes, plans, and code pointers. **Product / engineering brief:** [docs/investor-and-engineering-brief.md](docs/investor-and-engineering-brief.md).

## Implemented architecture

- **On-disk layout:** Canonical body in `{relativePath}.txt`, metadata in `{relativePath}.meta.json` relative to the vault root. Notes may live in **nested folders** (manifest v2, `FolderCatalog` / `PathIndex`; see [ADR 0003](docs/adr/0003-folders-paths-and-manifest-v2.md)). Indexes and staging live under `.miran/`; per-note table JSONL under `_aux/{noteID}/` per [ADR 0002](docs/adr/0002-auxiliary-storage-jsonl.md). **Vault-level databases** under `_databases/{databaseID}/` with schema, JSONL rows, and view configs per [ADR 0004](docs/adr/0004-vault-level-databases-and-planning.md).
- **Single source of truth for note identity:** `NoteDocument.id` is a computed property delegating to `metadata.noteID`.
- **Editing pipeline:** All structural mutations go through `EditCommandEngine`; `AppModel.apply(_:)` returns the resulting `NoteDocument` synchronously. `splitBlock` runs `SpanAdjuster` / `LinkAdjuster` `constrainToBlocks` after splits.
- **Persistence:** Two-phase **atomic** vault commits (`VaultCommitCoordinator`); **dirty-flag** index participants skip unchanged `VaultManifest`, `LinkGraph`, `RelationshipIndex`, `FolderCatalog`, `PathIndex`. Startup **recovery** for interrupted commits under `.miran/pending-commits/`; **`reconcileManifest()`** scans/repairs manifest vs disk at vault open and on vault watch events; **`listNotes()`** reads the manifest only (no reconcile). In-memory **index caches** in `VaultIndexActor` avoid re-reading `.miran/` JSON on every save. Debounced autosave; load returns `NoteLoadResult` with repair warnings.
- **Editor:** SwiftUI shell; single-surface `NSTextView` with `EditorVisualStyle`, slash discovery, wiki links, optional block chrome overlay. **1 MB (UTF-16)** note size cap with user-visible notice.
- **Undo:** `NSUndoManager` with a checkpoint timeline. **Hybrid undo** stores inverse `replaceText` chains (`UndoInverseSupport`, `UndoCheckpoint`) for pure replace-text steps; **full snapshots** for structural or mixed batches. **Coalescing** of rapid single-`replaceText` edits (default 300 ms window). **Prune** to `UndoPolicy.maxUndoSteps` (default 200) rebases oldest entries to full snapshots. See [Constraints.md](Constraints.md) § Undo.
- **Extension hooks:** `SlashCommandRegistry` (open registration), `ExtensionRegistry` + ordered closure interceptors on `AppModel` (see [extension-registry-and-interceptors.md](docs/architecture/extension-registry-and-interceptors.md)).
- **Navigation / search:** Folder sidebar outline, searchable list with body snippets, backlinks panel with snippets; vault-wide filesystem watch (subtree) and optional active-note file coordination where implemented.
- **Backlinks:** Debounced refresh; `LinkGraph` is cached inside `VaultIndexActor` (invalidated on external vault events and updated after commits).
- **Vault-level databases:** `DatabaseDocument` actor + `DatabaseRepository` actor provide schema-typed JSONL databases under `_databases/`. `DatabaseRegistry` in `.miran/` tracks all databases. 10 column types including `select`, `multiSelect`, `relation`, `noteLink`, `url`, `duration`. `DatabaseViewConfig` supports table, board, calendar, and list layouts with filters and sort keys.
- **Miran Planning:** Integrated planning feature built on the database layer. `PlanningModel` bootstraps Tasks and Sessions databases with predefined schemas. Dashboard with quick-add, daily/weekly/monthly calendar views, weekly review metrics, inline task/session embedding, `/task` and `/session` slash commands, and `ZoraMigrationEngine` for importing from Zora Planning vaults. Settings include subject management, color schema, CSV export.

## Module layout

- `Sources/MiranNotesCore` — `NoteDocument`, `EditCommandEngine`, `UndoInverseSupport`, `TextEditDiff`, `NoteIntegrity`, `ExtensionRegistry`, `CommandPipelineContract`, `DatabaseModels`, `LinkTarget`.
- `Sources/MiranNotesApp/Data` — `AppModel`, `NoteRepository`, vault/commit/index types, `DatabaseDocument`, `DatabaseRepository`, `PlanningConfigManager`, `PlanningSchemas`.
- `Sources/MiranNotesApp/Features/Editor` — `SingleSurfaceNoteEditor`, `SlashCommandRegistry`, editor features.
- `Sources/MiranNotesApp/Features/Planning` — `PlanningModel`, dashboard, calendar (daily/weekly/monthly/review), database views (table/board), edit sheets, inline embeds, settings, migration, slash commands, daily template engine.
- `Tests/MiranNotesTests`, `Tests/MiranNotesAppTests` — `swift test`.

## Milestones (historical)

1. **M1 Foundation** — model, schema, repository, invariants.  
2. **M2 Editor shell** — TextKit bridge.  
3. **M3 Core edits** — split/merge, block types, spans.  
4. **M4 Quality** — autosave, atomic persistence.  
5. **M5 Hardening** — migration seam, malformed metadata handling.
6. **M6 Databases & Planning** — vault-level database layer, Miran Planning integration (dashboard, calendar, task/session databases, cross-feature linking, Zora migration).

## Acceptance checklist (high level)

- [x] Local vault with `.txt` + `.meta.json`; nested paths and manifest v2.  
- [x] Command-based edit pipeline; synchronous `apply` results.  
- [x] Atomic multi-file commits + dirty index writes + startup recovery.  
- [x] Repair / advisory surfaces for load repair, integrity, conflicts, size limit (see `RepairAdvisory`).  
- [x] Hybrid + snapshot undo with cap, coalescing, and safe prune.  
- [x] Slash commands + discovery menu; open registry.  
- [x] Vault-level databases with typed schemas, JSONL rows, and multi-layout views.  
- [x] Miran Planning: dashboard, calendar, task/session databases, quick add, weekly review, cross-feature linking.  
- [x] Zora vault migration engine and CSV export.  
- [x] `/task` and `/session` slash commands; inline embeddable task/session views.  
- [x] Project builds; `swift test` passes (204 tests).

## Run

```bash
swift build
swift test
swift run
```

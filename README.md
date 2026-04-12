# Miran Notes MVP (macOS)

Local-first, Swift-native notes editor with plain-text storage and sidecar metadata.

**Documentation hub:** [docs/README.md](docs/README.md) — index of [Constraints.md](Constraints.md), ADRs, architecture notes, plans, and code pointers. **Product / engineering brief:** [docs/investor-and-engineering-brief.md](docs/investor-and-engineering-brief.md).

## Implemented architecture

- **On-disk layout:** Canonical body in `{relativePath}.txt`, metadata in `{relativePath}.meta.json` relative to the vault root. Notes may live in **nested folders** (manifest v2, `FolderCatalog` / `PathIndex`; see [ADR 0003](docs/adr/0003-folders-paths-and-manifest-v2.md)). Indexes and staging live under `.miran/`; table JSONL under `_aux/{noteID}/` per [ADR 0002](docs/adr/0002-auxiliary-storage-jsonl.md).
- **Single source of truth for note identity:** `NoteDocument.id` is a computed property delegating to `metadata.noteID`.
- **Editing pipeline:** All structural mutations go through `EditCommandEngine`; `AppModel.apply(_:)` returns the resulting `NoteDocument` synchronously. `splitBlock` runs `SpanAdjuster` / `LinkAdjuster` `constrainToBlocks` after splits.
- **Persistence:** Two-phase **atomic** vault commits (`VaultCommitCoordinator`); **dirty-flag** index participants skip unchanged `LinkGraph`, `RelationshipIndex`, `FolderCatalog`, `PathIndex`. Startup **recovery** for interrupted commits under `.miran/pending-commits/`. Debounced autosave; load returns `NoteLoadResult` with repair warnings.
- **Editor:** SwiftUI shell; single-surface `NSTextView` with `EditorVisualStyle`, slash discovery, wiki links, optional block chrome overlay. **1 MB (UTF-16)** note size cap with user-visible notice.
- **Undo:** `NSUndoManager` with a checkpoint timeline. **Hybrid undo** stores inverse `replaceText` chains (`UndoInverseSupport`, `UndoCheckpoint`) for pure replace-text steps; **full snapshots** for structural or mixed batches. **Coalescing** of rapid single-`replaceText` edits (default 300 ms window). **Prune** to `UndoPolicy.maxUndoSteps` (default 200) rebases oldest entries to full snapshots. See [Constraints.md](Constraints.md) § Undo.
- **Extension hooks:** `SlashCommandRegistry` (open registration), `ExtensionRegistry` + ordered closure interceptors on `AppModel` (see [extension-registry-and-interceptors.md](docs/architecture/extension-registry-and-interceptors.md)).
- **Navigation / search:** Folder sidebar outline, searchable list with body snippets, backlinks panel with snippets; vault-wide filesystem watch (subtree) and optional active-note file coordination where implemented.
- **Backlink cache:** In-memory `LinkGraph` cache with debounced refresh after edits.

## Module layout

- `Sources/MiranNotesCore` — `NoteDocument`, `EditCommandEngine`, `UndoInverseSupport`, `TextEditDiff`, `NoteIntegrity`, `ExtensionRegistry`, `CommandPipelineContract`, etc.
- `Sources/MiranNotesApp` — `AppModel`, `MiranNotesApp`, `SingleSurfaceNoteEditor`, `NoteRepository`, vault/commit/index types, editor features.
- `Tests/MiranNotesTests`, `Tests/MiranNotesAppTests` — `swift test`.

## Milestones (historical)

1. **M1 Foundation** — model, schema, repository, invariants.  
2. **M2 Editor shell** — TextKit bridge.  
3. **M3 Core edits** — split/merge, block types, spans.  
4. **M4 Quality** — autosave, atomic persistence.  
5. **M5 Hardening** — migration seam, malformed metadata handling.

## Acceptance checklist (high level)

- [x] Local vault with `.txt` + `.meta.json`; nested paths and manifest v2.  
- [x] Command-based edit pipeline; synchronous `apply` results.  
- [x] Atomic multi-file commits + dirty index writes + startup recovery.  
- [x] Repair / advisory surfaces for load repair, integrity, conflicts, size limit (see `RepairAdvisory`).  
- [x] Hybrid + snapshot undo with cap, coalescing, and safe prune.  
- [x] Slash commands + discovery menu; open registry.  
- [x] Project builds; `swift test` passes.

## Run

```bash
swift build
swift test
swift run
```

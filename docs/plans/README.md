# Planning documents

Use this directory for **planning and roadmaps that belong in version control**: feature specs, phased roadmaps, and review notes that help future contributors and AI sessions understand intent.

## Conventions

- Prefer **descriptive filenames**: `topic_short_slug.md` or `YYYY-MM-topic.md`.
- Link outward to code paths and to [Constraints.md](../../Constraints.md) when the work touches non-negotiable rules.
- If a plan duplicates content from an [ADR](../adr/README.md), reference the ADR instead of restating the decision.

## Relationship to IDE-generated plans

Tools such as Cursor may create plans under **`.cursor/plans/`** on a developer machine. Those files are often **not** committed. When a plan becomes a durable reference for the team, **copy or summarize it here** so clones of the repository include the context.

## Active product surface

**Canonical map:** what the **shipping** macOS app (`MiranNotesApp`) exposes today versus code that remains **compiled but deactivated** or **reference-only** after the Apr 2026 pivot (see [root README](../../README.md) and [Constraints.md](../../Constraints.md) § Product scope). `MiranNotesCore` is shared library code; the **product** is the app shell plus vault/editor UX.

| Surface | Ships in active app | Preserved / not active as product | Primary code paths |
|--------|---------------------|-----------------------------------|--------------------|
| Vault lifecycle (open, reconcile, atomic commits, startup recovery, FS watch) | Yes | — | `Sources/MiranNotesApp/Data/` — `NoteRepository`, `VaultCommitCoordinator`, `VaultManifestRefreshFacade`; `AppModel` in `Sources/MiranNotesApp/App/` |
| Workspace gate (compatibility scan, incompatible folder UX) | Yes | — | `WorkspaceCompatibility.swift`, `WorkspaceIncompatibleView`, `MiranNotesApp` |
| Folders, folder page, note list / search with body snippets | Yes | — | `FolderCatalog`, `FolderPageView`, `WorkspaceFolderSidebarView`, `NotesListView`; body index via `NoteBodySearchIndexController` |
| Block editor, slash commands, wiki links, backlinks | Yes | — | `Features/Editor/` — `SingleSurfaceNoteEditor`, `SlashCommandRegistry`; core engine in `MiranNotesCore/EditCommandEngine`; backlinks via `LinkGraph` / `AppModel` |
| Undo, repair advisories, external-edit conflict UX | Yes | — | `AppModel`, `RepairAdvisory`, `EditorRootView` |
| **Miran Planning** (menu bar, calendar, dashboard, task/session DB UI, Zora migration, `/task` `/session` in product) | **No** — not wired into the active shell | Source preserved under `Sources/MiranNotesApp/Features/Planning/`; pivot details in root README | `PlanningModel`, calendar/database views, migration *(deactivated)* |
| Vault-level **databases** (`_databases/` per [ADR 0004](../adr/0004-vault-level-databases-and-planning.md)) | On-disk format and types remain; **not** a user-facing Planning surface after pivot | `DatabaseDocument`, `DatabaseRepository` in `Data/`; legacy DB product isolated as `MiranNotesLegacyDatabase` for tests — see [architectural-refinements.md](../architecture/architectural-refinements.md) | `DatabaseModels` in core; `VaultDatabasePaths` |
| Per-note `_aux` JSONL tables (historical) | Not surfaced in UI | Optional cleanup per [ADR 0002](../adr/0002-auxiliary-storage-jsonl.md) | — |

## Completed plans

| Plan | Scope | Status |
|------|-------|--------|
| Vault index performance & reconciliation (see [vault-data-layer.md](../architecture/vault-data-layer.md)) | `VaultIndexActor` index caching, `VaultManifest.isDirty`, optional `VaultCommitContext` note fields, `reconcileManifest()` vs read-only `listNotes()`, `invalidateIndexCaches`, deduplicated helpers | Implemented |
| [reliability-and-autosave-fixes.md](reliability-and-autosave-fixes.md) | Navigation race conditions, debounced-save flush before note switch/rename/create, `navigationGeneration` guard, backlink error surfacing | Implemented |
| [robustness-phased-plan.md](robustness-phased-plan.md) | Phased hardening: repair advisory, `adjustBlocks`, slash registry, sync `onCommands`, cursor binding | Implemented (see repo history for test counts) |
| [hybrid-undo-appmodel-wiring.md](hybrid-undo-appmodel-wiring.md) | `UndoInverseSupport.replaceTextChainUndoCommands`, `AppModel` `UndoCheckpoint` hybrid storage, prune rebase, `Constraints` undo section | Implemented |
| [longevity-and-migration-analysis.md](longevity-and-migration-analysis.md) (Part 2) | `AppModel`: `ObservableObject` / `@Published` → `@Observable`; root `@State`; `@Bindable` at binding sites (Apr 2026) | Implemented |
| Vault-level databases & Miran Planning (see [ADR 0004](../adr/0004-vault-level-databases-and-planning.md), [planning-integration.md](../architecture/planning-integration.md)) | Database infrastructure, planning data layer, planning UI, cross-feature integration, Zora migration | Implemented |
| Workspace compatibility & import/drift (see [CHANGELOG.md](../CHANGELOG.md), [guides/ImportingNotes.md](../guides/ImportingNotes.md)) | Structural scan before open; incompatible-folder UI; `NoteIdentityResolution`; `validateVaultDrift` / `VaultDriftReport`; scanner and policy tests | Implemented |

## Active / reference plans

| Plan | Role |
|------|------|
| [quality-dimensions-roadmap.md](quality-dimensions-roadmap.md) | Cross-cutting quality backlog: current strengths and prioritized improvements across reliability, architecture, product goals, usability, performance, security/robustness (for contributors and agents) |
| [reliability-expectations.md](reliability-expectations.md) | Operator-oriented scope notes: startup recovery, link-graph sync thresholds, integrity checks, watcher debounce (aligns advisory copy with real behavior) |
| [longevity-and-migration-analysis.md](longevity-and-migration-analysis.md) | Longevity assessment; **@Observable** and Swift 6 language mode **done**; remaining: TextKit 2 typing migration |
| [vault-write-paths-audit.md](vault-write-paths-audit.md) | Vault write path audit notes |
| [constraints-touchpoint-map.md](constraints-touchpoint-map.md) | Constraints touchpoint mapping |
| [editor-interaction-scenarios.md](editor-interaction-scenarios.md) | Manual QA checklist (ongoing) |

## See also

- [Documentation hub](../README.md)
- [Constraints.md](../../Constraints.md)

# Planning documents

Use this directory for **planning and roadmaps that belong in version control**: feature specs, phased roadmaps, and review notes that help future contributors and AI sessions understand intent.

## Conventions

- Prefer **descriptive filenames**: `topic_short_slug.md` or `YYYY-MM-topic.md`.
- Link outward to code paths and to [Constraints.md](../../Constraints.md) when the work touches non-negotiable rules.
- If a plan duplicates content from an [ADR](../adr/README.md), reference the ADR instead of restating the decision.

## Relationship to IDE-generated plans

Tools such as Cursor may create plans under **`.cursor/plans/`** on a developer machine. Those files are often **not** committed. When a plan becomes a durable reference for the team, **copy or summarize it here** so clones of the repository include the context.

## Active product surface

**Canonical map:** what the **shipping** macOS app (`MiranNotesApp`) exposes today versus **historical** design that lives only in ADRs and archived notes after the Apr 2026 pivot (see [root README](../../README.md) and [Constraints.md](../../Constraints.md) § Product scope). `MiranNotesCore` is shared library code; the **product** is the app shell plus vault/editor UX.

| Surface | Ships in active app | Preserved / not active as product | Primary code paths |
|--------|---------------------|-----------------------------------|--------------------|
| Vault lifecycle (open, reconcile, atomic commits, startup recovery, FS watch) | Yes | — | `Sources/MiranNotesApp/Data/` — `NoteRepository`, `VaultCommitCoordinator`, `VaultManifestRefreshFacade`; `AppModel` in `Sources/MiranNotesApp/App/` |
| Workspace gate (compatibility scan, incompatible folder UX) | Yes | — | `WorkspaceCompatibility.swift`, `WorkspaceIncompatibleView`, `MiranNotesApp` |
| Folders (roles, nested tree, icon browser, moves), search (title/path/body/#tag), quick open, pins/recents | Yes | — | `FolderCatalog`, `FolderPageView`, `FolderIconBrowserView`, `WorkspaceFolderSidebarView`, `AppModel+Search`, `Features/QuickOpen/` |
| Block editor, slash commands (incl. `/task`), wiki links + `[[` autocomplete, backlinks panel, find/replace, tags, attachments | Yes | — | `Features/Editor/`, `Features/Tags/`, `MiranNotesCore/EditCommandEngine`, `AppModel+WikiLinks`, `BacklinksPanelView` |
| Today's Tasks (day picker, rollover, note links) | Yes ([ADR 0009](../adr/0009-task-blocks-and-todays-tasks.md)) | — | `TodaysTasksVaultPageView`, `VaultTodaysTasksStore`, `AppModel+TodaysTasks` |
| Trash, export (Markdown/PDF), Settings window | Yes ([ADR 0008](../adr/0008-trash-and-ui-state-stores.md)) | — | `NoteRepository+Trash`, `TrashPageView`, `NoteMarkdownExporter`, `Features/Settings/` |
| Undo, repair advisories, external-edit conflict UX | Yes | — | `AppModel`, `RepairAdvisory`, `EditorRootView` |
| **Miran Planning** (menu bar, calendar, dashboard, task/session DB UI, Zora migration, `/session`) | **No** — removed from tree; remaining core types deleted Aug 2026 | Historical behavior in [ADR 0004](../adr/0004-vault-level-databases-and-planning.md) and archived docs | — |
| Vault-level **databases** / per-note `_aux` JSONL tables | **No** — code fully deleted (Aug 2026); old vault artifacts are inert files | On-disk format documented in [ADR 0004](../adr/0004-vault-level-databases-and-planning.md) / [ADR 0002](../adr/0002-auxiliary-storage-jsonl.md) | — |

## Completed plans

| Plan | Scope | Status |
|------|-------|--------|
| Vault index performance & reconciliation (see [vault-data-layer.md](../architecture/vault-data-layer.md)) | `VaultIndexActor` index caching, `VaultManifest.isDirty`, optional `VaultCommitContext` note fields, `reconcileManifest()` vs read-only `listNotes()`, `invalidateIndexCaches`, deduplicated helpers | Implemented |
| [reliability-and-autosave-fixes.md](../archive/reliability-and-autosave-fixes.md) | Navigation race conditions, debounced-save flush before note switch/rename/create, `navigationGeneration` guard, backlink error surfacing | Implemented |
| [robustness-phased-plan.md](../archive/robustness-phased-plan.md) | Phased hardening: repair advisory, `adjustBlocks`, slash registry, sync `onCommands`, cursor binding | Implemented (see repo history for test counts) |
| [hybrid-undo-appmodel-wiring.md](../archive/hybrid-undo-appmodel-wiring.md) | `UndoInverseSupport.replaceTextChainUndoCommands`, `AppModel` `UndoCheckpoint` hybrid storage, prune rebase, `Constraints` undo section | Implemented |
| [longevity-and-migration-analysis.md](longevity-and-migration-analysis.md) (Part 2) | `AppModel`: `ObservableObject` / `@Published` → `@Observable`; root `@State`; `@Bindable` at binding sites (Apr 2026) | Implemented |
| Vault-level databases & Miran Planning (see [ADR 0004](../adr/0004-vault-level-databases-and-planning.md)) | Originally: database infrastructure, planning data layer, planning UI, Zora migration — **persistence/UI later removed** (Apr 2026); ADR amended | Superseded by minimal product; on-disk format retained in ADR |
| Workspace compatibility & import/drift (see [CHANGELOG.md](../CHANGELOG.md), [guides/ImportingNotes.md](../guides/ImportingNotes.md)) | Structural scan before open; incompatible-folder UI; `NoteIdentityResolution`; scanner and policy tests (the separate drift validator was later removed as unused) | Implemented |

## Active / reference plans

| Plan | Role |
|------|------|
| [quality-dimensions-roadmap.md](quality-dimensions-roadmap.md) | Cross-cutting quality backlog: current strengths and prioritized improvements across reliability, architecture, product goals, usability, performance, security/robustness (for contributors and agents) |
| [reliability-expectations.md](reliability-expectations.md) | Operator-oriented scope notes: startup recovery, link-graph sync thresholds, integrity checks, watcher debounce (aligns advisory copy with real behavior) |
| [longevity-and-migration-analysis.md](longevity-and-migration-analysis.md) | Longevity assessment; **@Observable** and Swift 6 language mode **done**; remaining: TextKit 2 typing migration |
| [vault-write-paths-audit.md](vault-write-paths-audit.md) | Vault write path audit notes |
| [constraints-touchpoint-map.md](../archive/constraints-touchpoint-map.md) | Constraints touchpoint mapping |
| [editor-interaction-scenarios.md](editor-interaction-scenarios.md) | Manual QA checklist (ongoing) |

## See also

- [Documentation hub](../README.md)
- [Constraints.md](../../Constraints.md)

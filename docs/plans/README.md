# Planning documents

Use this directory for **planning and roadmaps that belong in version control**: feature specs, phased roadmaps, and review notes that help future contributors and AI sessions understand intent.

## Conventions

- Prefer **descriptive filenames**: `topic_short_slug.md` or `YYYY-MM-topic.md`.
- Link outward to code paths and to [Constraints.md](../../Constraints.md) when the work touches non-negotiable rules.
- If a plan duplicates content from an [ADR](../adr/README.md), reference the ADR instead of restating the decision.

## Relationship to IDE-generated plans

Tools such as Cursor may create plans under **`.cursor/plans/`** on a developer machine. Those files are often **not** committed. When a plan becomes a durable reference for the team, **copy or summarize it here** so clones of the repository include the context.

## Completed plans

| Plan | Scope | Status |
|------|-------|--------|
| Vault index performance & reconciliation (see [vault-data-layer.md](../architecture/vault-data-layer.md)) | `VaultIndexActor` index caching, `VaultManifest.isDirty`, optional `VaultCommitContext` note fields, `reconcileManifest()` vs read-only `listNotes()`, `invalidateIndexCaches`, deduplicated helpers | Implemented |
| [reliability-and-autosave-fixes.md](reliability-and-autosave-fixes.md) | Navigation race conditions, debounced-save flush before note switch/rename/create, `navigationGeneration` guard, backlink error surfacing | Implemented |
| [robustness-phased-plan.md](robustness-phased-plan.md) | Phased hardening: repair advisory, `adjustBlocks`, slash registry, sync `onCommands`, cursor binding | Implemented (see repo history for test counts) |
| [hybrid-undo-appmodel-wiring.md](hybrid-undo-appmodel-wiring.md) | `UndoInverseSupport.replaceTextChainUndoCommands`, `AppModel` `UndoCheckpoint` hybrid storage, prune rebase, `Constraints` undo section | Implemented |
| [longevity-and-migration-analysis.md](longevity-and-migration-analysis.md) (Part 2) | `AppModel`: `ObservableObject` / `@Published` → `@Observable`; root `@State`; `@Bindable` at binding sites (Apr 2026) | Implemented |
| Vault-level databases & Miran Planning (see [ADR 0004](../adr/0004-vault-level-databases-and-planning.md), [planning-integration.md](../architecture/planning-integration.md)) | Database infrastructure, planning data layer, planning UI, cross-feature integration, Zora migration | Implemented |

## Active / reference plans

| Plan | Role |
|------|------|
| [longevity-and-migration-analysis.md](longevity-and-migration-analysis.md) | Longevity assessment; **@Observable migration done**; remaining: TextKit 2, Swift 6 concurrency |
| [vault-write-paths-audit.md](vault-write-paths-audit.md) | Vault write path audit notes |
| [constraints-touchpoint-map.md](constraints-touchpoint-map.md) | Constraints touchpoint mapping |
| [editor-interaction-scenarios.md](editor-interaction-scenarios.md) | Manual QA checklist (ongoing) |

## See also

- [Documentation hub](../README.md)
- [Constraints.md](../../Constraints.md)

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
| [reliability-and-autosave-fixes.md](reliability-and-autosave-fixes.md) | Navigation race conditions, debounced-save flush before note switch/rename/create, `navigationGeneration` guard, backlink error surfacing | Implemented |
| [robustness-phased-plan.md](robustness-phased-plan.md) | Phased hardening: repair advisory, `adjustBlocks`, slash registry, sync `onCommands`, cursor binding, tables | Implemented (see repo history for test counts) |
| [hybrid-undo-appmodel-wiring.md](hybrid-undo-appmodel-wiring.md) | `UndoInverseSupport.replaceTextChainUndoCommands`, `AppModel` `UndoCheckpoint` hybrid storage, prune rebase, `Constraints` undo section | Implemented |

## Active / reference plans

| Plan | Role |
|------|------|
| [vault-write-paths-audit.md](vault-write-paths-audit.md) | Vault write path audit notes |
| [constraints-touchpoint-map.md](constraints-touchpoint-map.md) | Constraints touchpoint mapping |
| [editor-interaction-scenarios.md](editor-interaction-scenarios.md) | Manual QA checklist (ongoing) |

## See also

- [Documentation hub](../README.md)
- [Constraints.md](../../Constraints.md)

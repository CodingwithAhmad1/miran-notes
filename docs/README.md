# Miran Notes — documentation hub

**Start here** when you open the repository in a new editor session or need the map of how documentation fits together.

## What this project is

Miran Notes is a **local-first** macOS notes app: canonical text in `note.txt`, structured metadata in a sidecar, edits through `EditCommandEngine`, and a SwiftUI + AppKit editor. See the [root README](../README.md) for build commands, module layout, and milestones.

## Document map

| Document | Role |
|----------|------|
| [README.md](../README.md) | Product overview, architecture summary, how to run and test |
| [Constraints.md](../Constraints.md) | Non‑negotiable engineering constraints, known limits, editor pipeline rules |
| [docs/architecture/slash-command-framework.md](architecture/slash-command-framework.md) | Slash command contracts, discovery UX behavior, and extension pattern |
| [docs/adr/](adr/README.md) | Architecture Decision Records (ADRs) — durable decisions with context |
| [docs/plans/](plans/README.md) | Planning notes and roadmaps that should live **in the repo** |
| [docs/plans/editor-interaction-scenarios.md](plans/editor-interaction-scenarios.md) | Manual QA checklist for typing, blocks, spans, IME, large notes |

## How to use this folder

- **Constraints** stay at the repository root so they stay visible; they are linked from here.
- **ADRs** live under `docs/adr/` with numeric prefixes (`0001-…`, `0002-…`). Add new ADRs in sequence when a decision is stable enough to document.
- **Planning** for features and roadmaps: add markdown under `docs/plans/` when the work should be shared with anyone who clones the repo. IDE-specific scratch plans may live elsewhere; see `docs/plans/README.md`.

## Code pointers (quick orientation)

- **Core model and edits:** `Sources/MiranNotesCore/` — `NoteDocument` (identity via `metadata.noteID`), `EditCommandEngine` (includes `splitBlock` with `constrainToBlocks`, `reconcileBlocksFromText`, `replaceMetadataBlocks`), `TextEditDiff` (UTF-16 incremental sync helper), `NoteIntegrity`, `RangeNormalizer`, `SpanAdjuster`, `ExtensionPoints`.
- **App and editor:** `Sources/MiranNotesApp/` — `SingleSurfaceNoteEditor` (1 MB cap, full-buffer warning, incremental styling), `EditorVisualStyle`, `SlashCommandRegistry` (open via `register(_:)`, built-ins via `registerBuiltins()`), `SlashQueryDetector`, `SlashCommandMatcher`.
- **Data layer:** `NoteRepository` (returns `NoteLoadResult`, two-phase `VaultCommitCoordinator`, dirty-flag participants); `LinkGraph`, `RelationshipIndex`, `FolderCatalog`, `PathIndex` (each with `isDirty` flag).
- **App state:** `AppModel` — `repairNotice`, `editorCursorOffset`, `undoHistory` (count-bounded, 200 steps), `cachedLinkGraph` (debounced refresh), `apply(_:) -> NoteDocument`, `removeCommandInterceptor(_:)`.
- **Tests:** `Tests/MiranNotesTests/` (core + `adjustBlocks` + `splitBlock` cross-boundary), `Tests/MiranNotesAppTests/` (app, navigation, undo, dirty-flag, watcher-race, visual style).

## Key `AppModel` published properties

| Property | Purpose |
|----------|---------|
| `activeDocument` | Current `NoteDocument` in the editor |
| `repairNotice: String?` | Non-nil when load-time repair ran, link metadata is missing, full-buffer replace fired, or size limit was hit |
| `editorCursorOffset: Int` | Live UTF-16 caret position fed by `SingleSurfaceNoteEditor`; reset to 0 on note switch |
| `lastError: String?` | Most recent async operation failure message |
| `externalEditConflictAlert` | Non-nil when an external file change conflicts with a dirty buffer |

## Key `AppModel` internal properties (visible to `@testable` imports)

| Property | Purpose |
|----------|---------|
| `undoHistory: [UndoStep]` | Deque of `(before, after, actionName)` snapshots; pruned to 200 entries |
| `cachedLinkGraph: LinkGraph?` | In-memory cache; nil after save or vault reload |

For deeper editor behavior and limits, read [Constraints.md](../Constraints.md) before changing the text pipeline or metadata rules.

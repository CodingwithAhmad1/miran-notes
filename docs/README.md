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

## How to use this folder

- **Constraints** stay at the repository root so they stay visible; they are linked from here.
- **ADRs** live under `docs/adr/` with numeric prefixes (`0001-…`, `0002-…`). Add new ADRs in sequence when a decision is stable enough to document.
- **Planning** for features and roadmaps: add markdown under `docs/plans/` when the work should be shared with anyone who clones the repo. IDE-specific scratch plans may live elsewhere; see `docs/plans/README.md`.

## Code pointers (quick orientation)

- Core model and edits: `Sources/MiranNotesCore/` (`NoteDocument`, `EditCommandEngine`, `NoteIntegrity`, `RangeNormalizer`).
- App and editor: `Sources/MiranNotesApp/` (`SingleSurfaceNoteEditor`, `EditorVisualStyle`, `SlashCommandRegistry`, `SlashQueryDetector`, `SlashCommandMatcher`, persistence).
- Data layer: `NoteRepository` (returns `NoteLoadResult`); `AppModel` (`repairNotice`, `editorCursorOffset`, `apply(_:) -> NoteDocument`).
- Tests: `Tests/MiranNotesTests/` (core + `adjustBlocks`), `Tests/MiranNotesAppTests/` (app, navigation, repair notices, table/cursor).

## Key `AppModel` published properties

| Property | Purpose |
|----------|---------|
| `activeDocument` | Current `NoteDocument` in the editor |
| `repairNotice: String?` | Non-nil when load-time structural repair ran or `[[link]]` syntax has no metadata |
| `editorCursorOffset: Int` | Live UTF-16 caret position fed by `SingleSurfaceNoteEditor` |
| `lastError: String?` | Most recent async operation failure message |
| `externalEditConflictAlert` | Non-nil when an external file change conflicts with a dirty buffer |

For deeper editor behavior and limits, read [Constraints.md](../Constraints.md) before changing the text pipeline or metadata rules.

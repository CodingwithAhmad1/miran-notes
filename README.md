# Miran Notes (macOS)

A simple, Mac-native knowledge storer. Local-first, plain-text storage, zero cloud dependency —
with wiki links, backlinks, and full-text search as the connective tissue.

**Documentation hub:** [docs/README.md](docs/README.md) — index of [Constraints.md](Constraints.md), ADRs, architecture notes, plans, and code pointers. **Change history:** [docs/CHANGELOG.md](docs/CHANGELOG.md).

## What it does

- **Notes** live in a vault folder you choose: canonical body in `{relativePath}.txt` (or `.md`,
  chosen per folder), metadata in `{relativePath}.meta.json`. Everything stays human-readable on disk.
- **Wiki links**: type `[[` anywhere for note autocomplete (or create the note on the spot); links
  are styled, clickable, and survive rename/move because they target a persistent `noteID`
  ([ADR 0001](docs/adr/0001-wiki-links-and-identity.md), [ADR 0007](docs/adr/0007-knowledge-layer-activation.md)).
  A **Linked mentions** strip under the editor lists backlinks with snippets.
- **Search** (toolbar or **Quick Open**, ⌘P) matches titles, paths, and note bodies with snippets;
  `#tag` queries filter by tag. Pinned notes and recents fill the empty palette.
- **Folders** have roles — *Dashboard* (nested folders) or *Repository* (notes) — shown in a nested
  sidebar tree and on folder pages as a **Finder-style icon browser**: arrange icons freely
  (positions persist per folder), double-click to open, drag a note onto a folder to move it, or use
  list view. Drag-and-drop and "Move To" work from lists and the sidebar too.
- **Editor**: block-based single surface (headings, lists, tasks, callouts, code, dividers) with a
  slash menu (`/h1`, `/list`, `/task`…), bold/italic/code spans, find & replace, tags, and
  **attachments** (`[attachment: file]` tokens; files stored beside the note). Markdown notes open
  in a source view with a rendered preview.
- **Today's Tasks**: a per-day checklist at the vault root with a calendar day picker, rollover of
  unfinished tasks, and one-way links from note task blocks ([ADR 0009](docs/adr/0009-task-blocks-and-todays-tasks.md)).
- **Trash**: deleting a note moves it to `.miran/trash/` for restore (identity preserved) until you
  empty it ([ADR 0008](docs/adr/0008-trash-and-ui-state-stores.md)).
- **Export**: any note as Markdown or PDF (File menu).
- **Safety**: two-phase atomic vault commits with crash recovery, external-edit detection with an
  explicit conflict flow, structural compatibility gating when opening folders, and repair
  advisories instead of silent fixes.

## Architecture (implemented)

- **Identity:** `NoteDocument.id` delegates to `metadata.noteID` — one source of truth.
- **Editing pipeline:** all structural mutations go through `EditCommandEngine`;
  `AppModel.apply(_:)` returns the resulting document synchronously; only `EditorSyncController`
  assigns canonical text to the `NSTextView` (TextKit 1 by policy; see Constraints.md).
- **Persistence:** two-phase atomic commits (`VaultCommitCoordinator`) over six participants with
  dirty-flag skipping, startup recovery under `.miran/pending-commits/`, and in-memory index caches
  (`VaultIndexActor`). Presentation state (`.miran/ui-state/`), task pages, and trash deliberately
  live outside the commit set ([ADR 0008](docs/adr/0008-trash-and-ui-state-stores.md)).
- **App state:** `AppModel` is `@MainActor @Observable`, split across focused extension files
  (`AppModel+Search`, `+Backlinks`, `+WikiLinks`, `+Folders`, `+TodaysTasks`, `+Trash`, …).
- **Undo:** window `NSUndoManager` with a hybrid checkpoint timeline (inverse `replaceText` chains +
  full snapshots), 300 ms coalescing, 200-step cap.
- **Vault access:** the vault-root security-scoped bookmark persists; launches reopen the last vault
  (toggleable in Settings) with compatibility gating before any I/O ([ADR 0006](docs/adr/0006-threat-model-app-sandbox-vault-access.md), amended).
- **Preferences:** `AppSettings` (UserDefaults-backed `@Observable`) behind the ⌘, Settings window.

## Module layout

- `Sources/MiranNotesCore` — `NoteDocument`, `EditCommandEngine`, span/link adjusters,
  `NoteIntegrity`, `UndoInverseSupport`, `TextEditDiff`, `ExtensionRegistry` (interceptors).
- `Sources/MiranNotesApp/Data` — `NoteRepository` (+`NoteFileActor`, `VaultIndexActor`), commits,
  watchers, trash, attachments, search indexes, UI-state stores.
- `Sources/MiranNotesApp/Features` — Editor (single-surface + markdown source, slash and `[[`
  menus), Workspace (sidebar, folder pages, icon browser, backlinks, trash), QuickOpen, Tags,
  Settings.
- `Tests/MiranNotesTests`, `Tests/MiranNotesAppTests` — `swift test`.

## Vault (first launch)

Pick or create a folder the first time; afterwards the app reopens your last vault automatically
(disable in Settings → General). **Switch Vault…** is ⇧⌘O. For development,
`MIRAN_USE_DEFAULT_VAULT=1` uses `~/MiranNotesVault` without a picker.

## Run

```bash
swift build
swift test
swift run          # or: Scripts/build-app.sh for a double-clickable MiranNotes.app
```

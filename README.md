# Miran Notes MVP (macOS)

Local-first, Swift-native notes editor with plain-text storage and sidecar metadata.

**Documentation hub (start here for context in a new session):** [docs/README.md](docs/README.md) — map of [Constraints.md](Constraints.md), ADRs, plans, and code pointers.

## Implemented Architecture

- `note.txt` holds canonical text content.
- `note.meta.json` stores `schemaVersion`, block ranges, span styles, links, and artifact refs.
- SwiftUI renders block rows while TextKit2 powers inline text editing via `NSTextView`.
- **Single source of truth for note identity:** `NoteDocument.id` is a computed property delegating to `metadata.noteID`; there is no separate stored `id` field.
- All editor mutations run through `EditCommandEngine`; `apply(_:)` returns the resulting `NoteDocument` synchronously so callers (editor coordinator, tests) can refresh immediately.
- **`splitBlock` safety:** after every block split, `SpanAdjuster.constrainToBlocks` and `LinkAdjuster.constrainToBlocks` clip any spans or wiki-links that crossed the new boundary.
- Metadata invariants: `adjustBlocks` handles single-block, zero-length-merge, and multi-block-collapse cases deterministically; `RangeNormalizer` fallback fires only for edge cases and logs when it does; `NoteIntegrity` validates structure.
- **Atomic vault commits (two-phase):** `VaultCommitCoordinator` runs a prepare phase (all participants write to temp files) followed by a commit phase (atomic rename into final paths). A failure during preparation leaves all vault files untouched.
- **Dirty-flag saves:** `LinkGraph`, `RelationshipIndex`, `FolderCatalog`, and `PathIndex` each expose `isDirty`. Their `VaultCommitParticipant` implementations skip serialization and temp-file writes when unchanged, eliminating spurious `mtime` bumps.
- Debounced autosave writes text and metadata; **load** (`NoteLoadResult`) re-runs `RangeNormalizer` and falls back to a single-block repair; any repair warnings are surfaced to the user via a dismissible banner (`repairNotice`).
- **Note size cap:** edits that would push a note past 1 MB (UTF-16) are rejected with a user-visible notice.
- **Cursor tracking:** `SingleSurfaceNoteEditor` publishes `cursorOffset` via `@Binding`; `AppModel.editorCursorOffset` reflects the live caret position so operations like wiki-link insertion land at the cursor rather than end-of-document. The offset is reset to 0 when switching notes.
- **Undo (count-bounded):** `AppModel` keeps checkpoint timelines capped at 200 steps (`UndoPolicy.maxUndoSteps`), with optional **coalescing** of rapid single-`replaceText` edits (`UndoPolicy.coalesceReplaceTextWindowNanoseconds`, default 300 ms). Oldest checkpoints are pruned with re-registration on `NSUndoManager`. Command interceptors use `UUID` tokens and `removeCommandInterceptor(_:)`.
- **Backlink cache:** `AppModel` keeps `cachedLinkGraph` in memory and debounces refreshes by 1 500 ms, avoiding per-keystroke full-vault scans. The cache is invalidated on vault save or reload.
- **Incremental visual styling:** `EditorVisualStyle.apply` is guarded by a document-ID and text cache; styling passes are skipped when content has not changed.
- **Slash commands:** `/h1`–`/h3`, `/p`, `/code`, `/list` (alias: `/bullet`), `/divider`, `/callout`. The registry is open: call `SlashCommandRegistry.register(_:)` to add commands without modifying core code. Built-ins are registered once at app startup via `SlashCommandRegistry.registerBuiltins()`.
- **Slash discovery menu (Notion-like):**
  - Typing `/` opens a searchable command menu near the caret.
  - Typing more characters filters commands dynamically.
  - Arrow Up/Down navigates, Enter/Tab applies highlighted command, Esc closes.
  - Unknown commands (for example `/doesntwork`) remain plain text and show `No commands found`.

## Module Layout

- `Sources/MiranNotesCore` — domain models (`NoteDocument`, `Block`, `Span`, `NoteLink`), `EditCommandEngine`, `RangeNormalizer`, `SpanAdjuster`, `NoteIntegrity`, `ExtensionPoints`.
- `Sources/MiranNotesApp` — app shell (`AppModel`, `MiranNotesApp`), features (`SingleSurfaceNoteEditor`, `EditorVisualStyle`, `SlashCommandRegistry`), data layer (`NoteRepository`, `VaultCommitCoordinator`, `LinkGraph`, `RelationshipIndex`, `FolderCatalog`, `PathIndex`).
- `Tests/MiranNotesTests` — core unit + regression tests; `Tests/MiranNotesAppTests` — app-layer, repository, undo, performance, and watcher-race tests (`swift test`).

## MVP Milestones

1. **M1 Foundation**: model contracts, schema versioning, vault repository, invariants validator.
2. **M2 Editor Shell**: block list view + TextKit2 editor bridge.
3. **M3 Core Edits**: insert/delete, split/merge APIs, block type change, span style toggles.
4. **M4 Quality**: autosave debounce, atomic persistence, compile verification.
5. **M5 Hardening**: metadata migration seam and malformed metadata normalization.

## Acceptance Checklist

- [x] Local vault storage using `.txt` + `.meta.json`.
- [x] Block types modeled for paragraph, heading, list item, callout, code, divider.
- [x] Command-based edit pipeline; `apply(_:)` returns `NoteDocument` synchronously.
- [x] `NoteDocument.id` is a computed property; `metadata.noteID` is the single source of truth.
- [x] `splitBlock` constrains spans and links to new block boundaries via `constrainToBlocks`.
- [x] TextKit2-backed editable block integration on macOS; cursor position tracked via `@Binding`; offset reset on note switch.
- [x] Two-phase atomic vault commit (prepare → rename); dirty-flag guards skip unchanged index writes.
- [x] Debounced persistence with atomic writes; `NoteLoadResult` surfaces repair warnings.
- [x] Dismissible repair-notice banner when load-time structural repair ran, link metadata is missing, full-buffer fallback fired, or note size limit was hit.
- [x] Note size cap at 1 MB (UTF-16); rejection triggers user notice.
- [x] Count-bounded undo (200 steps) with graceful oldest-first pruning; interceptors deregisterable via `UUID` token.
- [x] In-memory backlink cache with 1 500 ms debounce; invalidated on save/reload.
- [x] Incremental `EditorVisualStyle.apply`; skipped when document ID and text unchanged.
- [x] Slash commands `/list`, `/divider`, `/callout` registered alongside `/h1`–`/h3`, `/p`, `/code`; registry open for external extension via `register(_:)`.
- [x] Slash discovery menu supports dynamic filtering, keyboard selection, and explicit no-match state.
- [x] Deterministic `adjustBlocks` without normalize in common paths; fallback logged when triggered.
- [x] Filename slugs capped at 200 UTF-8 bytes with scalar-boundary truncation.
- [x] Project builds and all tests pass (`swift test`).

## Run

```bash
swift build
swift test
swift run
```

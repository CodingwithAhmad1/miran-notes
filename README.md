# Miran Notes MVP (macOS)

Local-first, Swift-native notes editor with plain-text storage and sidecar metadata.

**Documentation hub (start here for context in a new session):** [docs/README.md](docs/README.md) — map of [Constraints.md](Constraints.md), ADRs, plans, and code pointers.

## Implemented Architecture

- `note.txt` holds canonical text content.
- `note.meta.json` stores `schemaVersion`, block ranges, span styles, links, and artifact refs.
- SwiftUI renders block rows while TextKit2 powers inline text editing via `NSTextView`.
- All editor mutations run through `EditCommandEngine`; `apply(_:)` returns the resulting `NoteDocument` synchronously so callers (editor coordinator, tests) can refresh immediately.
- Metadata invariants: `adjustBlocks` handles single-block, zero-length-merge, and multi-block-collapse cases deterministically; `RangeNormalizer` fallback fires only for edge cases and logs when it does; `NoteIntegrity` validates structure.
- Debounced autosave writes text and metadata using **per-file** atomic replaces (`tmp` + `replaceItemAt`). A crash between the two writes can leave the pair briefly inconsistent; **load** (`NoteLoadResult`) re-runs `RangeNormalizer` and falls back to a single-block repair; any repair warnings are surfaced to the user via a dismissible banner (`repairNotice`).
- **Cursor tracking:** `SingleSurfaceNoteEditor` publishes `cursorOffset` via `@Binding`; `AppModel.editorCursorOffset` reflects the live caret position so operations like wiki-link insertion land at the cursor rather than end-of-document.
- **Slash commands:** `/h1`–`/h3`, `/p`, `/code`, `/list` (alias: `/bullet`), `/divider`, `/callout`.
- **Slash discovery menu (Notion-like):**
  - Typing `/` opens a searchable command menu near the caret.
  - Typing more characters filters commands dynamically.
  - Arrow Up/Down navigates, Enter/Tab applies highlighted command, Esc closes.
  - Unknown commands (for example `/doesntwork`) remain plain text and show `No commands found`.

## Module Layout

- `Sources/MiranNotesCore` domain models, `EditCommandEngine`, `RangeNormalizer`, `SpanAdjuster`, `NoteIntegrity`.
- `Sources/MiranNotesApp` app shell, features, data layer, single-surface editor.
- `Tests/MiranNotesTests` core unit tests; `Tests/MiranNotesAppTests` repository / app-layer tests (`swift test`).

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
- [x] TextKit2-backed editable block integration on macOS; cursor position tracked via `@Binding`.
- [x] Debounced persistence with atomic writes; `NoteLoadResult` surfaces repair warnings.
- [x] Dismissible repair-notice banner when load-time structural repair ran or link metadata is missing.
- [x] Slash commands `/list`, `/divider`, `/callout` registered alongside `/h1`–`/h3`, `/p`, `/code`.
- [x] Slash discovery menu supports dynamic filtering, keyboard selection, and explicit no-match state.
- [x] Deterministic `adjustBlocks` without normalize in common paths; fallback logged when triggered.
- [x] Project builds and all 55 tests pass (`swift test`).

## Run

```bash
swift build
swift test
swift run
```

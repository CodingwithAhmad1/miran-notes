# Miran Notes MVP (macOS)

Local-first, Swift-native notes editor with plain-text storage and sidecar metadata.

## Implemented Architecture

- `note.txt` holds canonical text content.
- `note.meta.json` stores `schemaVersion`, block ranges, and span styles.
- SwiftUI renders block rows while TextKit2 powers inline text editing via `NSTextView`.
- All editor mutations run through `EditCommandEngine`.
- Metadata invariants: incremental updates with `RangeNormalizer` fallback when needed; `NoteIntegrity` validates structure.
- Debounced autosave writes text and metadata using **per-file** atomic replaces (`tmp` + `replaceItemAt`). A crash between the two writes can leave the pair briefly inconsistent; **load** re-runs `RangeNormalizer` and falls back to a single-block repair so the editor always opens a structurally valid document.

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
- [x] Command-based edit pipeline with post-edit normalization.
- [x] TextKit2-backed editable block integration on macOS.
- [x] Debounced persistence with atomic writes.
- [x] Project builds successfully with `swift build`.

## Run

```bash
swift build
swift test
swift run
```

# ADR 0001: Wiki links and note identity

## Status

Accepted (implementation follows this ADR).

## Context

Miran Notes uses human-readable `note.txt` plus sidecar `note.meta.json`. Filenames (`baseName`) can change; wiki links must remain stable.

## Decisions

### Persistent note identity

- Each note has a **`noteID: UUID`** stored in `Note.meta.json` (schema v2+).
- Resolution and backlinks use **`noteID`** as the canonical target. Filenames are a display/storage key only.
- On first load of legacy metadata without `noteID`, the app assigns a new UUID and persists it on next save.

### Wiki syntax in `.txt`

- Inserted links use visible text: **`[[Display Title]]`** (matching the literal characters in the note body).
- Parallel metadata **`links[]`** stores UTF-16 `TextRange`, **`targetNoteID`**, and optional **`label`** for future display overrides.
- Hit-testing and navigation use metadata ranges; plain `[[...]]` text remains portable for other tools.

### Broken links

- **Policy:** highlight-only in the editor (visual affordance); **do not** block save.
- **`LinkResolver`** returns an optional target; UI shows an error or muted style when unresolved.

### Integrity- **`NoteIntegrity`** continues to validate block partitions and span bounds.
- **Link** ranges must lie within `[0, text.utf16.count]`; validated separately or alongside spans in the same check pass without asserting on unrelated features in the hot path.

## Consequences

- Rename note files updates the vault manifest only; **link targets unchanged**.
- External editors that strip `.meta.json` links still show `[[...]]` text; re-open in Miran may require a repair pass to rebuild `links[]` from syntax (future optional tool).

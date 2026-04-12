# ADR 0002: Auxiliary storage (tables / JSONL)

## Status

Accepted (implementation follows this ADR).

## Context

Large structured data must not slow the plain-text editing pipeline. Tables and similar artifacts need a clear on-disk layout and stable paths across note renames.

## Decisions

### Layout

- Per-note auxiliary directory: **`{vault}/_aux/{noteID-uuid-lowercased}/`**
- Table data: **`{vault}/_aux/{noteID}/tables/{artifactID}.jsonl`**
- Each line is one JSON object (**JSONL**), UTF-8, one row per line.

### Row schema (v1)

```json
{"id":"<uuid>","cells":{"Column A":"value","Column B":123}}
```

- **`id`:** stable row UUID (string).
- **`cells`:** string-keyed map; values are JSON primitives (`string`, `number`, `bool`, `null`) for MVP.

### Table schema header (optional companion)

- **`{artifactID}.schema.json`** next to the JSONL file defines column order and types for the UI:

```json
{"columns":[{"id":"col1","title":"Name","type":"string"},{"id":"col2","title":"Count","type":"number"}]}
```

If missing, the UI infers columns from the first row or empty table defaults.

### Metadata linkage

- **`NoteMetadata.artifacts[]`** lists `EmbeddedArtifact` with `id`, `kind: table`, and **`relativePath`** relative to `_aux/{noteID}/` (e.g. `tables/{artifactID}.jsonl`).

### Performance

- **Lazy load:** JSONL is read only when the user opens a table editor or explicitly loads that artifact.
- **Saves:** debounced, atomic replace (tmp + move) mirroring note saves; no full-file rewrite on every keystroke—buffer in memory, flush periodically.
- **Undo:** table surface maintains a **bounded** local undo stack separate from note snapshot undo.

## Consequences

- Renaming the note **file** does not move `_aux/{noteID}` (directory is keyed by `noteID`).
- Backup tools should include `_aux/` and `.miran/` for a complete vault.

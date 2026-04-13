# ADR 0002: Auxiliary storage (tables / JSONL)

## Status

**Withdrawn for product use** (Apr 2026). The app **no longer creates, edits, or links** per-note JSONL “tables” in the UI. This ADR remains as **historical documentation** for vaults that still contain `_aux/{noteID}/tables/` files from older builds, and for the shared **row record** shapes reused by vault-level databases ([ADR 0004](0004-vault-level-databases-and-planning.md)).

## Context

Large structured data must not slow the plain-text editing pipeline. An early experiment stored note-scoped tabular rows in JSONL under `_aux/` and referenced them from `NoteMetadata.artifacts` with `kind: table`.

## Decisions (historical layout)

### Layout

- Per-note auxiliary directory: **`{vault}/_aux/{noteID-uuid-lowercased}/`**
- Former table data path: **`{vault}/_aux/{noteID}/tables/{artifactID}.jsonl`**
- Each line was one JSON object (**JSONL**), UTF-8, one row per line.

### Row schema (v1)

```json
{"id":"<uuid>","cells":{"Column A":"value","Column B":123}}
```

- **`id`:** stable row UUID.
- **`cells`:** string-keyed map; values as JSON primitives.

### Table schema header (optional companion)

- **`{artifactID}.schema.json`** next to the JSONL file defined column order and types.

### Metadata linkage (legacy)

- Older `.meta.json` could list `EmbeddedArtifact` entries with **`kind: table`** and `relativePath` under `_aux/{noteID}/`.

## Current behavior (post-withdrawal)

- On load, **`NoteMetadata` decoding drops `kind: "table"` artifacts** so existing vaults open without failure. The next save persists metadata **without** those entries.
- The app does **not** write new table artifacts or open a table editor.
- **Orphan files:** `_aux/.../tables/*.jsonl` and `*.schema.json` may remain until the user deletes them or deletes the note (note delete still removes the whole `_aux/{noteID}/` tree).

## Consequences

- Renaming the note **file** does not move `_aux/{noteID}` (directory is keyed by `noteID`).
- Backup tools should include `_aux/` and `.miran/` for a complete vault if those directories exist.

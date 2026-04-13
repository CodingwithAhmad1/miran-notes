# ADR 0004 — Vault-level databases and Miran Planning

**Status:** Accepted  
**Date:** 2026-04-12

## Context

Miran Notes once experimented with per-note JSONL tables under `_aux/{noteID}/` ([ADR 0002](0002-auxiliary-storage-jsonl.md)); that path was scoped to individual notes, bypassed the `VaultCommitCoordinator`, and lacked a query layer (the standalone table UI was later withdrawn—0002 is historical). The Zora Planning application was a separate standalone menu-bar app using YAML frontmatter in `.md` files for tasks and sessions — architecturally disconnected from Miran Notes.

The goal was to integrate planning (tasks, sessions, calendar, dashboard) seamlessly into Miran Notes, similar to how Notion Calendar connects with Notion: shared data layer, cross-linking, and unified UI.

## Decision

### Vault-level database layer

Promote databases from per-note auxiliary artifacts to **first-class vault-level entities** stored under `_databases/{databaseID}/`:

```
vault/
├── _databases/
│   ├── {databaseID}/
│   │   ├── schema.json          # DatabaseSchema
│   │   ├── rows.jsonl           # TableRowRecord lines
│   │   └── views/
│   │       └── {viewID}.json    # DatabaseViewConfig
│   └── ...
└── .miran/
    ├── database-registry.json   # DatabaseRegistry
    └── planning-config.json     # PlanningConfig
```

- **`DatabaseRegistry`** (in `.miran/`) tracks all databases with `DatabaseRegistryRecord` entries (id, name, kind, createdAt).
- **`DatabaseSchema`** defines typed columns with `DatabaseColumnDefinition` supporting 10 column types: string, number, boolean, date, select, multiSelect, relation, noteLink, url, duration.
- **`DatabaseDocument`** (actor) manages per-database schema, rows, and views with atomic writes and a query engine for filtering/sorting.
- **`DatabaseRepository`** (actor) is the facade for database CRUD, paralleling `NoteRepository` for notes.

### Extended core types

- `LinkTarget` gains `.database(databaseID:)` and `.databaseRow(databaseID:, rowID:)` cases for cross-entity linking.
- `TableRowRecord` gains `Identifiable` conformance.
- `RelationshipIndex` gains `removeAllInvolvingDatabase(_:)`.
- `VaultIntegrityChecker` handles the new `LinkTarget` cases.

### Built-in planning databases

Two databases are bootstrapped automatically:
- **Tasks** (`DatabaseKind.tasks`) — title, type, subject, date, time, duration, priority, status, linkedNote, project.
- **Sessions** (`DatabaseKind.sessions`) — title, type, subject, topic, sessionType, date, startTime, duration, objective, status, linkedNote.

### Integration architecture

`PlanningModel` (`@MainActor ObservableObject`) owns domain logic: quick add, toggle complete, backlog detection, date navigation, weekly review metrics. It is instantiated by `AppModel` during vault load and published as `@Published var planningModel`.

The app shell gains an `AppContentMode` switcher (.notes / .planning) with Cmd+1 / Cmd+2 shortcuts. The planning UI includes: dashboard, calendar (daily/weekly/monthly/review), database views (table/board), edit sheets, and settings.

Cross-feature bridges: `/task` and `/session` slash commands, `linkActiveNoteToTask`, `openLinkedNote`, and inline embeddable views (`InlineTaskListView`, `InlineSessionListView`).

### Migration from Zora

`ZoraMigrationEngine` parses YAML frontmatter from Zora's `.md` files and imports rows into the Miran database layer. Config (subjects, colors) migrates to `planning-config.json`.

## Consequences

- **Per-note table artifacts** (`_aux/…/tables/`) are no longer created by the app (see ADR 0002); vault-level databases under `_databases/` are the structured-data path.
- Database persistence currently uses direct file I/O rather than participating in `VaultCommitCoordinator` atomic commits. This is acceptable because database writes are self-contained (not entangled with note saves), but a future enhancement could add a `DatabaseCommitParticipant` for coordinated multi-entity transactions.
- The `DatabaseRegistry` index adds a new file to `.miran/` that older Miran Notes versions will ignore (forward-compatible by convention).
- Planning schemas are predefined but extensible — users can add columns, views, and filters.
- The Zora Planning standalone app is superseded by the integrated feature module.

# Miran Planning — architecture and integration

## Overview

Miran Planning is a built-in feature module that provides structured planning workflows (tasks, sessions, calendars, dashboards) on top of the Miran Notes vault-level database layer. It replaces the standalone Zora Planning application with a deeply integrated feature that shares the same vault, data models, and linking system.

## On-disk layout

```
vault/
├── _databases/
│   ├── {tasksDbID}/
│   │   ├── schema.json       # DatabaseSchema with predefined task columns
│   │   ├── rows.jsonl         # One TableRowRecord per line
│   │   └── views/
│   │       ├── {viewID}.json  # "All Tasks" table view
│   │       └── {viewID}.json  # "Calendar" calendar view
│   └── {sessionsDbID}/
│       ├── schema.json
│       ├── rows.jsonl
│       └── views/
│           ├── {viewID}.json
│           └── {viewID}.json
└── .miran/
    ├── database-registry.json # DatabaseRegistry: list of all databases
    └── planning-config.json   # PlanningConfig: subjects, colors, defaults
```

## Data model

### Database infrastructure (MiranNotesCore)

| Type | Role |
|------|------|
| `DatabaseColumnType` | 10 types: string, number, boolean, date, select, multiSelect, relation, noteLink, url, duration |
| `DatabaseColumnDefinition` | Column spec: id, title, type, options, relationDatabaseID, required |
| `DatabaseSchema` | Versioned column list with lookup helpers |
| `DatabaseRegistryRecord` | Database identity: id, name, kind, createdAt |
| `DatabaseRegistry` | Index of all databases with CRUD and isDirty tracking |
| `DatabaseViewConfig` | View definition: layout (table/board/calendar/list), filters, sort keys, group-by, visible columns |
| `DatabaseFilter` / `DatabaseSortKey` | Query primitives |
| `DatabaseDateParser` | Loose YYYY-MM-DD parsing/formatting |

### Database persistence (MiranNotesApp/Data)

| Type | Role |
|------|------|
| `DatabaseDocument` (actor) | Per-database schema/row/view lifecycle; atomic flush; query engine with filter + sort |
| `DatabaseRepository` (actor) | Facade for database CRUD, registry management, document access, batch flush |
| `PlanningSchemas` | Predefined Tasks and Sessions schemas with default views |
| `PlanningConfigManager` (actor) | Loads/saves `planning-config.json` |

### Planning domain (Features/Planning)

| Type | Role |
|------|------|
| `PlanningModel` (@MainActor) | Central planning state: bootstrap, quick add, toggle complete, backlog, date nav, weekly review, refresh |
| `WeeklyReviewMetrics` | Aggregated stats: sessions planned/completed/missed, tasks total/completed, backlog, per-subject breakdown |
| `DailyTemplateEngine` | Renders daily note content from `{{date}}`, `{{sessions}}`, `{{tasks}}` template variables |

## UI structure

```
AppContentMode switcher (Cmd+1 Notes / Cmd+2 Planning)
├── Notes mode → NavigationSplitView (existing)
└── Planning mode → PlanningRootView
    ├── Sidebar: Dashboard, Calendar, Tasks, Sessions, Settings
    ├── Dashboard: QuickAddBar + TaskRowView + SessionRowView + Backlog
    ├── Calendar: DailyCalendarView / WeeklyCalendarView / MonthlyCalendarView / WeeklyReviewView
    ├── Tasks: DatabaseTableView (full table with inline editing)
    ├── Sessions: DatabaseTableView
    └── Settings: PlanningSettingsView (subjects, colors, export, migration)
```

### Database views

- **DatabaseTableView** — column-header grid with inline cell editing and context menu delete.
- **DatabaseBoardView** — kanban-style grouped columns by a select field.
- **DatabaseViewContainer** — hosts any database in its configured views with a layout switcher.

### Edit sheets

- **TaskEditSheet** — create/edit with type, subject, date, time, duration, priority, project fields.
- **SessionEditSheet** — create/edit with type, subject, topic, session type, date, start time, duration, objective.

## Cross-feature integration

| Feature | Mechanism |
|---------|-----------|
| `/task` slash command | Inserts a callout block with checkbox prefix via `SlashCommandRegistry` |
| `/session` slash command | Inserts a callout block with calendar prefix |
| Note → Task linking | `AppModel.linkActiveNoteToTask(rowID:)` sets the `linkedNote` cell to the current note's UUID |
| Task → Note navigation | `AppModel.openLinkedNote(from:)` reads `linkedNote` cell and opens the note |
| Inline task list | `InlineTaskListView` shows tasks linked to the current note or today's tasks |
| Inline session list | `InlineSessionListView` shows sessions linked to the current note or today's sessions |

## Migration from Zora Planning

`ZoraMigrationEngine` handles one-time import:

1. Parses YAML frontmatter from `.md` files in `Tasks/` and `Sessions/` directories.
2. Inserts rows into the Miran Tasks and Sessions databases.
3. Migrates `zora-config.json` subjects and colors to `planning-config.json`.
4. Returns a `MigrationResult` with counts and any errors.

`ZoraMigrationSheet` provides a UI with directory picker and progress reporting.

## Data export

`PlanningSettingsView` offers CSV export for both Tasks and Sessions databases using the schema column definitions as headers.

## Testing

- `DatabaseRepositoryTests` — 16 tests covering registry lifecycle, row CRUD, filtering, sorting, persistence round-trip, schema operations, view operations, type validation, LinkTarget coding.
- `PlanningModelTests` — 13 tests covering bootstrap idempotency, quick add, toggle complete, backlog detection, date navigation, weekly review metrics, delete, persistence, config.

## Related documents

- [ADR 0004](../adr/0004-vault-level-databases-and-planning.md) — decision record for vault-level databases
- [ADR 0002](../adr/0002-auxiliary-storage-jsonl.md) — historical per-note `_aux/` JSONL layout (withdrawn; see ADR status)
- [Constraints.md](../../Constraints.md) — non-negotiable constraints the planning layer respects

# ADR 0009: Task blocks and Today's Tasks integration

## Status

Accepted (2026-08-20).

## Context

Today's Tasks shipped post-pivot as a standalone per-day checklist (JSON pages under
`.miran/todays-tasks-days/`), disconnected from notes, with navigation restricted to days that
already had tasks. Meanwhile Constraints.md claimed `/task` and `/session` slash commands existed;
neither did, and there was no task block type in the document model. The product decision (Aug 2026)
was to keep and deepen Today's Tasks — explicitly **not** a return of Miran Planning.

## Decision

1. **`BlockType.taskItem` + `Block.isDone: Bool?`** — an additive, tolerant sidecar change (older
   sidecars decode with `isDone == nil`; synthesized Codable omits the key when nil). `isDone` is
   orthogonal to ranges: `SpanAdjuster`/`LinkAdjuster` are untouched. Rules in the engine:
   `changeBlockType` to `taskItem` initializes `isDone = false`, converting away clears it;
   `splitBlock` gives a task's continuation `isDone = false`; the new `EditCommand.setBlockDone`
   only mutates blocks that are actually `taskItem`.
2. **`/task` (alias `/todo`)** joins the built-in slash registry (making the old Constraints claim
   true); `/session` stays nonexistent. Enter on an empty task block demotes it to a paragraph,
   like list items.
3. **Checkbox chrome** draws in `BlockChromeOverlayView`'s left gutter — the overlay's only
   interactive region (`hitTest` returns the view only over checkbox rects). Toggling routes a
   `setBlockDone` batch through the normal command pipeline. Done tasks render with strikethrough +
   secondary color via `EditorVisualStyle`.
4. **Today's Tasks page**: free day navigation via a calendar picker (empty days show an empty
   editable list and are indexed only once they have content), a Today button, and **rollover** —
   explicit button plus an optional automatic mode (Settings) that fires when a new day starts
   empty. Rolled rows record `rolledFromDayKey`; duplicates are avoided by primary-line match.
5. **Note ↔ tasks integration is one-way.** "Add to Today's Tasks" (block context menu) copies the
   block's text into today's list with `sourceNoteID`/`sourceBlockID` back-references; the row's
   chip opens the note and scrolls to the block when it still exists. "Mark Done in Note Too" is an
   explicit per-row action (open pane pipeline when the note is active; load → engine → save
   otherwise). There is **no live sync** between day rows and note blocks — block IDs are advisory
   and text drifts, so silent cross-file mutation would violate the semantic-reconciliation stance.
6. Day pages and the day index stay simple atomic JSON outside the commit-participant set (the
   posture Today's Tasks already had; now documented in ADR 0008's storage-class taxonomy).

## Consequences

- Notes gain real checkable tasks with Markdown export as `- [ ]` / `- [x]`.
- A day row and its origin block can disagree; the UI presents them as copies with a link, not as
  one synchronized item.
- `VaultTodaysTaskRow` gained three optional fields (`rolledFromDayKey`, `sourceNoteID`,
  `sourceBlockID`) with tolerant decode; day files remain schemaVersion 2.

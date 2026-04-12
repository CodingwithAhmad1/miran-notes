# Plan: Wire `UndoInverseSupport` into `AppModel` (memory-saving hybrid undo)

## Goal

Use **inverse `replaceText` chains** for undo where safe, instead of storing a full `NoteDocument` for every checkpoint. Keep **full snapshots** for structural batches, mixed batches, and when inverse computation fails.

## Current state

- [`UndoInverseSupport`](../../Sources/MiranNotesCore/UndoInverseSupport.swift) exposes `inverseCommands(for:documentBefore:)` (single `replaceText` only).
- [`AppModel.apply`](../../Sources/MiranNotesApp/App/AppModel.swift) stores only `[NoteDocument]` in `undoCheckpoints` (full snapshots).
- Coalescing merges rapid `replaceText` into one step by overwriting the last checkpoint.

## Design

### 1) Core: `replaceTextChainUndoCommands`

Add to `UndoInverseSupport`:

```swift
public static func replaceTextChainUndoCommands(
    forward: [EditCommand],
    documentBefore: NoteDocument
) -> (after: NoteDocument, undoCommands: [EditCommand])?
```

- Return `nil` if any command is not `replaceText` or any single-step inverse fails.
- Walk forward with `EditCommandEngine.apply`, building a flat `undoCommands` list by prepending each step’s inverse (so applying `undoCommands` in order to `after` returns `documentBefore`).

### 2) AppModel: `UndoCheckpoint` storage

Replace `private var undoCheckpoints: [NoteDocument]` with something like:

```swift
private enum UndoCheckpoint {
    case full(NoteDocument)
    case replaceTextOnly(forward: [EditCommand], undoCommands: [EditCommand])
}
private var undoCheckpoints: [UndoCheckpoint] = []
```

**Invariants**

- Index `0` is always `.full` (oldest retained state).
- For `i > 0`, `materialize(i)` equals the document after the `i`th recorded step.
- `.replaceTextOnly`: `materialize(i) == fold(EditCommandEngine.apply, forward, materialize(i-1))`.

### 3) Materialization

```swift
private func materializeCheckpoint(at index: Int) -> NoteDocument {
    switch undoCheckpoints[index] {
    case .full(let d): return d
    case .replaceTextOnly(let forward, _):
        var doc = materializeCheckpoint(at: index - 1)
        for c in forward { doc = EditCommandEngine.apply(c, to: doc) }
        return doc
    }
}
```

**Undo** from `top` to `top-1`: if `undoCheckpoints[top]` is `.replaceTextOnly(_, let undo)`, set `activeDocument` by applying `undo` in order to `materialize(top)` — equivalent to `materialize(top-1)`.

**Simpler:** `activeDocument = materializeCheckpoint(at: toIndex)` (works for both kinds).

### 4) Recording a new step

After applying `intercepted` to get `after` from `before`:

1. If `replaceTextChainUndoCommands(forward: intercepted, documentBefore: before) != nil` → append `.replaceTextOnly(forward: intercepted, undoCommands: …)`.
2. Else → append `.full(after)`.

**First step** when empty: `undoCheckpoints = [.full(before), <second>]`.

### 5) Coalescing

When coalescing rapid single-`replaceText` edits:

- If the last checkpoint is `.replaceTextOnly`, **append** the new `intercepted` commands to `forward`, then recompute `(forward, undoCommands)` with `replaceTextChainUndoCommands(forward:accumulated, documentBefore: materializeCheckpoint(at: count-2))`.
- If recomputation fails, fall back to `.full(after)`.

Replace the check `undoCheckpoints.last == before` with:

`materializeCheckpoint(at: undoCheckpoints.count - 1) == before`

(`NoteDocument` is `Equatable`.)

### 6) Memory estimate

Update `undoRetentionMemoryEstimateBytes` to sum per checkpoint:

- `.full(d)`: `d.estimatedUndoMemoryBytes`
- `.replaceTextOnly`: use `materializeCheckpoint(at: i).estimatedUndoMemoryBytes` plus a small fixed overhead for command arrays (optional)

Note: **Actual** heap use drops because fewer full `NoteDocument` copies are stored; the estimate may still reflect logical document sizes when materializing for metrics.

### 7) Tests

- [`UndoInverseSupportTests`](../../Tests/MiranNotesTests/UndoInverseSupportTests.swift): multi-step forward chain round-trip (apply forward, then undo list, equals `documentBefore`).
- [`AppModelUndoMemoryTests`](../../Tests/MiranNotesAppTests/AppModelUndoMemoryTests.swift): keep behavioral tests; optionally assert `undoRetentionMemoryEstimateBytes` is lower for long replaceText-only histories vs previous cap (or add `fullCheckpointCount` test-only accessor).

## Follow-ups (clean, precise)

1. **Redo path:** existing `applyCheckpointUndo` redo registration stays valid if `materializeCheckpoint` is used for both directions.
2. **Interceptor chains:** if interceptors rewrite commands to non-`replaceText`, recording uses `intercepted` — already correct; hybrid only applies when the **post-interceptor** batch is pure `replaceText`.
3. **Documentation:** one paragraph in [`Constraints.md`](../../Constraints.md) undo section: hybrid undo for text deltas, snapshots for structural.

## Risk

- **Coalescing + hybrid:** must recompute undo from the step’s true `documentBefore` at `index-2` materialized — same as today’s implicit `before` for the burst.
- **Deep materialize:** worst-case O(n²) if many `.replaceTextOnly` in a row — mitigated by bounded undo steps (200) and typical short chains.

## Feasibility

High: localized to `AppModel` undo block + `UndoInverseSupport` + tests.

## Status

**Implemented** in-repo: `UndoInverseSupport.replaceTextChainUndoCommands`, `AppModel` `UndoCheckpoint` storage + `materializeCheckpoint`, coalescing hybrid merge, prune rebase to full snapshots, `Constraints.md` undo section updated, `UndoInverseSupportTests.testReplaceTextChainRoundTrip`.

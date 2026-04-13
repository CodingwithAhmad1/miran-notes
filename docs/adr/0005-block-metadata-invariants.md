# ADR 0005: Block metadata invariants

## Status

Accepted (implementation follows this ADR).

## Context

The block-based metadata system stores structural information (blocks, spans, links) in a sidecar `.meta.json` file alongside the plain-text `.txt` body. Multiple subsystems mutate this metadata: the `EditCommandEngine` during editing, `RangeNormalizer` as a safety net and on persistence, and `reconcileBlocksFromText` after full-buffer replacements. Without formally specified invariants, these subsystems have diverged in assumptions — leading to silent data loss (`databaseRowReferences` dropped during normalization), heuristic block recovery, and ordering-dependent zero-length block behavior.

This ADR establishes the canonical contract that all metadata producers and consumers must uphold.

## Invariants

### 1. Block partition rule

`metadata.blocks` must form a gapless, non-overlapping, sorted-by-start partition of the entire UTF-16 text range `[0, text.utf16.count)`.

- Every UTF-16 offset in the document belongs to exactly one block.
- Blocks are sorted by `range.start` in ascending order.
- `blocks[0].range.start == 0` and `blocks.last!.range.end == text.utf16.count`.
- Adjacent blocks satisfy `blocks[i].range.end == blocks[i+1].range.start`.

`NoteIntegrity.check` and `RangeNormalizer.isValid` validate this invariant. `RangeNormalizer.normalize` repairs violations.

### 2. Block identity

Each block has a stable `id` (UUID string). IDs are preserved across incremental edits (`adjustBlocks` never changes IDs) and across full-buffer reconciliation when the block's text content can be matched to an old block. IDs are regenerated only when no content match exists.

Stable IDs enable:
- Undo/redo targeting specific blocks.
- Same-batch `changeBlockType` after a `replaceText` that empties the block.
- External references (e.g. `DatabaseRowReference.blockID`).

### 3. Zero-length block lifecycle

A block may temporarily have `range.length == 0` within a command batch — for example, after a slash-command token is deleted but before a `changeBlockType` converts the empty block.

- `EditCommandEngine.adjustBlocks` preserves zero-length blocks (does not auto-merge).
- `RangeNormalizer.normalize` with `stripZeroLengthBlocks: true` (the default) removes zero-length interior blocks. Persistence and load paths always use `true`.
- Safety-net normalize calls inside `EditCommandEngine` pass `stripZeroLengthBlocks: false` so transient empty blocks survive for same-batch command lookups.
- Zero-length blocks must not survive to disk.

### 4. Span and link containment

Every `Span.range` and `NoteLink.range` must satisfy `range.start >= 0` and `range.end <= text.utf16.count`. Spans and links are not required to be contained within a single block — they may cross block boundaries.

`RangeNormalizer.normalize` clamps and removes empty spans/links. `SpanAdjuster` and `LinkAdjuster` shift ranges on text edits and optionally constrain to block boundaries after splits.

### 5. Metadata completeness

`RangeNormalizer.normalize` must preserve all `NoteMetadata` fields. It achieves this by mutating the input metadata in place (updating only `schemaVersion`, `blocks`, `spans`, and `links`) rather than constructing a new `NoteMetadata` instance.

Adding a new field to `NoteMetadata` must not require updating `normalize`. This prevents the class of bugs where a new field is silently dropped because a constructor call omitted it.

### 6. `databaseRowReferences` lifecycle

`DatabaseRowReference` has no text range — it associates a `(databaseID, rowID)` pair with the note, and optionally a `blockID`. References survive all edits and normalizations.

`blockID` is advisory: it records which block the reference was originally associated with, but may become stale if that block is deleted or merged. Consumers must handle missing or invalid `blockID` gracefully.

## Validation

`NoteIntegrity.check(document:)` validates invariants 1 and 4, returning typed `Issue` values. `RangeNormalizer.isValid` performs the same structural checks as a fast boolean predicate. Both must agree: `NoteIntegrity.check` uses `RangeNormalizer.isValid` as a secondary confirmation.

## Consequences

- All code paths that produce or repair `NoteMetadata` must satisfy these invariants.
- New metadata fields added to `NoteMetadata` are automatically preserved through normalization without code changes.
- The `stripZeroLengthBlocks` parameter makes the transient/persistent distinction explicit at each call site.
- `reconcileBlocksFromText` uses content-based matching for deterministic type recovery after full-buffer replacements.

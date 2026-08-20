---
name: Robustness phased plan
overview: "Four phases with full architectural latitude: repair transparency (NoteLoadResult struct, repairNotice banner), adjustBlocks made exhaustive (deterministic multi-block merge, no normalize in hot path), slash command registry completion, and save-flow + editor architecture (onCommands→NoteDocument sync return, cursorOffset binding, table save cleanup)."
todos:
  - id: p1-repair-advisory
    content: "Phase 1: NoteLoadResult struct; repairNotice in AppModel; wiki-link gap advisory; dismissible banner; tests"
    status: completed
  - id: p2-adjustblocks
    content: "Phase 2: Exhaustive adjustBlocks — deterministic multi-block merge, zero-length pruning, remove normalize from hot path, hard DEBUG assert; tests"
    status: completed
  - id: p3-slash-commands
    content: "Phase 3: Add /list, /divider, /callout to SlashCommandRegistry; tests"
    status: completed
  - id: p4-save-flow
    content: "Phase 4: onCommands→NoteDocument sync return; @Binding cursorOffset on SingleSurfaceNoteEditor; remove direct table save; tests"
    status: completed
isProject: false
---

# Robustness: phased implementation plan

## State after the previous session

The navigation, autosave, rename, and backlink-error fixes from the previous session are already in [`AppModel.swift`](Sources/MiranNotesApp/App/AppModel.swift) and passing all 38 tests. The remaining open items map to the four constraints below.

---

## Phase 1 — Reconciliation advisory (Plain text vs metadata constraint)

### What hurts

`NoteRepository.documentAfterLoadRepair` calls `RangeNormalizer.normalize` up to three times and silently discards all warnings. `MetadataValidationResult.warnings` (strings like `"Found a block gap. Expanded previous block coverage."`) are computed but never surfaced. `NoteIntegrity.logIfInvalid` writes to `os_log` but shows nothing to the user. Constraint says: detect, classify, never silently pick a semantic winner when it matters.

Additionally, ADR 0001 notes that `[[...]]` tokens can outlive `links[]` after an external edit. There is no load-time check for this mismatch.

### Changes

**`NoteRepository.swift`**
- Change `documentAfterLoadRepair(text:metadata:)` signature to `-> (NoteDocument, wasRepaired: Bool, warnings: [String])`. Collect all warnings from the three normalize passes and the final fallback path.
- In `loadNote(baseName:)`, propagate the new return values. Return the combined `(NoteDocument, wasRepaired: Bool, warnings: [String])` from the actor method (rename to `loadNote(baseName:)` returning a struct or tuple, keeping backwards compatibility with a private helper).

**`AppModel.swift`**
- Add `@Published var repairNotice: String?` (replaces `nil` when note loaded cleanly).
- In `loadSelectedNote()`, after `repository.loadNote`, if `wasRepaired || !warnings.isEmpty`, build a human-readable string (e.g. `"Block structure was repaired on load. Metadata may not match all original block types."`) and assign to `repairNotice`. Clear `repairNotice` when the note is clean or when the user switches notes.
- Also detect the wiki-link gap: after loading, if `document.text` contains `[[` but `document.metadata.links` is empty, append `"Note contains [[link]] syntax with no recorded link metadata."` to the notice.

**`MiranNotesApp.swift`**
- In `EditorRootView`, add a dismissible `HStack` banner below the toolbar (or above the editor) that shows when `model.repairNotice != nil`, with a "Dismiss" button that sets `model.repairNotice = nil`. Non-blocking — the editor is always open.

**Tests** — new `AppModelRepairNoticeTests.swift`:
- Load a note whose `.meta.json` has blocks that don't cover the text → `repairNotice != nil`.
- Load a note with valid metadata → `repairNotice == nil`.
- Load a note with `[[link]]` text but empty `links[]` → `repairNotice` contains the wiki-link advisory.

---

## Phase 2 — `adjustBlocks` made exhaustive (Block boundaries constraint)

### What hurts

`adjustBlocks` has two silent `RangeNormalizer.normalize` fallback paths. `normalize` calls `closeBlockGaps`, which fills gaps by **expanding the previous block's range** — this silently reassigns text to the wrong block type (e.g. a paragraph's range covers what was a heading's text). This is a "silent semantic winner" violation. The fallback should never fire during normal editing.

### Changes

**`EditCommandEngine.swift`** — rewrite `adjustBlocks` to be exhaustive:

1. **No affected block found** (edit offset outside all blocks): hard `assertionFailure` in DEBUG, `os_log` error in release, return `normalize` only as last resort. This case should not occur during normal editing.

2. **Single-block edit (normal case)**: existing delta-adjust logic, plus — if the adjusted block becomes zero-length, remove it and merge its coverage into the predecessor (or successor if no predecessor). Never calls `normalize`.

3. **Multi-block replacement** (currently falls back to `normalize`): deterministically collapse all blocks whose ranges intersect `replacedRange` into the **first** such block (preserving its id and type), set its new length to `firstBlock.range.start + replacementUTF16Length - firstBlock.range.start` = `replacementUTF16Length` offset from `firstBlock.range.start`, then shift all subsequent blocks by `delta`. No `normalize` call needed.

4. Remove the `isValid` re-check + `normalize` call from `applyTextReplacement` (lines 78–81). With exhaustive `adjustBlocks`, it should never be needed; the `#if DEBUG` assert at the end of `EditCommandEngine.apply` catches any remaining cases.

**`VaultLogging.swift`**: Add `Logger.editEngine` for the no-affected-block warning path.

**Tests** — extend `SpanAndBlockAdjustmentTests.swift`:
- Single-block deletion to zero-length: block count decreases, valid partition, `normalize` not invoked.
- Multi-block deletion: blocks collapse into one, valid partition, first block's type preserved.
- Multi-block replacement with non-empty replacement: single block remains with correct length.

---

## Phase 3 — Slash command registry completion (Slash commands constraint)

### What hurts

[`SlashCommandRegistry.swift`](Sources/MiranNotesApp/Features/Editor/SlashCommandRegistry.swift) only handles `/h1`–`/h3`, `/p`, `/code`. The block model has `listItem`, `divider`, and `callout` types with no corresponding slash commands. The `/list`, `/divider`, `/callout` tokens do nothing today.

### Changes

**`SlashCommandRegistry.swift`**:
- Add `SlashListItem` private enum: matches `"list"`, emits `.replaceText(tokenRange, "") + .changeBlockType(blockID, .listItem, nil)`.
- Add `SlashDivider`: matches `"divider"`, same pattern.
- Add `SlashCallout`: matches `"callout"`, same pattern.
- Register all three in `editCommands(for:blockID:)` after the existing entries.

**Tests** — extend `SlashCommandDetectorTests.swift` (or new file):
- `/list ` at line start commits and produces `listItem` block type.
- `/divider ` produces `divider` block type.
- `/callout ` produces `callout` block type.
- Partial `/lis` does not commit until Space/Return (existing behavior, verify it still holds for new tokens).

---

## Phase 4 — Editor architecture: sync `apply`, cursor binding, save cleanup

### What hurts

**Styling lag / two-representation desync**: `onCommands: ([EditCommand]) -> Void` is one-way. The coordinator fires commands, `AppModel.apply()` computes the new `NoteDocument` synchronously, but `parent.document` in the coordinator stays stale until the next SwiftUI render cycle. `refreshVisualChrome` therefore runs with old metadata on new text — bold/italic/link colouring briefly disagrees with the model.

**`pendingCommands` complexity**: `applyPendingCommandsIfConsistent` exists purely to bridge the one-way gap for structural commands (newline split, merge). With a sync return this disappears.

**`insertWikiLink` cursor**: `AppModel` always inserts at end of document. The coordinator knows the cursor (`textView.selectedRange()`), the model does not.

### Changes

**`SingleSurfaceNoteEditor.swift`**:
- Change `var onCommands: ([EditCommand]) -> Void` → `var onCommands: ([EditCommand]) -> NoteDocument`.
- Add `@Binding var cursorOffset: Int` — coordinator writes this on `textViewDidChangeSelection`.
- In coordinator: after every `parent.onCommands(...)` call, immediately call `refreshVisualChrome(textView:document:returnedDoc)` with the returned document. No lag.
- Remove `pendingCommands`, `applyPendingCommandsIfConsistent`, and `pendingCommands = structural` from `textView(_:shouldChangeTextIn:...)`. The coordinator now gets the new doc back synchronously and can apply the minimal diff itself if needed.

**`BlockListView.swift` / `TextKit2BlockEditor.swift`**:
- Same `onCommand: (EditCommand) -> Void` → `(EditCommand) -> NoteDocument` change for consistency.

**`AppModel.swift`**:
- `apply(_ commands: [EditCommand], recordUndo: Bool) -> NoteDocument` — return `doc` at end.
- `apply(_ command: EditCommand) -> NoteDocument` — convenience wrapper returns result.
- Add `@Published var editorCursorOffset: Int = 0`.
- `insertWikiLink(to:displayText:)` reads `editorCursorOffset` instead of always using text end.

**`MiranNotesApp.swift`**: Update `onCommands: { model.apply($0) }` closure signature to `{ model.apply($0) }` — same call, just now returns `NoteDocument` (closure return type inferred).

**Tests**:
- `insertWikiLink` with `editorCursorOffset = 3` inserts at position 3, not end.
- Styling coherence: after `apply(.toggleSpanStyle(...))`, the returned document's spans match what would be styled (unit test of the return value, no NSTextView needed).

---

## Files touched

- [`Sources/MiranNotesApp/Data/NoteRepository.swift`](Sources/MiranNotesApp/Data/NoteRepository.swift) — Phase 1
- [`Sources/MiranNotesApp/App/AppModel.swift`](Sources/MiranNotesApp/App/AppModel.swift) — Phases 1, 4
- [`Sources/MiranNotesApp/App/MiranNotesApp.swift`](Sources/MiranNotesApp/App/MiranNotesApp.swift) — Phases 1 (banner), 4 (closure type)
- [`Sources/MiranNotesCore/EditCommandEngine.swift`](Sources/MiranNotesCore/EditCommandEngine.swift) — Phase 2
- [`Sources/MiranNotesApp/Data/VaultLogging.swift`](Sources/MiranNotesApp/Data/VaultLogging.swift) — Phase 2
- [`Sources/MiranNotesApp/Features/Editor/SlashCommandRegistry.swift`](Sources/MiranNotesApp/Features/Editor/SlashCommandRegistry.swift) — Phase 3
- [`Sources/MiranNotesApp/Features/Editor/SingleSurfaceNoteEditor.swift`](Sources/MiranNotesApp/Features/Editor/SingleSurfaceNoteEditor.swift) — Phase 4
- [`Sources/MiranNotesApp/Features/Editor/BlockListView.swift`](Sources/MiranNotesApp/Features/Editor/BlockListView.swift) — Phase 4
- [`Sources/MiranNotesApp/Features/Editor/TextKit2BlockEditor.swift`](Sources/MiranNotesApp/Features/Editor/TextKit2BlockEditor.swift) — Phase 4
- `Tests/MiranNotesAppTests/AppModelRepairNoticeTests.swift` (new) — Phase 1
- `Tests/MiranNotesTests/SpanAndBlockAdjustmentTests.swift` (extend) — Phase 2
- `Tests/MiranNotesAppTests/SlashCommandDetectorTests.swift` (extend) — Phase 3
- `Tests/MiranNotesAppTests/AppModelTableTests.swift` (new) — Phase 4

## What this plan does NOT change

- Undo snapshot memory model (acknowledged tradeoff — unbounded undo with bounded memory is impossible).
- TOCTOU in external-change detection (acknowledged limit — no distributed lock).
- Slash command scope (line-start only, commit on Space/Return — confirmed correct).
- Auto-rebuilding `[[...]]` link targets from syntax without metadata (requires name-based vault lookup; future tool per ADR 0001).

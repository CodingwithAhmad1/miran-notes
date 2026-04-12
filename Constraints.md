# Constraints

This document records **non-negotiable product and engineering constraints** for Miran Notes, including known limits that no implementation can fully "solve."

## Product scope

- **Local-first, single-writer editing** is the baseline. Real-time multi-user collaboration is **not** a current goal and should not drive core architecture.
- **Human-readable storage** (`note.txt` + sidecar JSON) remains the default mental model for notes.

## Semantic reconciliation

When plain text and metadata disagree (for example after an external edit to `note.txt`, a tool bug, or a partial write), **there is no general algorithm that recovers user intent** from bytes alone. Multiple valid block partitions can match the same string.

**Constraint:** The app must **detect** inconsistency, **classify** it (safe vs ambiguous), and **never silently pick a semantic winner** when ambiguity matters. Acceptable behavior includes: blocking save, offering a **repair preview**, or requiring explicit user confirmation before rewriting sidecar metadata.

**Load-time advisory:** `NoteRepository.loadNote` now returns `NoteLoadResult` which carries any `repairWarnings` collected during the three `RangeNormalizer.normalize` passes. `AppModel` surfaces these via `@Published var repairNotice: String?`, displayed as a dismissible banner. This satisfies the "detect and classify" requirement without blocking the editor. A missing `[[...]]` link-metadata gap is detected separately and included in the same notice.

This limitation is **fundamental**; later discussion may refine UX, not "solve" intent inference.

## Storage format evolution

Plain `note.txt` cannot losslessly encode every conceivable future feature in isolation. Structured or heavy features may require **sidecar fields**, **auxiliary files**, or **schema migrations** with explicit versioning.

**Constraint:** Each feature must state what is stored where, and how round-trip and migration work.

## Block chrome and layout

Aligning visual block affordances (callouts, gutters, handles) with TextKit layout is **ongoing work**: resize, fonts, RTL, and layout invalidation all require disciplined invalidation. Cost can be **managed** (e.g. a single chrome controller), not reduced to zero.

## Editor representation

The canonical note model and `NSTextView` are two representations of text. Engineering discipline and tests keep them aligned; **formal proof** of impossible desync is not assumed.

## Rich text and slash commands

- **Dual representation:** Canonical plain text plus sidecar metadata (blocks, spans, links) is the source of truth. `NSTextView` attributes are **derived**: an `EditorVisualStyle` pass applies block fonts, span styles (bold / italic / code), and link coloring whenever the model updates from **any** source (typing, undo, structural commands, external reload). `onCommands` returns `NoteDocument` synchronously so the coordinator calls `refreshVisualChrome` with the updated document immediately — no lag between command dispatch and visual update.
- **Cursor position:** `SingleSurfaceNoteEditor` exposes `@Binding var cursorOffset: Int`; the coordinator writes it on every `textViewDidChangeSelection`. `AppModel.editorCursorOffset` tracks the live caret position so cursor-aware operations (e.g. wiki-link insertion via the toolbar) land at the cursor rather than end-of-document.
- **IME / marked text:** While the text view has **marked text** (composition), the editor does not run slash detection and formatting shortcuts (`toggleBold:`, etc.) do not apply, so composition is not torn down mid-sequence.
- **Slash discovery + execution (non-regression contract):**
  - Discovery is **line-start only** (after a newline or at document start, with `/` as the first character on the line).
  - Typing `/` opens a command menu anchored near the caret; typing more characters filters results live.
  - Keyboard contract is fixed for consistency: Up/Down moves highlight, Enter/Tab executes highlighted command, Esc closes menu without mutation.
  - Unknown tokens (for example `/doesntwork`) are **not errors** and are **not auto-transformed**: text remains plain, menu shows `No commands found`.
  - Enter without a selectable command follows normal editor behavior (no hidden slash fallback rewrite).
  - Registered commands currently include `/h1`–`/h3`, `/p`, `/code`, `/list` (alias `/bullet`), `/divider`, `/callout`.
  - **Registry order** defines precedence if two patterns could match.
- **External editors:** A literal `/h1` in `note.txt` stays plain text until the user edits in-app in a way that triggers detection (or a future explicit conversion). This aligns with **Semantic reconciliation**: no silent semantic rewrite of metadata without an explicit editing action the user can reason about.
- **Notion parity limits:** Slash commands plus heading fonts improve the experience but do **not** deliver full per-block chrome (gutters, drag handles, block menus) in a single `NSTextView`; see **Block chrome and layout** above.

## View sync and text pipeline (Phases 1–2)

- **Incremental model → view updates:** When the canonical string and `NSTextView` differ by a **single UTF-16 edit**, the editor applies `NSTextStorage.replaceCharacters` for that edit instead of assigning `string` wholesale, reducing churn and selection jumps ([`TextEditDiff`](Sources/MiranNotesApp/Features/Editor/TextEditDiff.swift)).
- **IME / marked text:** While `NSTextView` has **marked text** (for example input methods), `updateNSView` does **not** overwrite the buffer from the model, so composition is not torn down mid-sequence.
- **External full replace:** When the model must replace the whole string (multi-edit or no single replacement), the previous **selection is clamped** to the new length after the assignment.
- **Single pipeline:** Plain typing flows through `NSTextStorageDelegate.textStorage(_:didProcessEditing:…)` → `EditCommand` → `AppModel` ([`SingleSurfaceNoteEditor`](Sources/MiranNotesApp/Features/Editor/SingleSurfaceNoteEditor.swift)). The per-block [`TextKit2BlockEditor`](Sources/MiranNotesApp/Features/Editor/TextKit2BlockEditor.swift) uses the same delegate path instead of `textDidChange`.

## Undo and history (Phase 3)

The app uses **document-level undo** via the window `UndoManager`: each user editing batch is recorded as a **snapshot** of `NoteDocument` before and after `EditCommand` application. Structural batches (for example newline split or merge) are **one undo step** because they are applied in a single `apply([EditCommand])` call. `NSTextView.allowsUndo` is **off** so the text view does not maintain a second undo stack alongside the document snapshots.

**Undo menu labels:** A newline split (`replaceText` inserting `"\n"` + `splitBlock`) and a merge-at-start-of-block batch (`mergeWithPrevious` + `replaceText`) register under **Split Block** and **Merge Blocks** respectively when those patterns match. A slash batch (`replaceText` deleting the token + `changeBlockType`) registers as **Slash Command**.

**Highlighted limitations (must stay explicit in product and code):**

1. **Memory** — Snapshot undo stores full document state per undo step. Large notes and deep undo stacks increase memory use. **Unbounded** undo with **bounded** memory is impossible; the platform undo stack already implies practical limits.

2. **Undo vs disk** — Autosave writes the current document to files on a timer. Undo/redo updates `activeDocument` and **schedules autosave** like ordinary edits, so the vault converges to the undone state after the debounce window. The on-disk copy may still briefly lag the buffer. After an **external** file change is loaded, the undo stack is **cleared** so redo/undo does not refer to a replaced document.

3. **Stack invalidation** — Undo is cleared when switching notes, creating a new note, or reloading from disk after an external change. This avoids applying undo to the wrong note or a stale revision.

4. **Inverse commands vs snapshots** — The implementation uses **snapshots**, not mathematical inverse `EditCommand`s. That trades memory for correctness and simplicity; optimizing later with inverse ops would be an optional refinement.

## Integrity and automated tests (Phase 4)

- **`NoteIntegrity`** ([`Sources/MiranNotesCore/NoteIntegrity.swift`](Sources/MiranNotesCore/NoteIntegrity.swift)) is the single validation entry point: it reports whether block ranges form an **exact UTF-16 partition** of the text and whether spans sit in bounds.
- **Load and save** paths call **`NoteIntegrity.logIfInvalid`** so invalid states are visible in the unified logging system without crashing in release ([`NoteRepository`](Sources/MiranNotesApp/Data/NoteRepository.swift)).
- **`adjustBlocks` is now exhaustive** for the common cases: single-block edits (delta-adjust + zero-length merge), multi-block replacements (deterministic collapse into first block preserving its id and type), and out-of-bounds edits (logged `assertionFailure`). `RangeNormalizer.normalize` fires only as a safety-net fallback and logs to the `EditEngine` category when it does.
- **Regression tests** live under [`Tests/MiranNotesTests/`](Tests/MiranNotesTests/) (`swift test`). They include deterministic **random `replaceText` sequences**, [`SpanAndBlockAdjustmentTests`](Tests/MiranNotesTests/SpanAndBlockAdjustmentTests.swift) for `SpanAdjuster` and `EditCommandEngine.adjustBlocks`, and span/block scenarios.
- **Safety net:** if incremental block adjustment after a replace ever leaves metadata invalid (logged under `app.miran.notes/EditEngine`), `EditCommandEngine` applies `RangeNormalizer.normalize` for that step so the in-memory document does not stay broken. Silent destructive repair of **on-disk** files is still governed by the semantic reconciliation rules above.

## External file changes and conflicts (Phase 5)

- The vault directory is observed with an **event-only** descriptor and `DispatchSource` (not polling). Events are **debounced** so bursts of writes coalesce.
- While an **autosave** is in flight, filesystem notifications are **ignored** to avoid false conflicts from our own writes.
- **Dirty** means the buffer differs from the last snapshot known to match disk (`lastPersistedDocument` after load or successful save).
- If the buffer is **clean** and on-disk content differs → the app **reloads silently** (undo cleared for that note, same as after external change in earlier builds).
- If the buffer is **dirty** and the loaded on-disk document differs from the buffer → the app shows a **conflict** alert: **Reload from disk** (discard local edits) or **Keep local edits** (dismiss; the next save may overwrite external changes; the acknowledged file timestamp avoids repeating the same alert until the file changes again).
- **Limitation (TOCTOU):** A notification is not a guarantee that the file we read is bitwise-identical to the version that triggered the event; another writer could change the file again before we read. The app compares **loaded** `NoteDocument` values to the buffer, not a perfect distributed lock.

## Future model and sync hooks (Phase 6)

Types in [`Sources/MiranNotesCore/ExtensionPoints.swift`](Sources/MiranNotesCore/ExtensionPoints.swift) document **intentional extension points** only: rich inline canonical snapshots, tree-shaped blocks vs today's flat `[Block]` list, structured artifacts (tables / DB-like blobs) likely needing auxiliary storage, and a placeholder for a future sync transport. They are **not** wired into editing or persistence; they exist so features can name shared concepts without ad-hoc one-off types.

## Vault tooling and observability

- **Link graph rebuild:** `NoteRepository.rebuildLinkGraphFull()` performs a full vault scan; success and note counts are logged via `Logger` (`Vault` category, subsystem `app.miran.notes`). Use sparingly on cold start or after bulk external edits; normal editing updates the graph incrementally on save.
- **`EditEngine` category** (`app.miran.notes/EditEngine`): logged when the `adjustBlocks` normalize fallback fires. Useful for measuring fallback frequency in Console during development.

## Related planning

- **Repository index:** [docs/README.md](docs/README.md) links constraints, ADRs, and in-repo plans.
- **In-repo plans and roadmaps:** [docs/plans/](docs/plans/) — durable planning notes that ship with the repo. IDE-only plans (for example under `.cursor/plans/` on a developer machine) should be copied or summarized there when they matter to contributors.

This file names constraints; roadmaps and feature plans live under `docs/plans/` and in linked ADRs.

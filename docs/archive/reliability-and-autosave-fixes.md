---
name: Reliability and autosave fixes
overview: Fix high-impact data integrity bugs around debounced autosave and note navigation (including create/rename), and improve observability for backlink index failures—without changing product scope (no vault picker).
todos:
  - id: flush-helper
    content: Add navigationGeneration + flushCurrentNoteToDiskIfDirty(); cancel saveTask; guard scheduleAutosave completion
    status: completed
  - id: wire-navigation
    content: Await flush before changeSelection and createNote; save before renameActiveNote
    status: completed
  - id: backlinks-error
    content: Surface refreshBacklinks failures (lastError or dedicated field)
    status: completed
  - id: tests
    content: "Add AppModel tests: switch/new/rename preserve unsaved edits; state coherence after rapid switch"
    status: completed
isProject: false
---

# Reliability fixes: autosave, navigation, rename

## Problems identified (code-backed)

1. **Debounced save can finish after the user switches notes**  
   [`scheduleAutosave`](Sources/MiranNotesApp/App/AppModel.swift) captures `note` and runs after `Task.sleep`. When [`changeSelection`](Sources/MiranNotesApp/App/AppModel.swift) updates `selectedBaseName` and loads another note, a **still-running or late-completing** task can still execute `lastPersistedDocument = note` for the **previous** document while `activeDocument` is already the **new** note—breaking dirty detection and external-reload logic (see [`processExternalDiskActivity`](Sources/MiranNotesApp/App/AppModel.swift)).

2. **Unsaved edits are dropped on “New Note”**  
   [`createNote`](Sources/MiranNotesApp/App/AppModel.swift) replaces `selectedBaseName` / `activeDocument` without flushing the prior note. Any edits not yet written (debounce window) are **lost**.

3. **Rename ignores in-memory edits**  
   [`NoteRepository.renameNote`](Sources/MiranNotesApp/Data/NoteRepository.swift) loads with `loadNote(baseName:)` from disk (line ~243). [`renameActiveNote`](Sources/MiranNotesApp/App/AppModel.swift) never saves `activeDocument` first, so **buffer changes that are not on disk are silently discarded** when renaming.

4. **Backlink refresh failures are silent**  
   [`refreshBacklinks`](Sources/MiranNotesApp/App/AppModel.swift) catches errors and sets `backlinks = []` with no user-visible signal—hard to distinguish “no links” from “index failed”.

**Intentionally out of scope** (per your choice): vault location / folder picker; large refactors (inverse undo, block chrome). **Optional later:** [`loadVault`](Sources/MiranNotesApp/App/AppModel.swift) always calls [`rebuildLinkGraphFull`](Sources/MiranNotesApp/Data/NoteRepository.swift)—fine for small vaults but can be slow at scale; can be optimized in a separate pass.

## Implementation approach

### A. Navigation generation token (or equivalent)

- Add a monotonically increasing `navigationGeneration` (or `saveSessionID`) on `AppModel`, incremented **whenever** the “current note” identity changes: before `changeSelection` applies a new `selectedBaseName`, and at the start of `createNote` before replacing selection (same for any other path that swaps the active note).
- In `scheduleAutosave`, capture `let gen = navigationGeneration` when creating the `Task`. After the sleep, **before** save and before mutating `lastPersistedDocument` / `lastKnownDiskDate`, require `gen == navigationGeneration` (and optionally `selectedBaseName == expectedBaseName` captured at schedule time). If mismatch, **return without** applying persistence side effects.

This makes late completions harmless for state; **data safety** still requires flushing below.

### B. Flush current note before leaving it

Introduce a single `@MainActor` helper, e.g. `flushCurrentNoteToDiskIfDirty()`, that:

1. Cancels `saveTask` and nils it (or awaits completion if you choose a stricter pattern—see testing).
2. If `selectedBaseName` and `activeDocument` are non-nil and `activeDocument != lastPersistedDocument`, calls `try await repository.save(activeDocument!, asBaseName:)` and then updates `lastPersistedDocument` and `lastKnownDiskDate` on success (matching existing success path in `scheduleAutosave`).
3. On failure, sets `lastError` (same as autosave).

Call this **before**:

- Updating `selectedBaseName` in `changeSelection` (refactor to `Task { await ... }` or make the flush awaitable from the main actor).
- Creating a new note in `createNote` (before `repository.createNote` or immediately after, but **before** switching selection—actually flush **old** note while old selection still holds).

### C. Rename: save buffer first

In `renameActiveNote`, **await `flushCurrentNoteToDiskIfDirty()`** (or explicit save) **before** `repository.renameNote`. That aligns disk with the buffer so repository’s `loadNote` matches what the user sees.

### D. Backlink errors

- In `refreshBacklinks`, on catch: set `lastError` to a short message (e.g. “Could not refresh backlinks: …”) **or** add a dedicated optional `@Published var backlinkIndexError: String?` if you want to avoid clobbering other errors—minimal change is reusing `lastError` with a clear prefix.

### E. Tests ([`Tests/MiranNotesAppTests`](Tests/MiranNotesAppTests))

Add focused tests (mirroring style of [`AppModelExternalEditTests`](Tests/MiranNotesAppTests/AppModelExternalEditTests.swift)):

- **Switch note with pending debounce**: edit note A, switch to B **without** waiting 400ms; read A’s `.txt` from disk and assert it contains the edit.
- **New note with unsaved prior**: same pattern—edit A, tap New Note; assert A persisted.
- **Rename with unsaved edits**: edit buffer, rename; load file under new base name and assert edited text.
- **Generation guard** (optional but valuable): simulate a delayed completion (harder)—or assert `lastPersistedDocument == activeDocument` after rapid switch + small delay if you expose test hooks / use short sleep in test.

Use a temp vault URL and `NoteRepository` like existing tests.

## Files to touch

- Primary: [`Sources/MiranNotesApp/App/AppModel.swift`](Sources/MiranNotesApp/App/AppModel.swift) (flush helper, generation token, `changeSelection`, `createNote`, `renameActiveNote`, `scheduleAutosave` guard, `refreshBacklinks` error surface).
- Tests: new file or extend [`Tests/MiranNotesAppTests`](Tests/MiranNotesAppTests) with navigation/rename cases.

## Risk notes

- **Flush on every note switch** increases synchronous I/O; acceptable for MVP and matches user expectation that switching notes does not lose work.
- **Actor `NoteRepository`**: keep `await repository.save` patterns consistent with existing `scheduleAutosave`.

# ADR 0008: Trash and UI-state stores under `.miran/`

## Status

Accepted (2026-08-20).

## Context

The two-phase `VaultCommitCoordinator` with its six participants (note files + five indexes) is the
backbone of vault reliability, and Constraints.md keeps that participant set closed. Two new kinds of
per-vault data arrived in Aug 2026 that do not warrant that machinery:

1. **Presentation state** — pinned notes, recents, Finder-style icon-browser positions, per-folder
   icons/list view modes. Losing any of it is cosmetic.
2. **Trash** — deleted notes the user may want back. Loss matters, but its write pattern (copy files
   aside, then delete) has a naturally safe ordering that doesn't need journaled commits.

## Decision

1. **`VaultUIStateStore`** owns `.miran/ui-state/` (`pins.json`, `recents.json`,
   `folder-view-modes.json`, `icon-layout/<folderID>.json`). Atomic single-file writes; tolerant
   decode (a corrupt file reads as absent, never as a user-facing error); versioned
   `{schemaVersion, …}` envelopes. **Not** commit participants.
2. The FSEvents watcher (`VaultDirectoryWatcher`) drops event batches composed entirely of
   `.miran/ui-state` paths, so presentation writes (recents update on every note open) never trigger
   the external-disk reconcile pipeline.
3. **Trash** lives at `.miran/trash/<noteID>/` holding `body.<ext>`, `meta.json`, the `_aux`
   directory when present, and `trash-record.json` (original title/path/folder/extension +
   deletion date, ISO-8601). `NoteRepository.trashNote` copies files there **first**, then runs the
   exact index commit `deleteNote` uses; a crash between the phases leaves at most a harmless
   duplicate copy in trash. User-facing delete goes through trash; permanent delete and Empty Trash
   exist only in the Trash sheet.
4. **Restore** (`restoreTrashedNote`) preserves the original `noteID` and re-enters the vault through
   the normal `save(asRelativePath:folderID:bodyFileExtension:)` commit path. Destination:
   original folder if it still accepts notes → vault root if it does → first repository folder →
   a newly created "Recovered" repository folder. Incoming link-graph edges to the restored note
   rebuild as the linking notes re-save (documented, not silently reconstructed).

## Consequences

- The commit/recovery path stays exactly as audited; new storage can't destabilize it.
- Icon positions and pins do not sync between two app instances sharing a vault until relaunch —
  accepted for presentation state.
- Trash grows until emptied; there is no automatic expiry (personal-tool scale).

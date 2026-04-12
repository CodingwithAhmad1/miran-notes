# Architectural refinements (implementation notes)

This document tracks major structural work aligned with the long-term plan:

## Editor sync boundary

- [`EditorSyncController`](../../Sources/MiranNotesApp/Features/Editor/EditorSyncController.swift) is the **only** supported path for syncing canonical `NoteDocument.text` to `NSTextView` (except IME composition).
- SHA-256 **fingerprints** detect drift between model and view (DEBUG sampling by default).
- [`SingleSurfaceNoteEditor`](../../Sources/MiranNotesApp/Features/Editor/SingleSurfaceNoteEditor.swift) routes `applyDocumentText` and post-command sync through this controller.

## Extension registry

- [`ExtensionRegistry`](../../Sources/MiranNotesCore/ExtensionRegistry.swift) is a **synchronous**, thread-safe registration API (not an actor) so `AppModel.apply` can call it on the main actor without `await`.
- Pipeline order: **registry interceptors** (sorted by id) → **closure interceptors** (registration order) → `EditCommandEngine`.
- [`CommandContext.selectionRange`](../../Sources/MiranNotesCore/ExtensionRegistry.swift) is filled from `AppModel.editorTextSelection`.

## Vault indexes

- [`VaultIndexSubsystem`](../../Sources/MiranNotesApp/Data/VaultIndexSubsystem.swift) centralizes loading of link graph, path index, folder catalog, and relationship index JSON. `NoteRepository` delegates to it (a lighter-weight split than separate index/file **actors**, which can be introduced later if isolation testing demands it).

## Undo (hybrid roadmap)

- [`UndoInverseSupport`](../../Sources/MiranNotesCore/UndoInverseSupport.swift) computes inverse `replaceText` batches for hybrid undo; full `AppModel` integration can build on this without changing on-disk formats.

## External edits

- [`ActiveNoteFilePresenter`](../../Sources/MiranNotesApp/Data/ActiveNoteFilePresenter.swift) registers an `NSFilePresenter` for the active note’s `.txt` in addition to the subtree watcher. When the presenter fires, `AppModel` compares the on-disk `.txt` SHA256 to the last known body fingerprint; if they match, reconciliation is skipped (same body bytes as after load/save). The vault-wide watcher path is unchanged.
- Compare UI uses `ExternalTextComparePayload` and plain-text side-by-side view.

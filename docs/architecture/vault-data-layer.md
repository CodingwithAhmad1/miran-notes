# Vault data layer

This note summarizes how on-disk vault state, the repository, and `AppModel` fit together. It complements [architectural-refinements.md](architectural-refinements.md) and [Constraints.md](../../Constraints.md).

## `NoteRepository` (actor)

- **Single actor** today: listing, load/save, indexes, manifest, and commit coordination run through one `NoteRepository` instance per vault. A future split into dedicated actors (`VaultIndexActor`, `NoteFileActor`, etc.) is described in the refinements doc; behavior contracts below stay the same.
- **Per-note files:** `{relativePath}.txt` (canonical body bytes) and `{relativePath}.meta.json` (structured metadata). Paths are validated with `VaultPath` helpers.
- **Body fingerprint:** `noteTextFileSHA256(relativePath:)` returns a hex SHA256 of the raw `.txt` file bytes. It does not parse or repair; it is suitable for detecting body-only drift and for TOCTOU checks before loading external edits.
- **Revision token:** `noteRevisionToken` combines text and metadata for a coarser “whole note file set” identity (see repository implementation). Use tokens for fast “anything changed?” checks; use the text SHA256 when the concern is specifically the body file.

## `AppModel` and disk

- After load, successful save/autosave, and when resolving “keep local” after a conflict, `AppModel` refreshes **modified date**, **revision token**, and **text SHA256** together via `refreshOnDiskFingerprints(for:)`.
- When reconciling external changes, if a full load is required, the model performs **two consecutive** `noteTextFileSHA256` reads; a mismatch logs `VaultTelemetry.logToctouTextHashDrift()` and still proceeds to `loadNote`, which remains the authority for semantic comparison to the buffer.

## Telemetry

- Vault-scoped logging uses `Logger` (`Vault` category) and `VaultTelemetry` helpers for conflicts, autosave latency, manifest reconcile, repair warnings, and TOCTOU drift.

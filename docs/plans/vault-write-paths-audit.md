# Vault write paths audit (Phase 1 — Part 5)

Internal inventory of every persistence touchpoint for `note.txt`, sidecars, vault indexes, and related files. Categories match the Part 5 spec.

| Artifact | Write path (API / location) | Category |
|----------|----------------------------|----------|
| `note.txt` | `NoteRepository.save`, `moveNote`, `renameNote` (cross-path) via `NoteFilesCommitParticipant` → `VaultCommitCoordinator` | **Already atomic** (two-phase, vault-local staging + journal) |
| `note.meta.json` | Same as above | **Already atomic** |
| `manifest.json` | `VaultCommitCoordinator` (`ManifestCommitParticipant`); `reconcileManifest()` / note saves / index commits when `VaultManifest.isDirty` or schema bump; **`listNotes()` does not write** | **Already atomic** |
| `link-graph.json` | Coordinator (`LinkGraphCommitParticipant`); `saveLinkGraph` / `rebuildLinkGraphFull` / `updateLinkGraph` route through `commitIndexOnly` | **Already atomic** |
| `relationship-index.json` | Coordinator (`RelationshipIndexCommitParticipant`) | **Already atomic** |
| `folder-catalog.json` | Coordinator (`FolderCatalogCommitParticipant`) | **Already atomic** |
| `path-index.json` | Coordinator (`PathIndexCommitParticipant`) | **Already atomic** |
| `_aux/{noteID}/` tables (`*.jsonl`, schema JSON) | `TableDocument` private `atomicWrite` (tmp + `replaceItemAt`) | **Single-file by design** — not bundled in multi-file note/index commits; each table file is atomically replaced |
| `.miran/external-bookmarks.json` | `ExternalBookmarkStore.saveAll` — `Data.write(..., .atomic)` | **Single-file by design** — atomic single-file write; not part of the note/index commit group |
| `.miran/pending-commits/*` | Staging directories for in-flight `VaultCommitCoordinator` runs; removed after success or discarded on incomplete prepare | **Implementation detail** — not user data; used for crash recovery |

## Notes

- **Bypass removal:** Earlier builds used `NoteRepository.atomicWrite` directly for `saveManifest`, `saveLinkGraph`, and title-only `renameNote`. Those paths now go through `commitIndexOnly` / `executeNoteCommit` so vault-level state updates stay on the same two-phase + recovery model as normal saves.
- **Cross-volume:** Staging lives under `vault/.miran/pending-commits/` so temp files and final vault files are on the same volume for reliable rename/replace semantics.

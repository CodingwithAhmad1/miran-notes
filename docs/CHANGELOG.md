# Changelog

Versions in this file are **documentation milestones** for Miran Notes. They do not necessarily match an app marketing or bundle version until one is defined elsewhere.

## 2.0 — Knowledge layer, daily-use overhaul (Aug 2026)

One comprehensive pass (see the ADRs referenced per item) turned the built-but-dark knowledge layer on and filled in daily-use table stakes:

- **Cleanup:** Planning-era dead code deleted outright — `DatabaseModels`/`TableModels`/`VaultDatabasePaths`, `EditCommand.registerDatabaseRow`, `NoteMetadata.artifacts`/`databaseRowReferences` (legacy sidecar keys ignored on decode), `LinkTarget` database/artifact cases, `NotesListView`/`sidebarOutline`, `VaultDriftReport`, extension-point placeholders. `AppModel` and the app shell were split into focused files (mechanical).
- **Vault reopen:** production persists the vault-root security-scoped bookmark and reopens the last vault at launch; **Switch Vault…** (⇧⌘O) and a "Reopen last vault at launch" preference ([ADR 0006, amended](adr/0006-threat-model-app-sandbox-vault-access.md)).
- **Knowledge layer on** ([ADR 0007](adr/0007-knowledge-layer-activation.md)): styled, clickable wiki links; `[[` autocomplete with a create-note row (mid-line, both editors); **Linked mentions** backlinks strip under the editor; vault search matches **title, path, and body** with snippets (background index; per-note patch on autosave).
- **Navigation:** Quick Open palette (⌘P; pinned + recents when idle), find bar with next/previous/replace/replace-all (engine-batched, one undo step), pinned notes and recents.
- **Structure:** nested sidebar folder tree with subtree focus; drag-and-drop note moving + "Move To"; **Finder-style icon browser** as the folder page's default view with per-folder persisted icon positions (`.miran/ui-state/`, [ADR 0008](adr/0008-trash-and-ui-state-stores.md)) and an icons/list toggle.
- **Safety & organization:** **Trash** with restore (identity-preserving) and Empty Trash ([ADR 0008](adr/0008-trash-and-ui-state-stores.md)); **tags** on `properties["tags"]` with a chip strip and `#tag` search; **Export** as Markdown or PDF.
- **Tasks** ([ADR 0009](adr/0009-task-blocks-and-todays-tasks.md)): `taskItem` blocks with `/task` (alias `/todo`), gutter checkboxes, strikethrough-when-done; Today's Tasks gains free day navigation (calendar picker), explicit/automatic rollover, and one-way note integration ("Add to Today's Tasks", source chips, "Mark Done in Note Too").
- **Attachments:** files under `_aux/<noteID>/attachments/` referenced by clickable `[attachment: name]` text tokens; Attach File… and drag-onto-editor.
- **Settings:** real ⌘, window — General (vault, reopen toggle), Editor (links, autocomplete, text size 12–20 pt with proportional headings, task rollover), Shortcuts (moved out of Folder Management).

`swift test`: 353 tests + 6 swift-testing, all green at the 2.0 milestone.

## 1.1 — Workspace compatibility, identity, and drift (Apr 2026)

Opening a folder as a workspace is gated by a **structural compatibility scan**: unsupported layouts produce a **report** instead of a partial import. **Note identity** resolution and **vault drift** validation support bulk import, reconcile, and automated checks.

### Behavior and code

- **Scan:** [`Sources/MiranNotesApp/Data/WorkspaceCompatibility.swift`](../Sources/MiranNotesApp/Data/WorkspaceCompatibility.swift) — `WorkspaceStructureScan`, `WorkspaceScanOutcome` (`.empty`, `.compatible`, `.incompatible`), `CompatibilityReport` / `CompatibilityIssue`, `IssueCode` (e.g. nested folders, disallowed root files, items inside note folders, symlinks, unreadable directories).
- **Policy:** [`Sources/MiranNotesApp/Data/WorkspaceCompatibilityPolicy.swift`](../Sources/MiranNotesApp/Data/WorkspaceCompatibilityPolicy.swift) — limits and rules shared by scanner and UI.
- **Incompatible folder UI:** [`Sources/MiranNotesApp/Features/Workspace/WorkspaceIncompatibleView.swift`](../Sources/MiranNotesApp/Features/Workspace/WorkspaceIncompatibleView.swift).
- **Compatible workspace shell:** [`Sources/MiranNotesApp/Features/Workspace/FolderPageView.swift`](../Sources/MiranNotesApp/Features/Workspace/FolderPageView.swift), [`WorkspaceFolderSidebarView.swift`](../Sources/MiranNotesApp/Features/Workspace/WorkspaceFolderSidebarView.swift).
- **Identity:** [`Sources/MiranNotesApp/Data/NoteIdentityResolution.swift`](../Sources/MiranNotesApp/Data/NoteIdentityResolution.swift) — resolution aligned with [ADR 0001](adr/0001-wiki-links-and-identity.md) and [guides/ImportingNotes.md](guides/ImportingNotes.md).
- **Drift:** [`Sources/MiranNotesApp/Data/VaultDriftReport.swift`](../Sources/MiranNotesApp/Data/VaultDriftReport.swift); `NoteRepository.validateVaultDrift()` in [`NoteRepository.swift`](../Sources/MiranNotesApp/Data/NoteRepository.swift).
- **Tests:** [`Tests/MiranNotesAppTests/NoteIdentityPolicyTests.swift`](../Tests/MiranNotesAppTests/NoteIdentityPolicyTests.swift), [`WorkspaceCompatibilityScannerTests.swift`](../Tests/MiranNotesAppTests/WorkspaceCompatibilityScannerTests.swift); related startup coverage in [`AppModelStartupSyncTests.swift`](../Tests/MiranNotesAppTests/AppModelStartupSyncTests.swift).

### Landmark commit

`0efde7b` — note identity, vault drift, workspace compatibility, import docs.

---

## 1.0 — Core local-first notes app (baseline)

Baseline after the **Apr 2026 pivot**: a minimal **knowledge storer** (editor, vault, links, folders, search). Miran Planning / calendar UI and related modules were **later removed** from the repository; see [ADR 0004](adr/0004-vault-level-databases-and-planning.md) amendment for vault-level databases.

- **On disk:** `.txt` + `.meta.json`; indexes under `.miran/`; nested folders, manifest v2 ([ADR 0003](adr/0003-folders-paths-and-manifest-v2.md)).
- **Editing:** `EditCommandEngine`, `SingleSurfaceNoteEditor`, slash discovery and auto-commit, wiki links ([ADR 0001](adr/0001-wiki-links-and-identity.md)).
- **Persistence:** Two-phase atomic vault commits, dirty index participants, startup recovery, `reconcileManifest()` vs read-only `listNotes()` ([architecture/vault-data-layer.md](architecture/vault-data-layer.md)).
- **Integrity / metadata:** Block sidecar invariants ([ADR 0005](adr/0005-block-metadata-invariants.md)); load repair and user advisories; external-edit conflict flow ([Constraints.md](../Constraints.md)).
- **Undo:** Hybrid inverse chains + full snapshots, capped stack ([Constraints.md](../Constraints.md), [archive/hybrid-undo-appmodel-wiring.md](archive/hybrid-undo-appmodel-wiring.md)).
- **App shell:** `AppModel` as `@MainActor` `@Observable`; Swift 6 language mode in `Package.swift`.
- **Legacy:** Per-note JSONL table feature removed from UI; `_aux` cleanup per [ADR 0002](adr/0002-auxiliary-storage-jsonl.md).
- **Databases:** Vault-level `_databases/` layout documented in [ADR 0004](adr/0004-vault-level-databases-and-planning.md); core types remain in `MiranNotesCore` for compatibility with older vaults.

### Git (thematic backtrace)

Vault v2 and repository integration (`39c157e`, `2935cf2`); index split and caching (`5a2664a`, `18c4d3a`); slash and editor hardening (`9a99e98`, `678b32a`); pivot (`5167c28`, `2b46413`); `@Observable` (`9ad6db8`); Swift 6 strict concurrency (`e5498f4`).

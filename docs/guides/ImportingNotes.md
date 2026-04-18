# Importing notes into a Miran workspace

**See also:** [VaultSafety.md](VaultSafety.md) — sync folders, backups, and external changes.

## Layout

- Note bodies are **`.txt` or `.md`** files. Each note has a sibling `.meta.json` sidecar that stores stable `noteID`, block structure, and links.
- The app keeps indexes under `.miran/` (manifest, path index, link graph, etc.). After a successful vault open, **every note listed in the manifest should have a body file (`.txt` or `.md`) and `.meta.json`.**
- **Workspace gate:** When you open a folder as a library, it must pass the in-app workspace layout check (`WorkspaceCompatibilityScanner`). Arbitrary project folders (many file types at the root, git repos with loose files, etc.) may be rejected until the tree matches Miran’s rules.
- **Flat topic folders:** Under the vault root, each top-level directory (except `.miran` / `_aux`) is a *topic folder*. Topic folders may contain **only** note bodies and `.meta.json` sidecars at that one level—**no nested subfolders** inside a topic folder.
- **One body format per folder:** Within the vault root “note tray” and within each topic folder, all note bodies must use the **same** extension—either all `.txt` or all `.md`. Mixing `.txt` and `.md` in the same folder makes the workspace **incompatible** until you move or convert files.

## Wiki links in imported bodies

- Notes may contain `[[Display Title]]` (or `[[alias|Target Title]]`) in the body text. If the sidecar’s `links` array is **empty** but the body contains these tokens, opening the note in Miran resolves targets against the vault manifest, updates `.meta.json`, and refreshes link indexes when at least one target matches a note in the library.

## Identity rules

- **`.meta.json` wins** if it disagrees with the manifest for the same path: the manifest is repaired to match the sidecar.
- If `.meta.json` is missing, the manifest’s `noteID` for that path is used until the app **materializes** a new sidecar (automatic after reconcile/open).
- **Never** infer long-term `noteID` from the file path alone: renames keep the same `noteID` while the relative path changes.

## Bulk import

- Copying or syncing many `.txt` or `.md` files into the vault is supported **where the layout rules above hold**: run the app or trigger **manifest reconcile** so new files are registered, indexed, and get `.meta.json` materialized.
- Prefer completing a full open/reconcile cycle once per bulk change so manifest, path index, and sidecars stay aligned.
- If you import `.md` into a folder that already has `.txt` notes, create a **new topic folder** for markdown-only notes (or convert imports to match the folder’s existing extension).

## Drift checks

- Use `NoteRepository.validateVaultDrift()` (or the drift report in tests via `VaultDriftValidator`) to detect:
  - note bodies (`.txt` / `.md`) not in the manifest
  - `.meta.json` without a matching body file
  - duplicate `noteID` values in different sidecars
  - path index rows that disagree with the manifest

Interpret non-empty reports as “needs repair” (often fixed by opening the vault in the app so reconcile and materialization run).

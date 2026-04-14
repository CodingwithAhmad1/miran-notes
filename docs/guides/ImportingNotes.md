# Importing notes into a Miran workspace

**See also:** [VaultSafety.md](VaultSafety.md) — sync folders, backups, and external changes.

## Layout

- Notes are `.txt` files. Each note has a sibling `.meta.json` sidecar that stores stable `noteID`, block structure, and links.
- The app also keeps indexes under `.miran/` (manifest, path index, link graph, etc.). After a successful vault open, **every note listed in the manifest should have both `.txt` and `.meta.json`.**

## Identity rules

- **`.meta.json` wins** if it disagrees with the manifest for the same path: the manifest is repaired to match the sidecar.
- If `.meta.json` is missing, the manifest’s `noteID` for that path is used until the app **materializes** a new sidecar (automatic after reconcile/open).
- **Never** infer long-term `noteID` from the file path alone: renames keep the same `noteID` while the relative path changes.

## Bulk import

- Copying or syncing many `.txt` files into the vault is supported: run the app or trigger **manifest reconcile** so new files are registered, indexed, and get `.meta.json` materialized.
- Prefer completing a full open/reconcile cycle once per bulk change so manifest, path index, and sidecars stay aligned.

## Drift checks

- Use `NoteRepository.validateVaultDrift()` (or the drift report in tests via `VaultDriftValidator`) to detect:
  - `.txt` files not in the manifest
  - `.meta.json` without a matching `.txt`
  - duplicate `noteID` values in different sidecars
  - path index rows that disagree with the manifest

Interpret non-empty reports as “needs repair” (often fixed by opening the vault in the app so reconcile and materialization run).

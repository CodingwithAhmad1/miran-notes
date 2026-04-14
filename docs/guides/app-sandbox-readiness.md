# App Sandbox readiness

This document tracks **macOS App Sandbox–style** distribution (notarized sandboxed app, Mac App Store, or stricter hardened-runtime expectations) and what is already implemented in-repo.

## Threat model and decisions

Authoritative write-up: [ADR 0006: Threat model, vault access capability, and App Sandbox path](../adr/0006-threat-model-app-sandbox-vault-access.md).

## Implemented in application code (bookmark seam)

- **`VaultWorkspaceAccess`** ([`VaultWorkspaceAccess.swift`](../../Sources/MiranNotesApp/Data/VaultWorkspaceAccess.swift)) — resolves the vault root, calls `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` when the OS grants scoped access, and supports **plain URL** behavior when sandboxing is off (typical `swift run` / `swift test`).
- **`VaultRootBookmarkStore`** ([`VaultRootBookmarkStore.swift`](../../Sources/MiranNotesApp/Data/VaultRootBookmarkStore.swift)) — persists vault-root bookmark **`Data`** under **Application Support** (`MiranNotes/vault-root.bookmark`), separate from wiki **`ExternalBookmarkStore`** data inside the vault.
- **App shell** ([`MiranNotesApp.swift`](../../Sources/MiranNotesApp/App/MiranNotesApp.swift)) — bootstraps from saved bookmark when valid; otherwise shows **Open a vault** until the user picks a folder. **`MIRAN_USE_DEFAULT_VAULT=1`** restores legacy bootstrap to `~/MiranNotesVault` for development. **Open Workspace…** adopts the panel URL, saves a bookmark, and replaces `NoteRepository` / `AppModel`. Stale or missing on-disk targets clear persistence and return to the open-vault prompt (or the dev default when that env var is set).

**Not implemented yet:** App Sandbox **entitlements**, an **`.app` bundle** product in this repo, or Hardened Runtime flags. `swift test` remains **unsandboxed** by default.

## Optional packaging: `.app` bundle and entitlements

When you need a **sandboxed** notarized build:

1. **Add an Xcode project or wrapper** that produces `MiranNotes.app` (SwiftPM can stay the source of truth; the Xcode target links the same sources or uses a generated project).
2. **Enable App Sandbox** on the app target and add a minimal **entitlements** plist, for example:
   - **User Selected File** (read/write) for the folder the user grants via `NSOpenPanel` (vault root).
   - Avoid **temporary-exception** / broad file access unless you have no alternative.
3. **Hardened Runtime** as required for notarization; map any JIT or unusual APIs to entitlement reality.
4. **QA:** Run the `.app` against a fresh user account: pick vault, quit, relaunch (bookmark restore), revoke access in System Settings if applicable, confirm **Open Workspace…** still recovers.

CI can keep **`swift test`** only; sandboxed `.app` verification can be **manual** or a separate job until you invest in automation.

## Risks and trade-offs

- **Bookmark lifecycle:** Stale bookmarks (moved/deleted vault) clear storage and prompt to open a vault again; users pick the folder (or a new location) via the welcome screen or **Open Workspace…**.
- **Developer ergonomics:** Contributors running `swift run` do not need entitlements; behavior matches unsandboxed desktop apps.

## Related

- [VaultSafety.md](VaultSafety.md) — sync folders and backups.
- [vault-data-layer.md](../architecture/vault-data-layer.md) — repository and vault root assumptions.

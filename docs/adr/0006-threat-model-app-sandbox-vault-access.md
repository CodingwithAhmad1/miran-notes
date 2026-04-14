# ADR 0006: Threat model, vault access capability, and App Sandbox path

## Status

Accepted (implementation in progress; OS entitlements optional until notarized sandboxed builds ship).

## Context

Miran Notes is a **local-first** macOS editor. The primary asset is the user’s **vault directory** (notes, `.miran/` indexes). The app is distributed today as a **SwiftPM executable** without App Sandbox enforcement at the package level.

Long-term distribution may require **notarized, sandboxed** builds. That implies **security-scoped bookmarks** for the vault root and **no reliance** on unrestricted filesystem access.

**Extensions** in this codebase are **in-process Swift** (`ExtensionRegistry`). There is **no** third-party native plugin loader in v1; the threat model must not assume arbitrary IPC or untrusted code modules until such a feature exists.

## Threat model (summary)

| Trusted | Untrusted / hostile input | Must not happen |
|---------|---------------------------|-----------------|
| App source (Swift); user actions via system UI (e.g. `NSOpenPanel`). | **Bytes on disk** under the vault: `.txt`, `.meta.json`, `.miran/*` (malformed JSON, pathological size, odd Unicode). **Sync tools** mutating files concurrently. | Reads/writes **outside** the user-granted vault root due to **path traversal**, resolver bugs, or missing security scope. |
| | | Silent dependence on **global** filesystem access when sandbox is on. |

**Out of scope v1:** Sandboxing does **not** by itself stop malicious **content inside** allowed files; existing validation (`NoteIntegrity`, `VaultPath` rules) and editor limits remain the defense there. **Blast radius** reduction is the main filesystem goal.

## Decision

1. **Single vault-root capability:** Introduce `VaultWorkspaceAccess` as the type that owns **resolved vault root URL** and **security-scoped access** lifecycle (`startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource`). App shell constructs `NoteRepository(vaultURL:)` only from this capability’s URL (or immediately after entering a scoped block—same effective contract).

2. **Persistence (vault root):** Production **does not** persist or restore a vault-root bookmark; each cold start shows the vault welcome / folder picker unless **`MIRAN_USE_DEFAULT_VAULT=1`** (local dev bootstrap to `~/MiranNotesVault`). Any legacy `vault-root.bookmark` under Application Support is removed on launch. `VaultRootBookmarkStore` remains for **unit tests** (redirected bookmark file path). **Open Workspace…** switches folders during a session. Security-scoped access still starts when the user picks a folder; there is no silent reopen of an arbitrary path without user interaction.

3. **Two bookmark domains:** Do not conflate vault-root bookmarks with **`ExternalBookmarkStore`** (wiki / external file targets under `.miran/`). They remain separate products of user consent.

4. **Non-sandbox development:** When App Sandbox is off, `startAccessingSecurityScopedResource()` may return `false`; I/O still uses the plain URL. One code path handles both.

5. **OS sandbox flip:** Enabling **entitlements** and an **`.app` bundle** is a **packaging** step (see [app-sandbox-readiness.md](../guides/app-sandbox-readiness.md)); application logic must not depend on “always unsandboxed.”

## Consequences

- Switching workspace must **stop** scoped access on the previous root before replacing the session (avoid leaks and stale grants).
- Contributors should prefer **`NoteRepository` / file actors** for vault I/O; views may show paths but must not write ad hoc to disk.
- CI continues to run **`swift test`** unsandboxed by default; sandboxed `.app` QA is optional.

## Related

- [app-sandbox-readiness.md](../guides/app-sandbox-readiness.md)
- [vault-data-layer.md](../architecture/vault-data-layer.md)
- [VaultSafety.md](../guides/VaultSafety.md)

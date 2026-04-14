# App Sandbox readiness (assessment)

This document is a **readiness assessment** for macOS App Sandbox–style distribution (Mac App Store, hardened runtime expectations, or stricter notarization policies). It is **not** an implementation plan for this repository phase: no entitlements, containers, or security-scoped bookmark code ships here yet.

## Current model

- The app is built and run as a **non-sandboxed** process with a **user-selected vault directory** (default under the home folder or via **Open Workspace…**).
- File access is whatever the user’s POSIX permissions and path choice allow. Miran does not implement encryption-at-rest or a custom containment boundary beyond normal macOS file semantics.

## What sandboxing would require

1. **Entitlements:** A minimal set aligned with “user documents” access—typically **no broad file access**; instead, **security-scoped bookmarks** (or repeated open-panel grants) for the vault root and any secondary paths the product must read or write.
2. **UX:** Clear **“Open vault”** (or re-open) flows when bookmarks are stale or missing after relaunch; error copy when access is denied under sandbox rules.
3. **Testing:** Full test and CI runs would need **bookmark-backed** vault fixtures or host permissions that mirror sandbox constraints; today’s tests assume unrestricted temp directories.
4. **Auxiliary paths:** Features that touch locations outside the chosen vault (e.g. future exports, helpers, or XPC) would each need explicit entitlements or scoped user consent.

## Risks and trade-offs

- **Bookmark lifecycle:** Revoked access, restored volumes, and iCloud “placeholder” files interact badly with naive path assumptions; the app already cares about external edits and sync—sandbox adds **permission** churn on top.
- **Developer ergonomics:** Local `swift test` and debugging remain simple without sandbox; turning on sandbox is a **project-wide** change (targets, CI, manual QA).

## Non-goals (this pass)

- No changes to **Info.plist** entitlements, **Hardened Runtime** flags, or **security-scoped** `URL` handling in app code.
- No requirement to ship the Mac App Store variant until product and legal posture explicitly target it.

## Related

- [VaultSafety.md](VaultSafety.md) — user-facing sync and backup expectations (orthogonal to sandbox, but both affect “where files live”).
- [vault-data-layer.md](../architecture/vault-data-layer.md) — repository and vault root assumptions.

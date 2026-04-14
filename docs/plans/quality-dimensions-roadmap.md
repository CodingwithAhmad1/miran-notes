# Quality dimensions roadmap

**Purpose:** This document captures the **current strengths** and a **prioritized, actionable improvement backlog** across six engineering dimensions: reliability, architecture, goal orientation, usability, performance, and security/robustness. It is written for **human contributors and downstream agents** implementing or extending Miran Notes.

**Scope:** Applies to the SwiftPM package layout (`MiranNotesCore`, `MiranNotesApp`), local vault storage, and the active product direction (minimal Mac-native notes; Miran Planning **deactivated** but code preserved). Cross-reference [Constraints.md](../../Constraints.md) and [docs/investor-and-engineering-brief.md](../investor-and-engineering-brief.md) for product and invariant context.

**Document maintenance:** When an improvement ships, update this file (or add a short “Completed” subsection with date and PR/commit pointer) so the backlog stays honest.

---

## 1. Reliability

### Current status and strengths

Miran Notes treats **data durability** as a first-class concern: vault changes use a **two-phase commit** model with **pending-commit staging** under `.miran/pending-commits/`, and **startup recovery** can complete or discard interrupted operations. Automated tests cover simulated mid-commit failure, corrupt staging discard, and clean recovery (`Tests/MiranNotesAppTests/VaultCrashSafetyTests.swift`).

**Autosave and navigation** were hardened against race conditions: `navigationGeneration` plus `flushCurrentNoteToDiskIfDirty()` ensure debounced saves do not corrupt `lastPersistedDocument` / selection state after note switches, and flushes occur before create/rename/selection paths that would otherwise drop in-memory edits. See [reliability-and-autosave-fixes.md](reliability-and-autosave-fixes.md) and `Sources/MiranNotesApp/App/AppModel.swift`.

**User-visible honesty:** Load repair, wiki/metadata gaps, size limits, vault recovery, and post-save integrity can surface as **dismissible advisories** (`RepairAdvisory`, `RepairNoticeBanner`) rather than silent fixes—aligned with [Constraints.md](../../Constraints.md) and the engineering brief.

**Test coverage:** The repository maintains a large automated test suite (`swift test` — see root [README.md](../../README.md) for current counts), including app-level tests for navigation, external edits, startup sync decisions, and repository behavior.

### Prioritized improvements

#### P1 — Stress and concurrency scenarios for vault + watch paths

- **Why it matters:** Correctness under single-user “normal” use is well tested; **high load** for a desktop app includes rapid filesystem events (sync tools, git, batch renames), bursty `VaultDirectoryWatcher` debounces, and overlapping `refreshNotes` / index updates. Latent races may only appear under churn.
- **Expected impact:** Fewer hard-to-reproduce bugs in the field; clearer confidence when changing `AppModel` or `VaultIndexActor`.
- **Constraints / dependencies:** May require **temporary test hooks** (e.g. injectable clock, watcher debounce override) or file-system fixtures in `Tests/MiranNotesAppTests/`. Coordinate with [vault-data-layer.md](../architecture/vault-data-layer.md) and `AppModelWatcherRaceTests` patterns.

#### P2 — Documented SLOs for recovery and integrity checks

- **Why it matters:** Operators and support need to know what “verified library” means in terms of **time and scope** (full scan vs incremental), especially on large vaults.
- **Expected impact:** Predictable UX after crashes; easier tuning of deferred work (e.g. link graph sync).
- **Constraints / dependencies:** Read from `startupLinkGraphSyncDecision` and related logging in `AppModel`; align copy in `RepairAdvisory` with actual behavior.

#### P3 — Expand observability for silent failure paths

- **Why it matters:** Any remaining `catch` blocks that clear state without `lastError` or user copy can look like “empty backlinks” or “stale list” when the real issue is I/O or index failure.
- **Expected impact:** Faster diagnosis; aligns with completed backlog item for backlink refresh surfacing—**audit** for similar patterns (search index, manifest reconcile).
- **Constraints / dependencies:** Prefer `os_log` categories + user-visible **non-blocking** banners per [Constraints.md](../../Constraints.md) tone (non-technical titles, optional details).

#### Completed (§1 — 2026-04-14)

- **P1:** `VaultDirectoryWatcher` test initializer (debounce without FSEvents) + `VaultDirectoryWatcherTests`; extended `AppModelWatcherRaceTests` (rapid `simulateWatcherEvent`, bulk note create + refresh / watcher). See [vault-data-layer.md](../architecture/vault-data-layer.md).
- **P2:** [reliability-expectations.md](reliability-expectations.md) documents recovery scope, link-graph sync thresholds (`startupLinkGraphSyncDecision`), and integrity advisory meaning; `RepairAdvisory.vaultRecoveryNotice` title aligned with actual startup recovery (not a full vault audit).
- **P3:** `buildBodySearchIndex` failures log and set `lastError`; per-note body read skips log at debug; `loadManifest` failure during note-by-ID selection logs and sets `lastError`; active-note presenter hash read failure logs before queuing reconcile.

---

## 2. Architectural cleanliness

### Current status and strengths

**Module separation is clear:** `MiranNotesCore` holds the document model, `EditCommandEngine`, `NoteIntegrity`, undo helpers, and extension contracts; `MiranNotesApp` owns persistence, vault indexes, and UI (`Package.swift`). This enables **unit testing core logic** without launching SwiftUI.

**Editing pipeline:** Structural mutations flow through **`EditCommandEngine`** and synchronous `apply`—a single place to reason about spans, blocks, and links—rather than ad hoc string surgery.

**Decision records:** [ADR](../adr/README.md) documents and [docs/architecture/](../architecture/) notes capture folder paths, manifest v2, vault databases, and metadata invariants—reducing tribal knowledge.

**Extension points:** `ExtensionRegistry`, slash command registry, and documented interceptor ordering support evolution without forking the core loop.

**Concentration risk:** `AppModel` remains a **large orchestration hub** (selection, vault load, autosave, undo, search, backlinks, external edits). That is common in SwiftUI apps but increases merge conflict and regression surface.

### Prioritized improvements

#### P1 — Decompose `AppModel` into cohesive collaborators

- **Why it matters:** Smaller types with narrow APIs are easier to test in isolation and reduce accidental coupling (e.g. persistence vs selection vs search).
- **Expected impact:** Safer feature work; clearer unit tests; potential for `@MainActor` isolation boundaries where appropriate.
- **Constraints / dependencies:** Must preserve **`@Observable`** behavior and SwiftUI binding sites (`@Bindable`); consider extracting **non-UI** services as `actor` or `final class` types injected into `AppModel`. Reference [architectural-refinements.md](../architecture/architectural-refinements.md) before splitting save/sync paths.

#### P2 — Define a thin “facade” for vault I/O vs index policy

- **Why it matters:** `NoteRepository`, `VaultIndexActor`, and commit coordination are powerful but **call graphs** can be hard to follow for new contributors.
- **Expected impact:** Easier onboarding; clearer place for “read-only list vs reconcile” rules ([vault-data-layer.md](../architecture/vault-data-layer.md)).
- **Constraints / dependencies:** Do not duplicate ADR content; link ADRs from code headers.

#### P3 — Classify preserved Planning / database code paths in the build

- **Why it matters:** Deactivated features under `Features/Planning/` and database infrastructure still compile; contributors may not know what is **shipping vs legacy**.
- **Expected impact:** Fewer mistaken edits; optional **compiler flags** or target separation if the team wants a hard boundary (see §3).
- **Constraints / dependencies:** Product decision: keep single target vs split targets; migration cost vs clarity.

#### Completed (§2 — 2026-04-14)

- **P1:** [`LinkGraphStartupPolicy`](../../Sources/MiranNotesApp/App/LinkGraphStartupPolicy.swift) holds startup link-graph sync mode/decision pure logic; `AppModel` keeps I/O and `UserDefaults` EMA.
- **P2:** [`VaultManifestRefreshFacade`](../../Sources/MiranNotesApp/Data/VaultManifestRefreshFacade.swift) centralizes invalidate + `reconcileManifest` for disk-driven refresh; header links `vault-data-layer.md` and ADR 0003.
- **P3:** [`MiranNotesLegacyDatabase`](../../Sources/MiranNotesLegacyDatabase/) library product for `DatabaseRepository` / `DatabaseDocument` (tests-only dependency of the app executable); [`VaultDatabasePaths`](../../Sources/MiranNotesCore/VaultDatabasePaths.swift) + `DatabaseRegistry.loadFromVault` in `MiranNotesCore`. See [architectural-refinements.md](../architecture/architectural-refinements.md).
- **Later pass (same §2 theme):** Further `AppModel` decomposition — [`NoteBodySearchIndexController`](../../Sources/MiranNotesApp/Data/NoteBodySearchIndexController.swift), [`DebouncedAsyncWorkScheduler`](../../Sources/MiranNotesApp/Data/DebouncedAsyncWorkScheduler.swift), [`FolderPageNoteLoading`](../../Sources/MiranNotesApp/Data/FolderPageNoteLoading.swift), [`AppModelUndoCheckpointSupport`](../../Sources/MiranNotesApp/App/AppModelUndoCheckpointSupport.swift); shared vault FS pipeline `processVaultFilesystemRefreshPipeline()` on `AppModel`. Optional deeper `NoteRepository` facades deferred until call-site churn justifies them.

---

## 3. Goal orientation

### Current status and strengths

**Product pivot is explicit:** The app is positioned as a **simple, local-first, Mac-native knowledge storer**; Miran Planning (calendar, menu bar, task/session DB UI) is **deactivated** while source is preserved ([README.md](../../README.md), [investor-and-engineering-brief.md](../investor-and-engineering-brief.md)).

**Core user journeys match positioning:** Vault open, nested folders, search with body snippets, block-aware editor, slash commands, wiki links by stable `noteID`, backlinks with snippets, atomic saves—consistent with “ownership of files” and “trustworthy place to store ideas.”

**Honest gap documentation:** The brief and plans describe known trade-offs (undo scope, external sync conflicts) instead of overselling.

**Residual complexity:** Vault-level databases (`_databases/`, ADR 0004) and Planning code remain **engineering assets** but add cognitive load for anyone asking “what is the product?”

### Prioritized improvements

#### P1 — Single “active product surface” map (docs + code pointers)

- **Why it matters:** New agents and contributors need a **one-page** list of what ships in `MiranNotesApp` vs preserved modules—without reading the entire repo.
- **Expected impact:** Faster alignment; fewer accidental features in Planning folders.
- **Constraints / dependencies:** Add to [docs/README.md](../README.md) or a short `docs/ACTIVE_PRODUCT.md` **only if** the team wants a new file; otherwise extend [plans/README.md](README.md) with a pointer table. Keep synchronized with root README pivot note.

#### P2 — First-run value proposition in the app shell

- **Why it matters:** Technical excellence does not replace **user clarity** on what Miran is for (and not for) on first launch or empty vault.
- **Expected impact:** Higher activation; fewer mis-set expectations vs Obsidian/Notion.
- **Constraints / dependencies:** UX copy must match [Constraints.md](../../Constraints.md) tone; coordinate with `WorkspaceIncompatibleView` and default vault behavior (`MiranNotesApp` init).

#### P3 — Prune or quarantine non-goals in the issue tracker / roadmap

- **Why it matters:** Backlog noise (e.g. cloud sync, collaboration) distracts from **local-first** hardening unless explicitly a future phase.
- **Expected impact:** Clearer prioritization for maintainers.
- **Constraints / dependencies:** Process change, not code; optional link from this document.

#### Non-goals and backlog hygiene (maintainers)

Treat the items below as **out of scope for the current product phase** unless a plan explicitly labels them as a **future phase** (see [Constraints.md](../../Constraints.md) § Product scope). That keeps this roadmap and other plans aligned with **local-first, single-writer** hardening.

- **Real-time multi-user collaboration** or shared editing as a driver for core architecture.
- **Hosted / mandatory cloud sync** or accounts as part of the default experience (users may still place vaults in sync folders on disk; that is an environmental choice, not a product pillar).
- **Reactivating Miran Planning UI** without a deliberate product decision and ADR update.

**Backlog hygiene:** In issues or planning docs, **tag or section** “Future phase / non-goal” ideas so they do not compete with actionable local-first work. This repository does not mandate a specific external tracker; if you use one, mirror the same labels there. The canonical **shipping vs preserved** map lives under [plans/README.md — Active product surface](README.md#active-product-surface).

#### Completed (§3 — 2026-04-14)

- **P1:** [plans/README.md — Active product surface](README.md#active-product-surface) table (ships vs preserved + code paths); [docs/README.md](../README.md) document map links to it.
- **P2:** Empty-vault welcome copy in `FolderPageView` (`isEmptyVaultOnboardingState` on `AppModel`); `AppModelEmptyVaultOnboardingTests`.
- **P3:** Maintainer subsection above (explicit non-goals + backlog hygiene pointer).

---

## 4. Usability

### Current status and strengths

**Conflict UX is strong:** External file changes vs a dirty editor surface a structured alert (keep edits, reload from disk, Finder, compare, details) with copy centralized for consistency (`ExternalEditConflictCopy`, `MiranNotesApp`).

**Repair and integrity:** Dismissible banners and optional detail sheets explain non-trivial situations without blocking editing (`EditorRootView`, `RepairAdvisory`).

**Workspace compatibility:** Incompatible folders are blocked with a dedicated view and “choose different folder” (`workspaceGateState`, `WorkspaceIncompatibleView`).

**Discoverability gaps:** Default vault path under `~/MiranNotesVault`, advanced behaviors (e.g. undo cleared on certain pane switches—see comments in `AppModel`), and “Open Workspace…” vs first-run expectations may confuse new users without onboarding.

### Prioritized improvements

#### P1 — Onboarding or empty-state content for vault location and workspace choice

- **Why it matters:** Users who do not discover **Command+Shift+O** may not understand where data lives or how to use a Git-backed folder.
- **Expected impact:** Fewer support questions; better trust.
- **Constraints / dependencies:** Must work with sandboxing if enabled later; keep paths user-visible and accurate; avoid modal overload.

#### P2 — Surface “power user” limitations in UI copy or settings

- **Why it matters:** Behaviors documented only in code comments (e.g. undo scope when switching panes) feel like bugs if not explained.
- **Expected impact:** Reduced perceived flakiness; aligns expectations with [editor-interaction-scenarios.md](editor-interaction-scenarios.md).
- **Constraints / dependencies:** Short, optional “Learn more” links; avoid cluttering minimal UI—prefer **one** consolidated “Editing” help surface if needed.

#### P3 — Consistent error channel for all async failures

- **Why it matters:** `lastError` alerts are generic; some failures may still need **context-specific** recovery actions (e.g. “retry index build”).
- **Expected impact:** Users recover without guessing; complements reliability P3.
- **Constraints / dependencies:** Coordinate with `RepairAdvisory` kinds—avoid duplicate banners.

#### Completed (§4 — 2026-04-14)

- **P1:** Empty-vault welcome in [`FolderPageView`](../../Sources/MiranNotesApp/Features/Workspace/FolderPageView.swift) shows the workspace path and Open Workspace… (Shift-Command-O); [`WorkspaceFolderSidebarView`](../../Sources/MiranNotesApp/Features/Workspace/WorkspaceFolderSidebarView.swift) footer shows a truncated path (full path in tooltip) for non-empty vaults.
- **P2:** Help → **Editing in Miran Notes…** opens [`EditingHelpSheet`](../../Sources/MiranNotesApp/Features/Help/EditingHelpSheet.swift) (undo / multi-pane, large notes, wiki links).
- **P3:** `AppModel.userAlert` (`UserAlertState` + `UserAlertRecoveryKind`) replaces `lastError`; vault recovery, manifest reconcile, link-graph sync, list/folder reload, backlinks, autosave, watcher, external-edit pipeline, compare sheet, view panes, and user mutation failures all use `.recoverable` with context-specific **Retry** in [`MiranNotesApp`](../../Sources/MiranNotesApp/App/MiranNotesApp.swift). [`AppModelUserAlertTests`](../../Tests/MiranNotesAppTests/AppModelUserAlertTests.swift).

---

## 5. Performance

### Current status and strengths

**Startup scaling:** `LinkGraphStartupPolicy.decision` defers heavy link-graph work when note counts or relationship counts exceed thresholds or historical timing budgets (configured on `AppModel`)—reduces launch stalls on large vaults.

**Write path:** Dirty flags on index participants and debounced autosave/backlink refresh reduce redundant disk and CPU work (see root [README.md](../../README.md)).

**Micro-benchmarks:** `EditEnginePerformanceTests` and related tests use `XCTMeasure` for large-document inserts and span-heavy paths (`Tests/MiranNotesTests/`).

**Gaps:** Full-stack perceived performance (TextKit + SwiftUI + layout) is **not** the same as isolated engine benchmarks; real hardware profiles may differ.

### Prioritized improvements

#### P1 — Full-stack profiling budget and checklist

- **Why it matters:** Establishes **baseline numbers** for time-to-interactive, first keystroke after open, and save latency at the **1 MB UTF-16** cap.
- **Expected impact:** Regressions caught early; informs deferred-work thresholds.
- **Constraints / dependencies:** Document methodology in [testing/performance-tests.md](../testing/performance-tests.md); optional Instruments templates; may require **Release** builds.

#### P2 — Extend statistical or threshold tests where flaky

- **Why it matters:** CI stability matters if performance tests gate merges.
- **Expected impact:** Fewer false reds; clearer signals—see existing `EditEnginePerformanceStatisticalTests.swift`.
- **Constraints / dependencies:** Machine variance; prefer **median** and loose thresholds on CI, stricter local dev.

#### P3 — Search and snippet latency at large vaults

- **Why it matters:** Sidebar search builds a **body index asynchronously**; UX should reflect loading state and avoid main-thread stalls when merging results.
- **Expected impact:** Smooth typing in search field; predictable results.
- **Constraints / dependencies:** `AppModel` search paths and `bodySearchIndex`—profile before adding caching complexity.

---

## 6. Security and robustness

### Current status and strengths

**Threat model fits a local editor:** Primary assets are **notes on disk** under a user-chosen vault; there is no multi-tenant server in the core architecture. Attack surface is largely **local filesystem**, malicious files, and user-controlled sync tools.

**Structural validation:** `NoteIntegrity.check` validates block coverage, ordering, and bounds for spans and links (`Sources/MiranNotesCore/NoteIntegrity.swift`).

**Bounds:** Editor enforces a **1 MB UTF-16** size limit with user-visible feedback (`SingleSurfaceNoteEditor`, README). Command batches have contract limits; violations are handled with assertions in development paths—review **Release** behavior for graceful degradation.

**Gaps:** Sync folders (Dropbox, iCloud), symlinks, and permission errors can produce **surprising conflicts** or partial writes outside the app’s control; **sandboxing** and encryption-at-rest are not described as core guarantees in the brief.

### Prioritized improvements

#### P1 — Document sync-folder and backup guidance for users

- **Why it matters:** “Local-first” users often put vaults in cloud-synced directories; conflict frequency and filesystem semantics are **external** but dominate perceived reliability.
- **Expected impact:** Fewer data-loss reports; sets expectations—complements external-edit conflict UI.
- **Constraints / dependencies:** Add to [guides/ImportingNotes.md](../guides/ImportingNotes.md) or a short “Vault safety” guide; keep technically accurate without fear-mongering.

#### P2 — Audit path handling and symlink policy within the vault root

- **Why it matters:** Unexpected symlink targets can break assumptions about containment and security boundaries if the app ever adds network or sharing features.
- **Expected impact:** Clearer guarantees; safer future features.
- **Constraints / dependencies:** Coordinate with `WorkspaceCompatibility` scanner and `FolderCatalog`/`PathIndex` invariants ([ADR 0003](../adr/0003-folders-paths-and-manifest-v2.md)).

#### P3 — Release behavior for assertion-guarded command limits

- **Why it matters:** `assertionFailure` on oversized batches does not help end users if triggered; production should **drop safely** with a user-visible notice or logged event.
- **Expected impact:** No undefined behavior in Release; supportability.
- **Constraints / dependencies:** `AppModel.apply` batch path—align with [Constraints.md](../../Constraints.md) on maximum batch size and telemetry.

#### P4 — Future: App Sandbox readiness assessment

- **Why it matters:** Distribution outside ad-hoc signing may require **sandbox entitlements**; vault access must be user-selected and bookmarked.
- **Expected impact:** Path to Mac App Store or notarized distribution without architectural surprise.
- **Constraints / dependencies:** Major UX change (security-scoped bookmarks); treat as a **project**, not a quick fix.

---

## Revision history

| Date | Change |
|------|--------|
| 2026-04-14 | Initial roadmap derived from repository review and engineering quality dimensions. |
| 2026-04-14 | §1 Reliability P1–P3 shipped: stress tests, reliability-expectations doc, search/manifest observability (see Completed under §1). |
| 2026-04-14 | §2 Architectural cleanliness P1–P3 shipped: `LinkGraphStartupPolicy`, `VaultManifestRefreshFacade`, `MiranNotesLegacyDatabase` + `VaultDatabasePaths` (see Completed under §2). |
| 2026-04-14 | §2 follow-up: `AppModel` helpers — body search index controller, debounced scheduler, folder-page loading, undo checkpoint support types; unified `processVaultFilesystemRefreshPipeline` (see Completed under §2). |
| 2026-04-14 | §3 Goal orientation P1–P3 shipped: active product surface doc, empty-vault welcome UX, non-goals / backlog hygiene (see Completed under §3). |
| 2026-04-14 | §4 Usability P1–P3 shipped: vault path onboarding + sidebar footer, Editing help sheet, `userAlert` with retry for body search index (see Completed under §4). |
| 2026-04-14 | §4 follow-up: all `AppModel` error alerts use `UserAlertRecoveryKind` with context-specific Retry (manifest, link graph, backlinks, autosave, watcher, etc.; see Completed §4 P3). |

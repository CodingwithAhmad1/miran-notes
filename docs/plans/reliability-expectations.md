# Reliability expectations (recovery, integrity, link sync)

This note documents **what the app actually does** at startup and after saves so operators and contributors can reason about **time and scope**—not a marketing guarantee. It complements [vault-data-layer.md](../architecture/vault-data-layer.md), [Constraints.md](../../Constraints.md), and `AppModel` in `Sources/MiranNotesApp/App/AppModel.swift`.

## Startup recovery (interrupted commits)

**Code path:** `NoteRepository.performStartupRecovery()` from `AppModel.loadVault`, implemented via `VaultCommitCoordinator.recoverPendingCommits` (see Constraints *Atomic vault commits*).

**Scope:** Only **pending two-phase commit staging** under `.miran/pending-commits/` is examined. The coordinator either completes renames from a valid journal, applies deferred deletes, or **discards** corrupt/incomplete staging so last-known-good files on disk remain.

**What it is not:** A full vault audit, cryptographic verification, or repair of arbitrary user filesystem damage outside the commit protocol.

**User copy:** When recovery does work, a dismissible advisory may appear (`RepairAdvisory.vaultRecoveryNotice`). The title and explanation describe **interrupted saves** and leftover staging—not “every byte in the library was validated.”

## Link graph sync at open (immediate vs deferred)

**Decision function:** `LinkGraphStartupPolicy.decision(noteCount:noteLinkRelationshipCount:hardThreshold:historicalAverageMs:budgetMs:)` in `Sources/MiranNotesApp/App/LinkGraphStartupPolicy.swift` (defaults on `AppModel`: `hardThreshold` 2000 notes, `budgetMs` 120 ms, history weight 0.3 for rolling average).

**Rules (first match wins for deferral):**

1. **`noteCount > hardThreshold`** → deferred (reason `noteCount>2000` with default threshold).
2. **`noteLinkRelationshipCount > hardThreshold * 5`** → deferred (`relationshipCountHigh`).
3. **Historical average** of past inline link-graph sync duration **`> budgetMs`** → deferred (`historicalAverageOverBudget`).
4. Otherwise → **immediate** inline sync (`withinBudget`).

**Behavior:**

- **Immediate:** `synchronizeLinkGraphFromRelationships()` runs during `loadVault` before the UI settles; backlinks and indexes match relationship data right away.
- **Deferred:** Sync runs in a background task; until it completes, link/backlink data may briefly lag on very large vaults. Failures set `lastError` (immediate or deferred).

**Tests:** Threshold behavior is covered in `Tests/MiranNotesAppTests/AppModelStartupSyncTests.swift`.

## Post-save and load integrity (`RepairAdvisory.vaultIntegrityNotice`)

**Scope:** After coordinated saves (and related paths), `VaultIntegrityChecker` runs **lightweight** checks: manifest path consistency, index referential consistency, and note shape where applicable.

**What it is not:** A full re-read of every note body or a guarantee that all wiki links resolve.

**UX:** Mismatches produce a dismissible advisory (“data check warning”); the user can keep editing. Details are optional technical lines for support.

## Watcher debouncing (filesystem churn)

`VaultDirectoryWatcher` debounces File System Events before calling into `AppModel` reconciliation. Bursts of events should coalesce to **one** handling pass per debounce window (see `Tests/MiranNotesAppTests/VaultDirectoryWatcherTests.swift`).

## Related tests

- `Tests/MiranNotesAppTests/VaultCrashSafetyTests.swift` — pending commit recovery simulation.
- `Tests/MiranNotesAppTests/AppModelWatcherRaceTests.swift` — autosave vs external reconciliation, churn simulations.
- `Tests/MiranNotesAppTests/VaultDirectoryWatcherTests.swift` — debounce coalescing.

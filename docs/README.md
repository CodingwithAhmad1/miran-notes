# Miran Notes — documentation hub

**Start here** when you open the repository in a new editor session or need the map of how documentation fits together.

## What this project is

Miran Notes is a **simple, minimalistic, local-first** macOS knowledge storer: canonical text in per-note `.txt` files, structured metadata in a sidecar, edits through `EditCommandEngine`, and a SwiftUI + AppKit editor.

> **Pivot (Apr 2026):** Miran Planning (menu-bar calendar, task/session databases, dashboard) has been **removed from the codebase**. The active product is the core note-taking experience — vault, editor, wiki links, folders, and search. Historical design remains in ADRs and archived notes.

The [root README](../README.md) summarizes build commands, module layout, and features.

**Legacy per-note tables:** An older experiment stored JSONL under `_aux/{noteID}/tables/`. The app no longer surfaces that feature; see [ADR 0002](adr/0002-auxiliary-storage-jsonl.md) for history and on-disk cleanup notes.

## Document map

| Document | Role |
|----------|------|
| [README.md](../README.md) | Product overview, architecture summary, run/test |
| [Constraints.md](../Constraints.md) | Non-negotiable engineering constraints and editor/undo/storage rules |
| [investor-and-engineering-brief.md](investor-and-engineering-brief.md) | Investor + engineer narrative: product, architecture, gaps, positioning |
| [CHANGELOG.md](CHANGELOG.md) | Documentation milestones (1.0 baseline, 1.1 workspace compatibility — not app bundle versions) |
| **Guides** | |
| [guides/ImportingNotes.md](guides/ImportingNotes.md) | Importing `.txt` into a workspace: identity rules, bulk import, drift checks |
| [guides/VaultSafety.md](guides/VaultSafety.md) | Sync folders, backups, and expectations when the vault lives in cloud sync |
| [guides/app-sandbox-readiness.md](guides/app-sandbox-readiness.md) | Assessment: what App Sandbox would imply (bookmarks, UX, testing); no implementation in this phase |
| **Architecture** | |
| [architecture/architectural-refinements.md](architecture/architectural-refinements.md) | Editor sync, extension wiring, vault index notes, undo / external-edit context |
| [architecture/extension-registry-and-interceptors.md](architecture/extension-registry-and-interceptors.md) | `ExtensionRegistry` vs closure interceptors and apply order |
| [architecture/slash-command-framework.md](architecture/slash-command-framework.md) | Slash contracts, discovery UX, extension pattern |
| [architecture/block-chrome-interaction-model.md](architecture/block-chrome-interaction-model.md) | Block chrome design for future interactive handles |
| [architecture/vault-data-layer.md](architecture/vault-data-layer.md) | Repository, on-disk layout, text hash vs revision token, TOCTOU |
| **Archive** | |
| [archive/README.md](archive/README.md) | Superseded 2026 briefs (historical context only); live story in ADRs and [CHANGELOG.md](CHANGELOG.md) |
| **ADRs** | |
| [adr/README.md](adr/README.md) | Architecture Decision Records index (includes [0006](adr/0006-threat-model-app-sandbox-vault-access.md) threat model / vault bookmarks) |
| **Plans and QA** | |
| [plans/README.md](plans/README.md) | Planning docs index, completed plans, and [**Active product surface**](plans/README.md#active-product-surface) (what ships vs historical design) |
| [plans/longevity-and-migration-analysis.md](plans/longevity-and-migration-analysis.md) | Longevity assessment; `@Observable` and Swift 6 language mode **done**; TextKit 2 typing migration still planned |
| [plans/editor-interaction-scenarios.md](plans/editor-interaction-scenarios.md) | Manual QA checklist (typing, blocks, IME, large notes) |
| [plans/quality-dimensions-roadmap.md](plans/quality-dimensions-roadmap.md) | Six-dimension quality assessment: strengths, prioritized actionable improvements (reliability, architecture, goals, UX, performance, security) |
| [plans/reliability-expectations.md](plans/reliability-expectations.md) | Recovery scope, link-graph sync SLOs, integrity advisory meaning, watcher debounce |
| [archive/hybrid-undo-appmodel-wiring.md](archive/hybrid-undo-appmodel-wiring.md) | Hybrid undo implementation (completed) |
| **Testing** | |
| [testing/ui-tests.md](testing/ui-tests.md) | UI test host / XCUITest notes for SPM |
| [testing/performance-tests.md](testing/performance-tests.md) | Edit-engine statistical (median) performance tests for CI |

## How to use this folder

- **Constraints** live at the repository root for visibility; they are linked from here.
- **ADRs** live under `docs/adr/` with numeric prefixes. Add new ADRs in sequence when a decision is stable.
- **Release-style history** for contributors is summarized in [CHANGELOG.md](CHANGELOG.md) (documentation milestones, not necessarily app marketing versions).
- **Plans** under `docs/plans/` belong in version control when shared with contributors; see [plans/README.md](plans/README.md). Cursor-only plans under `.cursor/plans/` are often not committed; copy durable content here when needed.

## Code pointers (quick orientation)

- **Core:** `Sources/MiranNotesCore/` — `NoteDocument`, `EditCommandEngine`, `UndoInverseSupport`, `TextEditDiff`, `NoteIntegrity`, `ExtensionRegistry`, `CommandPipelineContract`, `DatabaseModels`, `LinkTarget`.
- **App / Data:** `Sources/MiranNotesApp/Data/` — `NoteRepository`, `VaultCommitCoordinator`, indexes (`LinkGraph`, `RelationshipIndex`, `FolderCatalog`, `PathIndex`), and related vault I/O types.
- **App / Editor:** `Sources/MiranNotesApp/Features/Editor/` — `SingleSurfaceNoteEditor`, `EditorVisualStyle`, `SlashCommandRegistry`.
- **App / Workspace:** `Sources/MiranNotesApp/Features/Workspace/` — folder workspace shell (`FolderPageView`, `WorkspaceFolderSidebarView`), `WorkspaceIncompatibleView` when a chosen folder fails the compatibility scan (see `Data/WorkspaceCompatibility.swift`).
- **App shell:** `Sources/MiranNotesApp/App/` — `AppModel`, `MiranNotesApp`.
- **Tests:** `Tests/MiranNotesTests/`, `Tests/MiranNotesAppTests/` (`swift test`).

## Key `AppModel` observable state (selected)

`AppModel` is `@MainActor @Observable` (Swift `Observation` framework). SwiftUI observes individual properties; views that need `$` bindings use `@Bindable var model: AppModel` (see `MiranNotesApp`, `NotesListView`, `EditorRootView`, `ActiveEditorPane`).

| Property | Purpose |
|----------|---------|
| `activeDocument` | Current `NoteDocument` in the editor |
| `repairAdvisory` | Load-time / integrity / size-limit advisories (`RepairAdvisory`) |
| `editorCursorOffset` | Live UTF-16 caret position; reset on note switch |
| `editorTextSelection` | UTF-16 selection range for command context |
| `externalEditConflictAlert` | External change vs dirty buffer |
| `extensionRegistry` | Typed extension registry (runs before closure interceptors) |

## Key `AppModel` internals (tests)

| Property | Purpose |
|----------|---------|
| `undoHistory` | Action names per undo step (mirrors menu labels) |
| `undoRetentionMemoryEstimateBytes` | Approximate retained undo state (hybrid + full checkpoints) |

For editor behavior and limits, read [Constraints.md](../Constraints.md) before changing the text pipeline or metadata rules.

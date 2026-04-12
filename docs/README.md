# Miran Notes — documentation hub

**Start here** when you open the repository in a new editor session or need the map of how documentation fits together.

## What this project is

Miran Notes is a **local-first** macOS notes app: canonical text in per-note `.txt` files, structured metadata in a sidecar, edits through `EditCommandEngine`, and a SwiftUI + AppKit editor. The [root README](../README.md) summarizes build commands, module layout, and features.

## Document map

| Document | Role |
|----------|------|
| [README.md](../README.md) | Product overview, architecture summary, run/test |
| [Constraints.md](../Constraints.md) | Non-negotiable engineering constraints and editor/undo/storage rules |
| [investor-and-engineering-brief.md](investor-and-engineering-brief.md) | Investor + engineer narrative: product, architecture, gaps, positioning |
| **Architecture** | |
| [architecture/architectural-refinements.md](architecture/architectural-refinements.md) | Editor sync, extension wiring, vault index notes, undo / external-edit context |
| [architecture/extension-registry-and-interceptors.md](architecture/extension-registry-and-interceptors.md) | `ExtensionRegistry` vs closure interceptors and apply order |
| [architecture/slash-command-framework.md](architecture/slash-command-framework.md) | Slash contracts, discovery UX, extension pattern |
| [architecture/block-chrome-interaction-model.md](architecture/block-chrome-interaction-model.md) | Block chrome design for future interactive handles |
| [architecture/user-and-technical-priorities.md](architecture/user-and-technical-priorities.md) | User and technical priorities brief |
| [architecture/architecture-flexibility-assessment.md](architecture/architecture-flexibility-assessment.md) | Flexibility and product-fit assessment |
| [architecture/links-folders-tables-database-analysis.md](architecture/links-folders-tables-database-analysis.md) | Links, folders, tables analysis |
| **ADRs** | |
| [adr/README.md](adr/README.md) | Architecture Decision Records index |
| **Plans and QA** | |
| [plans/README.md](plans/README.md) | Planning docs index and completed plans |
| [plans/editor-interaction-scenarios.md](plans/editor-interaction-scenarios.md) | Manual QA checklist (typing, blocks, IME, large notes) |
| [plans/hybrid-undo-appmodel-wiring.md](plans/hybrid-undo-appmodel-wiring.md) | Hybrid undo implementation (completed) |
| **Testing** | |
| [testing/ui-tests.md](testing/ui-tests.md) | UI test host / XCUITest notes for SPM |

## How to use this folder

- **Constraints** live at the repository root for visibility; they are linked from here.
- **ADRs** live under `docs/adr/` with numeric prefixes. Add new ADRs in sequence when a decision is stable.
- **Plans** under `docs/plans/` belong in version control when shared with contributors; see [plans/README.md](plans/README.md). Cursor-only plans under `.cursor/plans/` are often not committed; copy durable content here when needed.

## Code pointers (quick orientation)

- **Core:** `Sources/MiranNotesCore/` — `NoteDocument`, `EditCommandEngine`, `UndoInverseSupport`, `TextEditDiff`, `NoteIntegrity`, `ExtensionRegistry`, `CommandPipelineContract`.
- **App:** `Sources/MiranNotesApp/` — `AppModel`, `SingleSurfaceNoteEditor`, `EditorVisualStyle`, `SlashCommandRegistry`, `NoteRepository`, `VaultCommitCoordinator`, indexes (`LinkGraph`, `RelationshipIndex`, `FolderCatalog`, `PathIndex`).
- **Tests:** `Tests/MiranNotesTests/`, `Tests/MiranNotesAppTests/` (`swift test`).

## Key `AppModel` published properties (selected)

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
| `cachedLinkGraph` | In-memory link graph cache |

For editor behavior and limits, read [Constraints.md](../Constraints.md) before changing the text pipeline or metadata rules.

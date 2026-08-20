# Constraints to Implementation Touchpoint Map

This map links binding constraints in `Constraints.md` to current implementation touchpoints and explicit risk classes.

## 1) Local-first single-writer, human-readable storage
- **Touchpoints**
  - `Sources/MiranNotesApp/Data/NoteRepository.swift`
  - `Sources/MiranNotesApp/Data/VaultPaths.swift`
- **Risk class**
  - **Robustness**: partial persistence across multiple files (`.txt`, `.meta.json`, manifest, link graph).
  - **UX**: conflict prompts must stay explicit when external edits race local dirty buffers.

## 2) Semantic reconciliation must detect ambiguity, no silent semantic winner
- **Touchpoints**
  - `Sources/MiranNotesApp/Data/NoteRepository.swift` (`documentAfterLoadRepair`)
  - `Sources/MiranNotesApp/App/AppModel.swift` (`repairNotice`)
- **Risk class**
  - **Robustness**: metadata reconstruction can be structurally valid but semantically ambiguous.
  - **UX**: user advisory and save policy must keep ambiguity visible.

## 3) Editor/model dual representation and sync
- **Touchpoints**
  - `Sources/MiranNotesApp/Features/Editor/SingleSurfaceNoteEditor.swift`
  - `Sources/MiranNotesCore/TextEditDiff.swift`
  - `Sources/MiranNotesApp/Features/Editor/DocumentLayoutController.swift`
- **Risk class**
  - **Robustness**: desync risk when multiple ingress paths mutate text and structure. Full-buffer fallback now triggers `reconcileBlocksFromText` for heading recovery and surfaces `onFullReplaceWarning` to the user.
  - **Efficiency**: incremental `EditorVisualStyle.apply` guard (document-ID + text cache) reduces redundant styling passes. 1 MB cap prevents unbounded buffer growth.
  - **UX**: IME/selection correctness must not regress.

## 4) Edit command semantics and undo limits must stay explicit
- **Touchpoints**
  - `Sources/MiranNotesCore/EditCommandEngine.swift`
  - `Sources/MiranNotesApp/App/AppModel.swift` (`apply`, snapshot undo registration, `undoHistory`, `removeCommandInterceptor`)
- **Risk class**
  - **Robustness**: stack invalidation around reload/navigation must remain deterministic. Count-bounded deque (200 steps) with graceful pruning and `UUID`-token interceptor deregistration address unbounded growth and interceptor leaks.
  - **Efficiency**: 200-step cap bounds memory growth; snapshot size still proportional to document length.
  - **UX**: action naming and stack resets must stay predictable.

## 5) Load/save integrity and structural normalization
- **Touchpoints**
  - `Sources/MiranNotesCore/RangeNormalizer.swift`
  - `Sources/MiranNotesCore/NoteIntegrity.swift`
  - `Sources/MiranNotesApp/Data/NoteRepository.swift`
- **Risk class**
  - **Robustness**: guardrail is structural validity, not semantic intent certainty.
  - **Efficiency**: repeated normalization is safety-first but can cost CPU on large notes.

## 6) Vault watching and external conflicts (TOCTOU acknowledged)
- **Touchpoints**
  - `Sources/MiranNotesApp/Data/VaultDirectoryWatcher.swift`
  - `Sources/MiranNotesApp/App/AppModel.swift` (`processExternalDiskActivity`)
- **Risk class**
  - **Robustness**: timestamp-only identity has blind spots under rapid or tooling-driven writes.
  - **UX**: conflict copy/choices must stay explicit and non-destructive.

## 7) Slash commands, formatting, IME safety constraints
- **Touchpoints**
  - `Sources/MiranNotesApp/Features/Editor/SlashCommandDetector.swift`
  - `Sources/MiranNotesApp/Features/Editor/SlashCommandRegistry.swift` (open for extension via `register(_:)`; builtins via `registerBuiltins()`)
  - `Sources/MiranNotesApp/Features/Editor/SingleSurfaceNoteEditor.swift`
  - `Sources/MiranNotesApp/App/MiranNotesApp.swift` (calls `registerBuiltins()` at startup)
- **Risk class**
  - **UX**: command discoverability and expected trigger behavior.
  - **Robustness**: composition safety during marked text. Registry is now open without requiring modification of built-in arrays.

## 8) Extension points and future evolution
- **Touchpoints**
  - `Sources/MiranNotesCore/ExtensionPoints.swift`
- **Risk class**
  - **None immediate runtime**: currently declarative placeholders.
  - **Future robustness/expandability**: lack of runtime contracts can lead to ad-hoc branching.

## 9) Integrity and test expectations
- **Touchpoints**
  - `Tests/MiranNotesTests/` — core, `adjustBlocks`, `splitBlock` cross-boundary span/link clipping
  - `Tests/MiranNotesAppTests/` — app, navigation, undo (`AppModelUndoTests`), dirty-flag saves (`LinkGraphDirtyFlagTests`), watcher-race (`AppModelWatcherRaceTests`), visual style (`EditorVisualStyleTests`), performance baselines
- **Risk class**
  - **Robustness**: watcher race and deferred-reconciliation covered by `AppModelWatcherRaceTests`. `splitBlock` cross-boundary correctness covered by `SpanAndBlockAdjustmentTests`.
  - **Efficiency**: `EditEnginePerformanceTests` enforces `measure {}` baselines; dirty-flag index guards reduce spurious disk I/O.

## 10) Atomic vault commits and dirty-flag persistence (Foundation Hardening)
- **Touchpoints**
  - `Sources/MiranNotesApp/Data/VaultCommit.swift` (`VaultCommitCoordinator`, two-phase prepare/commit)
  - `Sources/MiranNotesApp/Data/NoteRepository.swift` (all `VaultCommitParticipant` implementations)
  - `Sources/MiranNotesApp/Data/LinkGraph.swift`, `RelationshipIndex.swift`, `FolderCatalog.swift`, `PathIndex.swift` (`isDirty` flags)
- **Risk class**
  - **Robustness**: two-phase commit ensures either all files are written or none; partial vault states are no longer possible from a single commit call.
  - **Efficiency**: dirty-flag guards skip serialization and disk writes for unchanged indexes.

## 11) Note identity and data model integrity (Foundation Hardening)
- **Touchpoints**
  - `Sources/MiranNotesCore/NoteDocument.swift` (computed `id` property)
  - `Sources/MiranNotesApp/Data/NoteRepository.swift` (`slugify` 200-byte cap)
  - `Sources/MiranNotesCore/EditCommandEngine.swift` (`splitBlock` with `constrainToBlocks`, `reconcileBlocksFromText`)
  - `Sources/MiranNotesCore/SpanAdjuster.swift`, `NoteLink.swift` (exposed `constrainToBlocks`)
- **Risk class**
  - **Robustness**: dual-identity ambiguity eliminated; cross-boundary span/link leakage after split eliminated.
  - **Correctness**: filename slug truncation now safe for multi-byte characters.

## 12) AppModel lifecycle and performance (Foundation Hardening)
- **Touchpoints**
  - `Sources/MiranNotesApp/App/AppModel.swift` (count-bounded undo, `UUID`-token interceptors, debounced backlink cache, `editorCursorOffset` reset, batch truncation guard)
  - `Sources/MiranNotesApp/Features/Editor/SingleSurfaceNoteEditor.swift` (1 MB cap, `onFullReplaceWarning`, `onSizeLimitExceeded`, incremental `EditorVisualStyle` guard)
  - `Sources/MiranNotesApp/App/UndoPolicy.swift` (count-based `maxUndoSteps`)
- **Risk class**
  - **Efficiency**: unbounded undo memory growth bounded; per-keystroke backlink scans eliminated; redundant styling passes eliminated.
  - **Robustness**: size cap prevents runaway buffer allocation; interceptor leak eliminated.
  - **UX**: cursor reset on note switch prevents stale caret positions.

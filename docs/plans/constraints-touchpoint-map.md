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
  - `Sources/MiranNotesApp/Features/Editor/TextEditDiff.swift`
  - `Sources/MiranNotesApp/Features/Editor/DocumentLayoutController.swift`
- **Risk class**
  - **Robustness**: desync risk when multiple ingress paths mutate text and structure.
  - **Efficiency**: full-buffer fallback replace can be expensive.
  - **UX**: IME/selection correctness must not regress.

## 4) Edit command semantics and undo limits must stay explicit
- **Touchpoints**
  - `Sources/MiranNotesCore/EditCommandEngine.swift`
  - `Sources/MiranNotesApp/App/AppModel.swift` (`apply`, snapshot undo registration)
- **Risk class**
  - **Robustness**: stack invalidation around reload/navigation must remain deterministic.
  - **Efficiency**: snapshot-based undo has memory growth pressure.
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
  - `Sources/MiranNotesApp/Features/Editor/SlashCommandRegistry.swift`
  - `Sources/MiranNotesApp/Features/Editor/SingleSurfaceNoteEditor.swift`
- **Risk class**
  - **UX**: command discoverability and expected trigger behavior.
  - **Robustness**: composition safety during marked text.

## 8) Extension points and future evolution
- **Touchpoints**
  - `Sources/MiranNotesCore/ExtensionPoints.swift`
- **Risk class**
  - **None immediate runtime**: currently declarative placeholders.
  - **Future robustness/expandability**: lack of runtime contracts can lead to ad-hoc branching.

## 9) Integrity and test expectations
- **Touchpoints**
  - `Tests/MiranNotesTests/`
  - `Tests/MiranNotesAppTests/`
- **Risk class**
  - **Robustness**: race and watcher behavior still need broader coverage.
  - **Efficiency**: no enforced perf budgets for large documents yet.

# Longevity and Migration Analysis

Analysis of platform pressure points that will require engineering attention over the next 1–5 years, with concrete migration plans sized against the actual codebase.

**Date:** April 2026
**Codebase snapshot:** 105 Swift files, Swift 5.10 / macOS 14, zero third-party SPM dependencies.

---

## Part 1: Longevity Assessment

### Strengths (what buys time)

- **Zero third-party dependencies.** `Package.swift` declares only internal targets. This removes the entire category of dependency rot — no version pinning, no upstream breaking changes, no transitive vulnerability churn.
- **Swift 5.x ABI and source stability.** Swift has been ABI-stable since 5.0 (2019) and source-compatible across 5.x releases. The codebase's Swift 5.10 code will compile on future Swift compilers for a long time.
- **AppKit.** The most stable framework Apple ships. `NSTextView`, `NSScrollView`, `NSView` — these APIs are decades old and essentially frozen. AppKit code from 2012 still compiles and runs today.
- **Foundation, CryptoKit, CoreServices, os.log.** All stable, mature system frameworks with no sign of deprecation.

### Pressure points

| Area | Breakage type | Estimated comfortable lifespan |
|------|---------------|-------------------------------|
| Third-party deps | N/A — none | Indefinite |
| Swift language | Source-compatible | 5+ years |
| AppKit APIs | Frozen / stable | 5–10+ years |
| **TextKit 1** | **Subtle bugs, no new fixes from Apple** | **~3–5 years before real pain** |
| ObservableObject | Friction with new SwiftUI APIs | ~2–4 years |
| Swift 6 strict concurrency | Compiler warnings / errors (opt-in) | ~1–2 years (voluntary migration) |
| macOS 14 minimum target | Feels dated | ~2–3 years before bump needed |

---

## Part 2: Migration 1 — ObservableObject to @Observable

### Difficulty: Very easy. One-pass, near-certain success.

### Current surface area

| Item | Count | Files |
|------|-------|-------|
| `ObservableObject` conformances | 1 | `AppModel.swift` |
| `@Published` properties | 20 | `AppModel.swift` |
| `@StateObject` usage | 1 | `MiranNotesApp.swift` |
| `@ObservedObject` usage | 6 | `NotesListView.swift` (×2), `MiranNotesApp.swift`, `TiledEditorView.swift` (×2), `LayoutSelectorView.swift` |
| `@EnvironmentObject` | 0 | — |
| Combine / `objectWillChange` / `.sink` | 0 | — |
| Nested `ObservableObject` types | 0 | — |
| Manual `objectWillChange.send()` | 0 | — |

### Why this is favorable

- Single root observable (`AppModel`) with no child observables.
- No Combine dependency — the codebase uses async/await for side effects.
- Already targeting macOS 14, which is the minimum for `@Observable`.
- `bodySearchIndex` has `private(set)` — this pattern works natively with `@Observable`.

### Migration steps

**Step 1: `AppModel.swift`**
```swift
// Before
@MainActor
final class AppModel: ObservableObject {
    @Published var noteSummaries: [NoteSummary] = []
    @Published var selectedNoteID: UUID?
    @Published private(set) var bodySearchIndex: [UUID: String] = [:]
    // ... 17 more @Published properties
}

// After
@MainActor @Observable
final class AppModel {
    var noteSummaries: [NoteSummary] = []
    var selectedNoteID: UUID?
    private(set) var bodySearchIndex: [UUID: String] = [:]
    // ... 17 more stored properties (remove @Published)
}
```

**Step 2: `MiranNotesApp.swift`**
```swift
// Before
@StateObject private var model: AppModel
// init: _model = StateObject(wrappedValue: AppModel(repository: repository))

// After
@State private var model: AppModel
// init: _model = State(wrappedValue: AppModel(repository: repository))
```

**Step 3: Views with `@ObservedObject`**

For views that only read (no `$` bindings):
```swift
// Before
@ObservedObject var model: AppModel

// After
var model: AppModel
```

For views that use `$model.foo` bindings (sheet items, searchable, editor bindings):
```swift
// Before
@ObservedObject var model: AppModel
// usage: .sheet(item: $model.somePayload)

// After
@Bindable var model: AppModel
// usage: .sheet(item: $model.somePayload) — same syntax, different wrapper
```

**Step 4: Custom `Binding(get:set:)` wrappers**

The `Binding(get: { model.lastError }, set: { ... })` patterns in `MiranNotesApp.swift` continue to work unchanged with `@Observable`.

### Binding sites requiring `@Bindable`

| File | Line(s) | Binding pattern |
|------|---------|-----------------|
| `MiranNotesApp.swift` | *(sheet bindings)* | `.sheet(item: $model.externalTextCompare)` and other item sheets |
| `MiranNotesApp.swift` | 170–171 | `$model.editorCursorOffset`, `$model.editorTextSelection` |
| `NotesListView.swift` | 86 | `.searchable(text: $model.noteQuery)` |
| `TiledEditorView.swift` | 159–160 | `$model.editorCursorOffset`, `$model.editorTextSelection` |

These views need `@Bindable var model: AppModel` instead of bare `var`.

### Tests

Tests construct `AppModel(repository:)` as a plain value — no property wrappers. Migration requires zero test changes.

### Risk assessment

**Confidence: ~95%.** The only non-mechanical consideration is SwiftUI view update granularity. With `@Observable`, views re-render only when the *specific* properties they read change, rather than on any `@Published` mutation. This is typically a performance *improvement*, but should be verified with a smoke test across note switching, search, and editor interactions.

---

## Part 3: Migration 2 — Swift 6 Strict Concurrency

### Difficulty: Medium. Achievable in 2–3 compiler-guided passes.

### Current concurrency posture

**Actors (6):**

| Actor | File | Risk |
|-------|------|------|
| `VaultIndexActor` | `Data/VaultIndexActor.swift` | Low — clear isolation |
| `NoteFileActor` | `Data/NoteFileActor.swift` | Low |
| `NoteRepository` | `Data/NoteRepository.swift` | Low–medium — many APIs; ensure payloads are Sendable |
| `DatabaseDocument` | `Data/DatabaseDocument.swift` | Low |
| `DatabaseRepository` | `Data/DatabaseRepository.swift` | Medium — fire-and-forget `Task` usage |
| `ExternalBookmarkStore` | `Data/ExternalBookmarkStore.swift` | Low |

**`@MainActor` annotations:**

- `AppModel` (entire class) — good central pivot.
- `VaultDirectoryWatcher.onEvent` and `onSetupFailed` closures.
- 12+ test classes.

**`nonisolated` usage (7 sites, all low risk):**

| File | What | Risk |
|------|------|------|
| `VaultIndexActor.swift` | `nonisolated let vaultURL` | Low — `URL` is `Sendable` |
| `NoteFileActor.swift` | `nonisolated let vaultURL` | Low |
| `NoteFileActor.swift` | `private nonisolated static func documentAfterLoadRepair(...)` | Low — pure transform |
| `NoteRepository.swift` | `nonisolated let vaultURL` | Low |
| `NoteRepository.swift` | `nonisolated static func validateBaseName` | Low — pure |
| `DatabaseRepository.swift` | `nonisolated let vaultURL` | Low |
| `AppModel.swift` | `nonisolated static func startupLinkGraphSyncDecision(...)` | Low — pure decision helper |

**`@unchecked Sendable` (1 site):**

- `ExtensionRegistry` (`ExtensionRegistry.swift` line 49) — uses `NSLock` for thread safety. Medium risk: acceptable if lock coverage is complete. May want to migrate to actor or `Mutex`.

**GCD / legacy primitives:**

- `VaultDirectoryWatcher` — `FSEventStreamSetDispatchQueue(streamRef, DispatchQueue.main)` + `FSEventStreamCallback` with `Unmanaged.passUnretained`. Medium risk.
- `ActiveNoteFilePresenter` — `presentedItemOperationQueue = OperationQueue.main`. Low risk.
- `ExtensionRegistry` — `NSLock`. Low–medium.
- No `DispatchSemaphore`, `DispatchGroup`, or `DispatchWorkItem`.

**Global mutable state:**

- `SlashCommandRegistry` — `private static var descriptors`, `private static var builtinsRegistered`. Medium risk: unsynchronized mutable statics. Only mutated from `registerBuiltins()` at startup, but Swift 6 may flag this.

### Migration tiers

**Tier 1 — Mechanical (high confidence):**

1. Add `Sendable` to core value types that cross isolation boundaries: `NoteDocument`, `NoteMetadata`, `Block`, `Span`, `EditCommand`, `NoteLink`, `NoteSummary`, `BacklinkItem`, `RepairAdvisory`, `FolderCatalog`, `PendingEditorScroll`, `ExternalEditConflict`, `ExternalTextComparePayload`. These are likely all structs with Sendable-compatible fields.
2. Mark `SingleSurfaceNoteEditor.Coordinator` and `WikiLinkTextView` as `@MainActor` — they already execute on main; this makes it explicit.
3. Mark `@Sendable` on `ActiveNoteFilePresenter.onChange` closure and `VaultDirectoryWatcher` callback closures.

**Tier 2 — Requires reasoning (medium confidence):**

4. `SlashCommandRegistry` global mutable statics — options:
   - Wrap in an actor (cleanest but changes call sites to async).
   - Use `nonisolated(unsafe)` with documented single-init-site contract.
   - Convert to a `@MainActor` singleton since it's only read from the editor (main thread).
5. `ExtensionRegistry` (`@unchecked Sendable` + `NSLock`) — options:
   - Migrate to actor (preferred if call sites can tolerate `await`).
   - Migrate to `Mutex` (synchronous, Swift 6 safe).
   - Keep `@unchecked Sendable` with documented audit.
6. `VaultDirectoryWatcher` FSEvents bridge — annotate `@MainActor` on the watcher class, ensure `Unmanaged` lifetime aligns.

**Tier 3 — Needs compiler guidance:**

7. Enable `-strict-concurrency=complete` in `Package.swift`:
   ```swift
   .target(
       name: "MiranNotesCore",
       path: "Sources/MiranNotesCore",
       swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
   ),
   ```
8. Build, read diagnostics, fix iteratively. Common findings:
   - `Task { }` closures in `AppModel` capturing `self` — add `@MainActor in` or `[weak self]`.
   - Non-`Sendable` types passed across isolation boundaries — add conformances or restructure.

### Approach

The recommended workflow is: enable strict concurrency warnings (not errors) → fix all warnings → promote to errors → opt into Swift 6 language mode when ready. This is compiler-guided and iterative — each build tells you exactly what to fix next.

### Risk assessment

**Confidence: ~80%.** Mechanical parts (Tier 1) are reliable. Primary risk: if any type in the `NoteDocument` / `EditCommand` / `NoteMetadata` hierarchy contains a reference type or mutable class field, making it `Sendable` becomes non-trivial. The codebase's preference for structs makes this likely straightforward. The `DatabaseRepository` fire-and-forget `Task` pattern (`Task { await doc.insertRow(...) }`) needs ordering review.

---

## Part 4: Migration 3 — TextKit 1 to TextKit 2

### Difficulty: Hard. Structurally achievable, but correctness demands human testing.

### Current TextKit 1 surface area

The editor is contained in **4 files (~1,180 lines total)**:

| File | Lines | TextKit role |
|------|-------|-------------|
| `SingleSurfaceNoteEditor.swift` | 866 | `NSTextView` subclass (`WikiLinkTextView`), `NSViewRepresentable`, `NSTextViewDelegate`, `NSTextStorageDelegate`, popover anchoring |
| `BlockChromeOverlayView.swift` | 91 | Layout-manager glyph geometry for gutter/handle drawing |
| `EditorVisualStyle.swift` | 96 | `NSTextStorage` attribute application (`.font`, `.foregroundColor`) |
| `EditorSyncController.swift` | 129 | `NSTextView` / `textStorage` sync for model → view updates |

**No** `NSLayoutManager` subclass. **No** custom `NSAttributedString.Key`. **No** `NSTextAttachment`. **No** extra `NSTextContainer`. **No** third-party editor (e.g., CodeMirror).

### Glyph-level API usage (hardest to migrate — ~25 lines)

All glyph usage is in two locations:

**`BlockChromeOverlayView.swift` `draw(_:)` (lines 34–60):**
- `textView.layoutManager` → `lm`
- `lm.glyphRange(forCharacterRange:actualCharacterRange:)` → `boundingRect(forGlyphRange:in:)` — maps block character ranges to screen rects for gutter drawing.
- `lm.glyphIndexForCharacter(at:)` → `lineFragmentRect(forGlyphAt:effectiveRange:)` — handles empty blocks.
- `lm.numberOfGlyphs` — bounds clamping.

**`SingleSurfaceNoteEditor.swift` `slashAnchorRect(in:)` (lines 598–600):**
- `lm.glyphRange(forCharacterRange:actualCharacterRange:)` → `boundingRect(forGlyphRange:in:)` — zero-length range at caret for popover positioning.

### TextKit 2 equivalents

| TextKit 1 pattern | TextKit 2 equivalent |
|--------------------|---------------------|
| `layoutManager.glyphRange(forCharacterRange:)` then `boundingRect(forGlyphRange:in:)` | `textLayoutManager.textLayoutFragment(for: location)` then `.layoutFragmentFrame` or enumerate line fragments within |
| `layoutManager.lineFragmentRect(forGlyphAt:effectiveRange:)` | `textLayoutManager.textLayoutFragment(for: location).layoutFragmentFrame` |
| `layoutManager.numberOfGlyphs` | `textLayoutManager.documentRange.endLocation` |
| `textView.layoutManager` access | `textView.textLayoutManager` (TextKit 2 mode); ensure the text view stays in TK2 mode |

### Migration approach

**Phase A — Abstraction boundary (prepare, no behavioral change):**

Extract the two glyph-using sites into a protocol or helper:
```swift
protocol TextGeometryProvider {
    func boundingRect(forCharacterRange range: NSRange) -> CGRect?
    func lineFragmentRect(atCharacterIndex index: Int) -> CGRect?
}
```

Implement for TextKit 1 (current behavior). Wire `BlockChromeOverlayView` and `slashAnchorRect` through this abstraction. **Zero behavioral change.**

**Phase B — TextKit 2 implementation:**

Add a TextKit 2 conformance:
```swift
struct TextKit2GeometryProvider: TextGeometryProvider {
    let textLayoutManager: NSTextLayoutManager
    let textContentStorage: NSTextContentStorage

    func boundingRect(forCharacterRange range: NSRange) -> CGRect? {
        guard let start = textContentStorage.location(
            from: textContentStorage.documentRange.location, offset: range.location
        ) else { return nil }
        guard let fragment = textLayoutManager.textLayoutFragment(for: start) else { return nil }
        return fragment.layoutFragmentFrame
    }
    // ...
}
```

**Phase C — Opt the `NSTextView` into TextKit 2:**

On macOS 14+, `NSTextView` uses TextKit 2 internally but may fall back to TextKit 1 for certain features. The migration needs:
1. Stop accessing `textView.layoutManager` (which forces TextKit 1 fallback).
2. Use `textView.textLayoutManager` instead.
3. Verify the text view stays in TK2 mode during all operations.

**Phase D — Validate `NSTextStorageDelegate` behavior:**

The `textStorage(_:didProcessEditing:)` pipeline (`SingleSurfaceNoteEditor.swift` lines 434–486) is the core typing path. TextKit 2 changes layout invalidation timing. Key validation points:
- IME guard (`hasMarkedText()`) still works.
- `isApplyingModelUpdate` reentrancy guard still prevents feedback loops.
- Attribute application in `EditorVisualStyle` fires at the correct time relative to layout.

**Phase E — Test matrix:**
- Basic typing, delete, selection.
- Block split/merge (newline at various positions).
- Slash command menu popover positioning.
- Block chrome overlay alignment.
- Bold/italic/code span toggle.
- Wiki link click hit-testing.
- IME composition (Japanese, Korean, Chinese input methods).
- Large notes (~1 MB) scrolling and editing.
- Window resize while editing.
- Dark mode / font size changes.

### What makes this tractable

- **Small glyph surface:** Only ~25 lines use glyph-level APIs. Most of the 1,180 editor lines are `NSTextView` standard APIs (selection, string access, delegate methods) that work identically under both TextKit stacks.
- **No custom attributes or attachments:** Styling uses only `.font` and `.foregroundColor`. No custom layout manager subclass.
- **Single text view, single container:** No multi-column or non-contiguous layout.

### What makes this risky

- **TextKit 2 is under-documented.** Fewer battle-tested examples in the ecosystem compared to TextKit 1. Edge cases around coordinate mapping, line fragment enumeration, and IME integration are not comprehensively documented by Apple.
- **`NSTextStorageDelegate` timing.** Layout invalidation under TextKit 2 differs from TextKit 1. The delegate callback order and the state of the layout system at the time `didProcessEditing` fires may differ.
- **Coordinate precision.** `layoutFragmentFrame` is coarser than `boundingRect(forGlyphRange:)` — fragments represent entire paragraphs, not glyph runs. For sub-paragraph precision (e.g., popover anchoring at a specific character), you need `NSTextLineFragment` within the layout fragment.
- **Fallback behavior.** Accessing `textView.layoutManager` forces the text view back to TextKit 1. Any code path that accidentally touches the old API undoes the migration.

### Risk assessment

**Confidence: ~55–65%.** An AI agent can produce a structurally correct first draft. The abstraction boundary (Phase A) and TextKit 2 implementation (Phase B) are well within capability. The behavioral validation (Phases C–E) requires on-device testing because TextKit 2's rendering/interaction quirks are not fully captured in documentation. Plan for 2–4 rounds of "AI writes fix, human tests on device."

---

## Part 5: Priority and Sequencing

### Recommended order

1. **ObservableObject → @Observable** (1 session, minimal risk)
   - Smallest change, highest confidence, immediate benefit.
   - Aligns the codebase with Apple's current direction before SwiftUI features start requiring it.

2. **Swift 6 strict concurrency** (2–3 sessions, compiler-guided)
   - Enable warnings first, fix iteratively.
   - Doing this second means `@Observable` is already in place (one less migration in flight).
   - The compiler tells you exactly what to fix — no guesswork.

3. **TextKit 1 → TextKit 2** (3–5 sessions, test-intensive)
   - Largest risk, longest tail of validation.
   - Start with the abstraction boundary (Phase A) which has zero behavioral change.
   - Phase B–E can be incremental and tested in isolation.
   - Defer until a concrete need arises (Apple deprecation signal, a TK2-only feature you want, or a rendering bug Apple won't fix in TK1).

### Total estimated effort

| Migration | Sessions | Lines changed (est.) | Test changes |
|-----------|----------|---------------------|-------------|
| @Observable | 1 | ~80 | 0 |
| Swift 6 concurrency | 2–3 | ~200–400 | ~50 (add `@MainActor`, fix warnings) |
| TextKit 2 | 3–5 | ~300–500 | ~100 (new geometry tests, QA matrix) |

---

## Part 6: Files Referenced

### Editor (TextKit migration scope)
- `Sources/MiranNotesApp/Features/Editor/SingleSurfaceNoteEditor.swift` — 866 lines, entire editor surface
- `Sources/MiranNotesApp/Features/Editor/BlockChromeOverlayView.swift` — 91 lines, glyph geometry for chrome
- `Sources/MiranNotesApp/Features/Editor/EditorVisualStyle.swift` — 96 lines, `NSTextStorage` attributes
- `Sources/MiranNotesApp/Features/Editor/EditorSyncController.swift` — 129 lines, model → view sync

### State (@Observable migration scope)
- `Sources/MiranNotesApp/App/AppModel.swift` — 20 `@Published` properties
- `Sources/MiranNotesApp/App/MiranNotesApp.swift` — `@StateObject`, binding sites
- `Sources/MiranNotesApp/Features/NotesList/NotesListView.swift` — 2× `@ObservedObject`
- `Sources/MiranNotesApp/Features/Layout/TiledEditorView.swift` — 2× `@ObservedObject`
- `Sources/MiranNotesApp/Features/Layout/LayoutSelectorView.swift` — 1× `@ObservedObject`

### Concurrency (Swift 6 migration scope)
- All 7 actor files under `Sources/MiranNotesApp/Data/`
- `Sources/MiranNotesCore/ExtensionRegistry.swift` — `@unchecked Sendable`
- `Sources/MiranNotesApp/Features/Editor/SlashCommandRegistry.swift` — global mutable statics
- `Sources/MiranNotesApp/Data/VaultDirectoryWatcher.swift` — FSEvents + GCD bridge
- `Sources/MiranNotesApp/Data/ActiveNoteFilePresenter.swift` — `NSFilePresenter` delegate
- Core model types in `Sources/MiranNotesCore/` — need `Sendable` audit

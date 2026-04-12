# Slash Command Framework

This document defines the long-term pattern for adding slash-driven components in Miran Notes.

## Goals

- Keep command behavior deterministic and easy to reason about.
- Make new commands additive (register + tests) instead of invasive editor rewrites.
- Preserve metadata integrity (`blocks`, `spans`, `links`) after every command batch.
- Support both slash tokens and lightweight markdown-style triggers through one framework.

## Current UX Contract (Discovery + Execution)

Slash commands are now discoverable and keyboard-first in the shipping editor.

- Typing `/` opens a command menu anchored near the caret.
- Querying is live: `/`, `/h`, `/bul`, etc. filter results dynamically.
- Selection controls:
  - Up/Down: move highlight
  - Enter/Tab: execute highlighted command
  - Esc: close menu and keep text unchanged
- No-match behavior:
  - Unknown tokens (for example `/doesntwork`) remain plain text.
  - Menu remains visible with `No commands found` while query context is active.
  - Enter without a selectable command falls back to normal editor behavior.

### Discovery Components

- `SlashQueryDetector`: extracts in-progress slash query ranges from editor text/caret state.
- `SlashCommandMatcher`: ranks matches (prefix > alias > keyword/title contains).
- `SlashCommandRegistry` catalog metadata: `id`, `aliases`, `title`, `keywords`, `category`, `preview`.
- `SingleSurfaceNoteEditor` coordinator: owns slash menu state, keyboard routing, and command application.

## Pipeline Contract

Slash-driven transformations flow through four explicit layers:

1. Detection
2. Registration
3. Execution
4. Validation

```mermaid
flowchart TD
    keystroke[KeystrokeInNSTextView] --> preEdit[PreEditGate]
    preEdit -->|trigger_candidate| detection[TriggerDetection]
    preEdit -->|no_candidate| structural[StructuralLayoutRules]
    detection --> registration[CommandRegistration]
    registration --> execution[EditCommandBatch]
    structural --> execution
    execution --> appModel[AppModelApply]
    appModel --> engine[EditCommandEngine]
    engine --> validation[NoteIntegrityValidation]
    validation --> render[EditorVisualRefresh]
```

### 1) Detection Layer

Responsibility:
- Read editor deltas and identify whether an edit is a known trigger.
- Produce a normalized invocation payload that is independent of UI widgets.

Rules:
- Trigger detection must be pure and side-effect free.
- If detection is ambiguous, return `nil` and allow normal text replacement.
- Detection is only allowed to read current document text, insertion diff, and block location.

Current trigger families:
- Slash query (`/token` while typing, for discovery).
- Slash commit (`/token` committed with space/newline, backward-compatible path).
- Markdown bullet trigger (`- ` at line start).

### 2) Registration Layer

Responsibility:
- Map invocation IDs and aliases to a command producer.
- Resolve precedence deterministically.

Required descriptor fields:
- `id`: canonical identifier (`list`, `heading1`, etc).
- `aliases`: alternate tokens (`bullet` for list).
- `commitPolicy`: accepted commit characters.
- `applicability`: optional block-type constraints.
- `produce`: pure function returning `[EditCommand]?`.

Rules:
- Registry order must be stable and explicit.
- No command may mutate editor state directly; only emit `EditCommand`s.
- Unsupported tokens return `nil` instead of partial behavior.
- **Open registration:** `SlashCommandRegistry.register(_ descriptor: SlashCommandDescriptor)` accepts external descriptors idempotently (duplicate `id`s are silently ignored). All built-in descriptors are registered via `SlashCommandRegistry.registerBuiltins()`, called once at app startup in `MiranNotesApp.init`. Feature modules or plugins may call `register(_:)` at any point thereafter without touching built-in arrays.

### 3) Execution Layer

Responsibility:
- Apply produced batches through `AppModel.apply`.
- Keep model mutation centralized in `EditCommandEngine`.

Rules:
- Handlers emit minimal, ordered command batches.
- Batches should be atomic from the user’s perspective.
- Prefer existing command primitives (`replaceText`, `changeBlockType`, `splitBlock`, `mergeWithPrevious`).

### 4) Validation Layer

Responsibility:
- Guarantee document invariants after command application.

Safety checks:
- Block partition remains sorted and contiguous over text.
- Span and link ranges remain bounded and non-overlapping with invalid regions.
- Batch size respects command pipeline contract.

Fallback:
- When detector or producer cannot confidently transform, fall back to plain text replacement path.
- Discovery no-match is not an error state; it is an explicit UI state that does not mutate content.

## Structural Rule Interactions

`DocumentLayoutController` owns Enter/Backspace structural behavior. Trigger transformations and structural rules must not conflict:

- Trigger transforms run only when exact trigger predicates pass.
- Otherwise, structural rules own the event.
- List-specific Enter behavior is defined as a structural rule, not a slash producer.

This separation keeps command registration focused on mode activation while keeping editing semantics centralized.

## Command Authoring Template

For each new command:

1. Create a `SlashCommandDescriptor` with `id`, `aliases`, and `produce` closure.
2. Fill descriptor metadata for discovery (`title`, `category`, `keywords`, `preview`).
3. Ensure producer emits only `EditCommand`s — no direct editor state mutation.
4. Register via `SlashCommandRegistry.register(descriptor)`. For built-ins, add the call inside `registerBuiltins()`. For plugin commands, call `register` at module init.
5. Add detector/query tests for positive and negative paths.
6. Add matcher tests (ranking + alias coverage).
7. Add structural tests if command changes Enter/Backspace behavior.
8. Add regression tests for metadata integrity.

## Reliability Checklist (Required for PRs)

- Command has at least one positive detector test.
- Command has at least one negative detector test.
- Command has discovery coverage (query extraction + matcher behavior).
- Command behavior is deterministic for ambiguous input.
- Command batch preserves undo semantics and does not bypass `AppModel.apply`.
- No integrity regressions in note metadata tests.

## Extension Guidance

Use this same pattern for future interactive components:
- Checkboxes
- Table embeds
- Bullets and numbered lists
- Callouts and dividers

If a feature needs custom UI behavior, keep the activation in trigger/registry and route model mutations through command batches to avoid hidden side effects.

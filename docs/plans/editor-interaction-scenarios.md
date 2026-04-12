# Editor interaction scenarios (manual QA)

Checklist for the single-surface `NSTextView` editor. Automated coverage lives in `Tests/MiranNotesTests/` (`EditorInteractionEngineTests`, regression suites). **Expected:** `NoteIntegrity` holds; no cursor jumps or lost formatting in normal use; IME composition is not torn down mid-sequence.

## Typing and backspace

| Scenario | Expected outcome |
|----------|------------------|
| Insert/delete single characters | Model stays in sync; incremental UTF-16 diff path |
| Delete across a bold/italic/code span | Spans adjusted; metadata valid |
| Backspace at start of block (not first block), previous char is newline | Merge blocks + delete newline; single undo step |
| Empty list item + Enter | Block becomes paragraph (no stray list marker) |

## Block boundaries

| Scenario | Expected outcome |
|----------|------------------|
| Enter mid-paragraph | Newline + `splitBlock`; two blocks; types preserved where applicable |
| Enter at boundary between two blocks | Insert newline only (no duplicate block starts) |
| Paste or edit that cannot be one UTF-16 region | Full-buffer path; user sees advisory; reconciled block types applied when recoverable |

## Spans (bold / italic / code)

| Scenario | Expected outcome |
|----------|------------------|
| Toggle style on selection | Span added or removed; `EditorVisualStyle` updates immediately |
| Toggle same range again | Span removed (toggle off) |
| Overlapping spans (e.g. bold + italic) | Fonts compose; integrity maintained |

## Wiki links and callouts

| Scenario | Expected outcome |
|----------|------------------|
| Insert wiki link | `[[token]]` text + link metadata; link color applied |
| Edit inside `[[...]]` | Link range adjusts; navigation still works when valid |
| Callout block + newline split | Child blocks remain callouts where engine defines; integrity OK |

## IME (input methods)

| Scenario | Expected outcome |
|----------|------------------|
| Composing (marked text) | No model sync from storage edits; no model→view buffer overwrite in `applyDocumentText` |
| Formatting shortcuts while composing | No-op (does not clear composition) |

## Large notes (≈ 1 MB UTF-16)

| Scenario | Expected outcome |
|----------|------------------|
| Typing near cap | Insert rejected at limit; user notice |
| Edits below cap on large buffer | Incremental replace when possible; integrity holds |

## Related code

- Pipeline: `SingleSurfaceNoteEditor`, `TextEditDiff`, `DocumentLayoutController`, `EditCommandEngine`
- Constraints: [Constraints.md](../../Constraints.md) (editor representation, view sync)

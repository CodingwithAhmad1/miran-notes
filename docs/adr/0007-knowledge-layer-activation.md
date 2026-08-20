# ADR 0007: Knowledge layer activation (wiki links UI, backlinks panel, full-text search)

## Status

Accepted (2026-08-20).

## Context

ADR 0001 gave every note a persistent `noteID` and `[[Display Title]]` links with UTF-16 ranges in the sidecar. The full engine — `EditCommand.insertWikiLink`, `LinkGraph`, `LinkResolver`, `RelationshipIndex`, `WikiLinkSyntaxReconciler`, per-pane backlink computation, and a background body-text search index — shipped and stayed active, but the UI was deliberately dark: `WikiLinkPresentationPolicy.isFrontendEnabled` was hardcoded `false`, no view rendered backlinks, and search matched titles/paths only while the body index went unread.

The product direction settled in Aug 2026: connected ideas are the differentiator; the knowledge layer turns on.

## Decision

1. **Presentation policy becomes a preference.** `WikiLinkPresentationPolicy` reads UserDefaults-backed `AppSettings` toggles (`wikiLinkNavigationEnabled`, `wikiLinkAutocompleteEnabled`), both default **true**. The policy affects styling, click routing, and the autocomplete popover only — never persisted link data.
2. **`[[` autocomplete.** A new `WikiLinkQueryDetector` matches an unclosed `[[` before the caret **anywhere in a line** (slash discovery stays line-start-only per its non-regression contract). A shared `WikiLinkMenuController` hosts the caret-anchored popover in both editor backends with the slash menu's keyboard contract. Ranking: exact title > title prefix > title substring > path substring, capped at 8, current note excluded; a "Create '<query>'" row appears when the query matches no title exactly and the current folder accepts notes.
3. **Commit semantics differ per backend, by design.** The block editor commits one atomic batch — `replaceText` (remove `[[query`) + `insertWikiLink` — producing linked text and metadata in one undo step. The markdown source editor commits plain `[[Title]]` text and lets `WikiLinkSyntaxReconciler` derive the link at save, keeping the md pipeline dumb and identical to external edits. `.md` stays a second-class source-mode format: no block-parity markdown parsing.
4. **Backlinks panel.** A collapsible "Linked mentions (n)" strip under the editor renders `WorkspacePaneSession.backlinks`; rows navigate via the existing `openBacklinkSource` (scroll-to-link included). Hidden when there are no backlinks or link presentation is off.
5. **Full-text search.** Vault search matches title, path, **and body** (ranked in that order) via the existing background `bodySearchIndex`; autosave patches the saved note's entry so results don't lag edits by a full rebuild. Search results show body snippets (`SearchSnippetBuilder`).
6. **Dangling targets** alert on click ("note isn't in this vault anymore") — consistent with the semantic-reconciliation stance: surface, don't repair.

## Consequences

- The differentiating feature set is finally user-visible; no on-disk format changed.
- Toggling presentation off restores the previous dark state without touching data.
- The autocomplete popover restyles only on document change; toggling settings mid-session may need a note reopen to fully apply styling.

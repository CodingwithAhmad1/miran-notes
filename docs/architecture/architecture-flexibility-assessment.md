# Miran Notes: Architecture, Flexibility, and Product Fit Assessment

> **Superseded (Apr 2026):** This assessment was produced during an earlier phase. Its recommendations (hardening boundaries, performance budgets, conflict/repair UX, schema lifecycle) have been substantially implemented — see [Constraints.md](../../Constraints.md), the [engineering brief](../investor-and-engineering-brief.md), and completed plans in [plans/README.md](../plans/README.md). Retained for historical context.

## Purpose

This document evaluates Miran Notes from two lenses:

- **User lens**: does it feel fast, clear, and trustworthy like Notion/Obsidian without heavy memory use?
- **Technical lens**: is the architecture clear, resilient, and flexible enough to pivot and extend comfortably?

---

## Executive View

Miran Notes is in a strong architectural position for a local-first editor:

- Clear separation between **editing commands**, **document model**, and **disk persistence**.
- Good correctness bias via integrity normalization, conflict detection, and now revision-aware checks.
- A path toward extensibility has started (extension registry + commit participants), which is the right direction.

The biggest opportunity now is not a rewrite; it is **hardening boundaries and contracts** so growth remains simple:

1. Stabilize extension/plugin contracts.
2. Add performance budgets and telemetry-based optimization.
3. Improve user-visible conflict/repair workflows.
4. Formalize schema and migration lifecycle as first-class product behavior.

---

## Perspective 1: User Experience (Product Lens)

## What users will already feel positively

- **Fast local editing** without server dependency.
- **Reliable autosave and conflict prompts** instead of silent data loss.
- **Rich note behaviors** (block semantics, slash commands, links) with a lightweight footprint.
- **Human-readable files** that feel future-safe.

## Where users may still feel friction

- Occasional ambiguity in repair/conflict cases can feel technical.
- Larger notes can eventually expose undo-memory tradeoffs.
- Some “Notion feel” polish (micro-interactions, structural affordances, discoverability) still depends on UI refinement, not just backend correctness.

## User-facing priorities

1. **Repair/Conflict UX polish**: clearer language, safer defaults, one-click guided resolution.
2. **Performance confidence**: predictable behavior on large notes and vaults.
3. **Discoverability**: command palette/slash discoverability and block-level affordances.

---

## Perspective 2: Technical Architecture (Engineering Lens)

## Current architecture strengths

- **Command-based core**: `EditCommandEngine` keeps mutation semantics centralized.
- **Model integrity discipline**: normalization/integrity checks provide robust guardrails.
- **Persistence structure**: sidecar metadata and link graph maintain explicit semantics.
- **Separation of concerns**: editor surface, app model, repository, and core model are mostly cleanly separated.
- **Recent upgrades**:
  - `VaultCommit` participant-based write orchestration.
  - `DocumentRevisionToken` for stronger external-change identity.
  - `CommandSession` style unification at editor ingress.
  - Early runtime extension contracts (`ExtensionRegistry`).

## Architectural risks to manage

- Multi-file persistence is improved but still not a full transactional DB; failure semantics must remain explicit.
- Extension system is present but still early; contract instability could create plugin churn.
- Undo memory policy exists, but tuning needs empirical thresholds and user-informed behavior.
- Notion-like feature growth can cause accidental coupling unless registry/capability patterns are consistently enforced.

---

## Expandability and Pivot Readiness

## What makes pivots feasible now

- Local-first file model and sidecars avoid vendor lock-in.
- Command engine allows introducing new structural actions without replacing the editor.
- Extension and commit participant abstractions create room for future modules (tables, sync adapters, indexing).

## What is needed to make pivots comfortable

1. **Versioned capability contracts**
  - Freeze extension interfaces with semver-like compatibility rules.
  - Add capability negotiation for optional features.
2. **Schema evolution discipline**
  - Define migration strategy per schema change (forward/backward compatibility, rollback, repair behavior).
3. **Compatibility test matrix**
  - Contract tests for extension points, persistence participants, and migration paths.
4. **Operational observability**
  - Promote telemetry to decision-making: repair frequency, conflict rate, autosave latency, large-note cost.

---

## RAM-Light, Notion/Obsidian-Like Strategy

To keep a polished feel without becoming memory-heavy, prioritize these principles:

1. **Incremental over full recompute**
  - Incremental parsing/index updates instead of full vault scans.
2. **Bounded in-memory state**
  - Cap undo and cache sizes with predictable eviction policies.
3. **Lazy materialization**
  - Load/render details only when visible or needed (especially large documents/artifacts).
4. **Background indexing queues**
  - Keep UI thread focused on interaction; move heavy graph/index work off the hot path.
5. **Performance budgets as product constraints**
  - Treat latency and memory targets as non-negotiable acceptance criteria.

---

## What to Do Next (Prioritized)

## Phase 1: Product trust and stability

- Improve conflict/repair UI copy and guided flows.
- Add explicit diagnostics surface for “why this happened” in external edits and repairs.
- Validate behavior with stress tests (large docs, frequent external edits, rapid note switching).

## Phase 2: Extension maturity

- Version and document extension contracts (commands, interceptors, artifact providers).
- Add compatibility tests for extension registry and participant ordering rules.
- Define safe failure behavior when extensions fail (degrade gracefully, never corrupt notes).

## Phase 3: Performance and scalability

- Add benchmark suite: typing latency, save latency, vault load, memory under deep undo.
- Introduce budgets and automated regression checks in CI.
- Move expensive maintenance (full graph rebuilds, large reconciliations) to controlled background jobs.

## Phase 4: Feature velocity without coupling

- Enforce module boundaries (UI/editor/core/data).
- Require new features to declare:
  - storage impact,
  - migration path,
  - extension impact,
  - performance impact.

---

## Clarity Scorecard (Current)

- **Architecture clarity**: High and improving.
- **Expandability**: Medium-high; strong direction, contracts still maturing.
- **Flexibility/pivotability**: High for local-first evolution, medium for plugin ecosystem maturity.
- **User trust posture**: High for data safety intent; medium-high for repair/conflict experience polish.
- **RAM efficiency posture**: Promising, but needs explicit budgets + continuous benchmarking.

---

## Bottom Line

You are on the right path for a **lightweight, flexible, local-first editor** that can feel like Notion/Obsidian without inheriting their heavy runtime profile.  
The main requirement now is disciplined maturation: **contract stability, performance budgets, and user-facing recovery clarity**. If those are prioritized, Miran Notes can scale in capability while staying lean and understandable.
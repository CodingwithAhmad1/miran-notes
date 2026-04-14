# Performance tests (CI)

Backlog context: [§5 Performance in the quality dimensions roadmap](../plans/quality-dimensions-roadmap.md).

## Edit engine — statistical median

[`EditEnginePerformanceStatisticalTests`](../../Tests/MiranNotesTests/EditEnginePerformanceStatisticalTests.swift) runs repeated batches of sequential `replaceText` operations on a medium-sized document and asserts the **median** wall-clock time stays below a loose threshold (intended to catch large regressions, not micro-optimizations).

- Runs under `swift test` with the `MiranNotesTests` target (core package).
- **Local dev:** 10 outer iterations, median must stay **below 0.35s**.
- **CI** (`CI` environment variable set, e.g. GitHub Actions): **21** outer iterations for a stabler median, ceiling **0.48s** (shared runners vary more than developer laptops).
- Tweak counts or thresholds only when changing editor hot paths or CI machine class; keep CI looser than local to limit false reds.

## Other performance tests

[`EditEnginePerformanceTests`](../../Tests/MiranNotesTests/EditEnginePerformanceTests.swift) holds additional non-statistical checks where useful.

## Full-stack (app) profiling

Isolated core benchmarks do not measure **perceived** performance (TextKit, SwiftUI layout, and shell chrome). Use this checklist to record baselines for the real app, separate from `MiranNotesTests`.

### Prerequisites

- Prefer a **Release** build (or `swift run`/archive configuration closest to what users run).
- Note the **machine class** (chip, RAM) and **macOS build**; record the **git commit**.
- Use a vault with at least one note at or near the **1 MB (UTF-16)** editor cap (see root [README.md](../../README.md) and [Constraints.md](../../Constraints.md)).

### Checklist

1. **Cold vs warm:** Decide whether the run is cold launch (process not in memory) or warm; record which.
2. **Time-to-interactive:** Time until the shell is usable (sidebar responsive, editor can take focus) after launch into the test vault.
3. **First keystroke latency:** After open (or after selecting the large note), time until the first typed character appears with acceptable responsiveness.
4. **Save latency:** After editing the large note, time until autosave (or explicit save, if you use one) completes without blocking the UI.

### Optional: Instruments

- **Time Profiler** for main-thread hot spots during launch, search, and save.
- **Points of Interest** (if you add `os_signpost` later) to bracket vault load, index build, and save.

### Baseline table (fill when measured)

| Date | Commit | Machine | Cold/warm | TTI (s) | First keystroke (s) | Save latency (s) | Notes |
|------|--------|---------|-----------|---------|---------------------|------------------|-------|
| TBD | | | | | | | |

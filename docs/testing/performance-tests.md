# Performance tests (CI)

## Edit engine — statistical median

[`EditEnginePerformanceStatisticalTests`](../../Tests/MiranNotesTests/EditEnginePerformanceStatisticalTests.swift) runs repeated batches of sequential `replaceText` operations on a medium-sized document and asserts the **median** wall-clock time stays below a loose threshold (intended to catch large regressions, not micro-optimizations).

- Runs under `swift test` with the `MiranNotesTests` target (core package).
- Tweak the iteration counts or threshold only when changing editor hot paths or CI machine class.

## Other performance tests

[`EditEnginePerformanceTests`](../../Tests/MiranNotesTests/EditEnginePerformanceTests.swift) holds additional non-statistical checks where useful.

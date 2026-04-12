import Foundation

struct UndoPolicy {
    /// Maximum number of undo steps to keep. When exceeded, the oldest entries are pruned.
    let maxUndoSteps: Int

    /// Monotonic-time window for merging consecutive single-`replaceText` steps. `0` disables coalescing.
    let coalesceReplaceTextWindowNanoseconds: UInt64

    static let defaultPolicy = UndoPolicy(
        maxUndoSteps: 200,
        coalesceReplaceTextWindowNanoseconds: 300_000_000
    )
}

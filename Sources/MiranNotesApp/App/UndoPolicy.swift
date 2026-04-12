import Foundation

struct UndoPolicy {
    /// Maximum number of undo steps to keep. When exceeded, the oldest entries are pruned.
    let maxUndoSteps: Int

    static let defaultPolicy = UndoPolicy(maxUndoSteps: 200)
}

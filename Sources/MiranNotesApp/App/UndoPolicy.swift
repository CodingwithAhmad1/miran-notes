import Foundation

struct UndoPolicy {
    let maxApproxBytes: Int

    static let defaultPolicy = UndoPolicy(
        maxApproxBytes: 8 * 1024 * 1024
    )
}

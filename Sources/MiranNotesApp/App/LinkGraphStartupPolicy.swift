import Foundation

/// Pure policy for whether link-graph sync runs inline at vault startup or is deferred (large vaults).
enum LinkGraphStartupPolicy {
    enum SyncMode: Equatable {
        case immediate
        case deferred
    }

    struct Decision: Equatable {
        var mode: SyncMode
        var reason: String
    }

    nonisolated static func decision(
        noteCount: Int,
        noteLinkRelationshipCount: Int,
        hardThreshold: Int,
        historicalAverageMs: Double?,
        budgetMs: Double
    ) -> Decision {
        if noteCount > hardThreshold {
            return Decision(
                mode: .deferred,
                reason: "noteCount>\(hardThreshold)"
            )
        }
        if noteLinkRelationshipCount > hardThreshold * 5 {
            return Decision(
                mode: .deferred,
                reason: "relationshipCountHigh"
            )
        }
        if let historicalAverageMs, historicalAverageMs > budgetMs {
            return Decision(
                mode: .deferred,
                reason: "historicalAverageOverBudget"
            )
        }
        return Decision(mode: .immediate, reason: "withinBudget")
    }
}

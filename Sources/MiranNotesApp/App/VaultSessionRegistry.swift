import Foundation
import Observation

/// Tracks how many vault-backed window sessions are active (for global toolbar affordances).
@MainActor
@Observable
final class VaultSessionRegistry {
    private(set) var openVaultSessionCount: Int = 0

    var hasAnyVaultSession: Bool { openVaultSessionCount > 0 }

    func registerSession() {
        openVaultSessionCount += 1
    }

    func unregisterSession() {
        openVaultSessionCount = max(0, openVaultSessionCount - 1)
    }
}

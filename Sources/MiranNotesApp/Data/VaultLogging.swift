import os.log

extension Logger {
    static let vault = Logger(subsystem: "app.miran.notes", category: "Vault")
    static let editEngine = Logger(subsystem: "app.miran.notes", category: "EditEngine")
}

enum VaultTelemetry {
    static func logRepairWarnings(count: Int) {
        Logger.vault.info("repairWarnings count=\(count, privacy: .public)")
    }

    static func logConflictDetected(isDirty: Bool, hasRevisionToken: Bool) {
        Logger.vault.info(
            "externalConflict isDirty=\(isDirty, privacy: .public) hasRevision=\(hasRevisionToken, privacy: .public)"
        )
    }

    static func logAutosave(latencyMs: Int) {
        Logger.vault.debug("autosave latencyMs=\(latencyMs, privacy: .public)")
    }

    static func logManifestReconcile(removed: Int, added: Int) {
        Logger.vault.debug("manifestReconcile removed=\(removed, privacy: .public) added=\(added, privacy: .public)")
    }
}

import Foundation

/// Persists whether the user has left the one-time vault welcome (per vault, under `.miran/`).
enum VaultWelcomeDismissalStore {
    static func markerURL(vaultURL: URL) -> URL {
        VaultPaths.miranDirectory(vaultURL: vaultURL)
            .appendingPathComponent(VaultPaths.vaultWelcomeDismissedFileName, isDirectory: false)
    }

    static func isDismissed(vaultURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: markerURL(vaultURL: vaultURL).path)
    }

    static func markDismissed(vaultURL: URL) throws {
        let miran = VaultPaths.miranDirectory(vaultURL: vaultURL)
        try FileManager.default.createDirectory(at: miran, withIntermediateDirectories: true)
        let url = markerURL(vaultURL: vaultURL)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try Data().write(to: url, options: .atomic)
    }
}

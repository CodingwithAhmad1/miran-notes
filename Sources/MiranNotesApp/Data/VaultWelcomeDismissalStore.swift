import CryptoKit
import Foundation

/// Persists whether the user has left the one-time vault welcome (per vault), without writing into the vault by default.
enum VaultWelcomeDismissalStore {
    private static let userDefaultsKeyPrefix = "MiranNotes.vaultWelcomeDismissed."

    static func markerURL(vaultURL: URL) -> URL {
        VaultPaths.miranDirectory(vaultURL: vaultURL)
            .appendingPathComponent(VaultPaths.vaultWelcomeDismissedFileName, isDirectory: false)
    }

    private static func userDefaultsKey(for vaultURL: URL) -> String {
        let path = vaultURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return userDefaultsKeyPrefix + hex
    }

    static func isDismissed(vaultURL: URL) -> Bool {
        if UserDefaults.standard.bool(forKey: userDefaultsKey(for: vaultURL)) {
            return true
        }
        return FileManager.default.fileExists(atPath: markerURL(vaultURL: vaultURL).path)
    }

    static func markDismissed(vaultURL: URL) throws {
        UserDefaults.standard.set(true, forKey: userDefaultsKey(for: vaultURL))
    }
}

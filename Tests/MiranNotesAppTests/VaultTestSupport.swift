import Foundation

enum VaultTestSupport {
    /// Creates an on-disk directory suitable as an empty vault root (workspace scan returns `.empty`).
    static func makeEmptyVaultDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiranVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

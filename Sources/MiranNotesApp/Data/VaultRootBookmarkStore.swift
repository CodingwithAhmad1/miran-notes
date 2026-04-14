import Foundation

enum VaultRootBookmarkError: Error {
    case applicationSupportUnavailable
}

/// Vault-root bookmark file on disk. **Production** does not read or write it (legacy file is removed on launch); **unit tests** redirect the path via ``setBookmarkFileURLForTesting``. Separate from ``ExternalBookmarkStore`` (wiki targets).
enum VaultRootBookmarkStore {
    private static let appFolderName = "MiranNotes"
    private static let bookmarkFileName = "vault-root.bookmark"

    /// For unit tests only; clears when set to `nil`.
    private nonisolated(unsafe) static var bookmarkFileURLOverride: URL?

    static func setBookmarkFileURLForTesting(_ url: URL?) {
        bookmarkFileURLOverride = url
    }

    /// When `true`, bookmark I/O uses a test path and ``VaultWorkspaceAccess`` persists/restores the vault root bookmark for tests only.
    internal static var isBookmarkFileRedirectedForTesting: Bool {
        bookmarkFileURLOverride != nil
    }

    static func bookmarkFileURL() throws -> URL {
        if let override = bookmarkFileURLOverride {
            return override
        }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw VaultRootBookmarkError.applicationSupportUnavailable
        }
        let dir = base.appendingPathComponent(appFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(bookmarkFileName, isDirectory: false)
    }

    static func loadBookmarkData() -> Data? {
        guard let url = try? bookmarkFileURL(),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func saveBookmarkData(_ data: Data) throws {
        let url = try bookmarkFileURL()
        try data.write(to: url, options: .atomic)
    }

    static func clearBookmarkData() {
        guard let url = try? bookmarkFileURL(),
              FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

import Foundation

enum VaultRootBookmarkError: Error {
    case applicationSupportUnavailable
}

/// Persists **vault root** security bookmarks outside the vault (Application Support). Separate from ``ExternalBookmarkStore`` (wiki targets).
enum VaultRootBookmarkStore {
    private static let appFolderName = "MiranNotes"
    private static let bookmarkFileName = "vault-root.bookmark"

    /// For unit tests only; clears when set to `nil`.
    private nonisolated(unsafe) static var bookmarkFileURLOverride: URL?

    static func setBookmarkFileURLForTesting(_ url: URL?) {
        bookmarkFileURLOverride = url
    }

    /// When `true`, bookmark I/O uses a test path; callers may skip production-only bootstrap rules (e.g. rejecting vaults under the temp directory).
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

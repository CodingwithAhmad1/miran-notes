import AppKit
import Foundation

extension CompatibilityIssue {
    /// Absolute URL for the reported item under `vaultRoot`, or `nil` when the issue has no path.
    func resolvedItemURL(vaultRoot: URL) -> URL? {
        guard let rel = path else { return nil }
        let root = vaultRoot.standardizedFileURL
        if rel.posixPath == "." {
            return root
        }
        return root.appendingPathComponent(rel.posixPath)
    }

    /// Whether the item exists on disk and can be revealed in Finder.
    func canRevealInFinder(vaultRoot: URL) -> Bool {
        guard let url = resolvedItemURL(vaultRoot: vaultRoot) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func revealInFinder(vaultRoot: URL) {
        guard let url = resolvedItemURL(vaultRoot: vaultRoot) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

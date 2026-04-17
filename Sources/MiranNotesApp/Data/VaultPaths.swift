import Foundation
import MiranNotesCore

enum VaultPaths {
    static let miranDirName = ".miran"
    static let manifestFileName = "manifest.json"
    static let linkGraphFileName = "link-graph.json"
    static let relationshipIndexFileName = "relationship-index.json"
    static let folderCatalogFileName = "folder-catalog.json"
    static let pathIndexFileName = "path-index.json"
    /// Maps folder IDs to preferred note body extension before the first note exists in that folder.
    static let folderNoteBodyConventionFileName = "folder-note-body-convention.json"
    static let externalBookmarksFileName = "external-bookmarks.json"
    /// Legacy single-file Today’s Tasks payload (migrated to per-day files when absent index).
    static let todaysTasksFileName = "todays-tasks.json"
    static let todaysTasksIndexFileName = "todays-tasks-index.json"
    static let todaysTasksDaysDirectoryName = "todays-tasks-days"
    /// Marker file: user completed the one-time vault welcome (detail pane); stored under `.miran/`.
    static let vaultWelcomeDismissedFileName = "vault-welcome-dismissed"
    static let auxDirName = "_aux"

    static func miranDirectory(vaultURL: URL) -> URL {
        vaultURL.appendingPathComponent(miranDirName, isDirectory: true)
    }

    /// In-flight vault commits (temp payloads + `vault-commit.json`). Same volume as the vault for atomic renames.
    static func pendingCommitsDirectory(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent("pending-commits", isDirectory: true)
    }

    static func manifestURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(manifestFileName, isDirectory: false)
    }

    static func linkGraphURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(linkGraphFileName, isDirectory: false)
    }

    static func relationshipIndexURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(relationshipIndexFileName, isDirectory: false)
    }

    static func folderCatalogURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(folderCatalogFileName, isDirectory: false)
    }

    static func pathIndexURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(pathIndexFileName, isDirectory: false)
    }

    static func folderNoteBodyConventionURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(folderNoteBodyConventionFileName, isDirectory: false)
    }

    static func externalBookmarksURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(externalBookmarksFileName, isDirectory: false)
    }

    static func todaysTasksURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(todaysTasksFileName, isDirectory: false)
    }

    static func todaysTasksIndexURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(todaysTasksIndexFileName, isDirectory: false)
    }

    static func todaysTasksDaysDirectory(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(todaysTasksDaysDirectoryName, isDirectory: true)
    }

    static func todaysTasksDayFileURL(vaultURL: URL, dayStorageKey: String) -> URL {
        todaysTasksDaysDirectory(vaultURL: vaultURL).appendingPathComponent("\(dayStorageKey).json", isDirectory: false)
    }

    /// `{vault}/_aux/{noteID-lower}/`
    static func auxDirectory(vaultURL: URL, noteID: UUID) -> URL {
        vaultURL
            .appendingPathComponent(auxDirName, isDirectory: true)
            .appendingPathComponent(noteID.uuidString.lowercased(), isDirectory: true)
    }
}

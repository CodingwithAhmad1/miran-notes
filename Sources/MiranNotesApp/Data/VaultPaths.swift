import Foundation
import MiranNotesCore

enum VaultPaths {
    static let miranDirName = ".miran"
    static let manifestFileName = "manifest.json"
    static let linkGraphFileName = "link-graph.json"
    static let relationshipIndexFileName = "relationship-index.json"
    static let folderCatalogFileName = "folder-catalog.json"
    static let pathIndexFileName = "path-index.json"
    static let externalBookmarksFileName = "external-bookmarks.json"
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

    static func externalBookmarksURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(externalBookmarksFileName, isDirectory: false)
    }

    /// `{vault}/_aux/{noteID-lower}/`
    static func auxDirectory(vaultURL: URL, noteID: UUID) -> URL {
        vaultURL
            .appendingPathComponent(auxDirName, isDirectory: true)
            .appendingPathComponent(noteID.uuidString.lowercased(), isDirectory: true)
    }

    // MARK: - Vault-level databases

    static let databasesDirName = "_databases"
    static let databaseRegistryFileName = "database-registry.json"

    static func databaseRegistryURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent(databaseRegistryFileName, isDirectory: false)
    }

    /// `{vault}/_databases/`
    static func databasesRoot(vaultURL: URL) -> URL {
        vaultURL.appendingPathComponent(databasesDirName, isDirectory: true)
    }

    /// `{vault}/_databases/{databaseID-lower}/`
    static func databaseDirectory(vaultURL: URL, databaseID: UUID) -> URL {
        databasesRoot(vaultURL: vaultURL)
            .appendingPathComponent(databaseID.uuidString.lowercased(), isDirectory: true)
    }

    /// `{vault}/_databases/{databaseID-lower}/schema.json`
    static func databaseSchemaURL(vaultURL: URL, databaseID: UUID) -> URL {
        databaseDirectory(vaultURL: vaultURL, databaseID: databaseID)
            .appendingPathComponent("schema.json", isDirectory: false)
    }

    /// `{vault}/_databases/{databaseID-lower}/rows.jsonl`
    static func databaseRowsURL(vaultURL: URL, databaseID: UUID) -> URL {
        databaseDirectory(vaultURL: vaultURL, databaseID: databaseID)
            .appendingPathComponent("rows.jsonl", isDirectory: false)
    }

    /// `{vault}/_databases/{databaseID-lower}/views/`
    static func databaseViewsDirectory(vaultURL: URL, databaseID: UUID) -> URL {
        databaseDirectory(vaultURL: vaultURL, databaseID: databaseID)
            .appendingPathComponent("views", isDirectory: true)
    }

    /// `{vault}/_databases/{databaseID-lower}/views/{viewID-lower}.json`
    static func databaseViewURL(vaultURL: URL, databaseID: UUID, viewID: UUID) -> URL {
        databaseViewsDirectory(vaultURL: vaultURL, databaseID: databaseID)
            .appendingPathComponent("\(viewID.uuidString.lowercased()).json", isDirectory: false)
    }
}

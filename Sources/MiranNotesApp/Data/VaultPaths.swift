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
}

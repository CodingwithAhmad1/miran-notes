import Foundation
import MiranNotesCore

enum VaultPaths {
    static let miranDirName = ".miran"
    static let manifestFileName = "manifest.json"
    static let linkGraphFileName = "link-graph.json"
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

    /// `{vault}/_aux/{noteID-lower}/`
    static func auxDirectory(vaultURL: URL, noteID: UUID) -> URL {
        vaultURL
            .appendingPathComponent(auxDirName, isDirectory: true)
            .appendingPathComponent(noteID.uuidString.lowercased(), isDirectory: true)
    }
}

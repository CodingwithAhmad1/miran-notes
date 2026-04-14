import Foundation
import MiranNotesCore

/// Index file I/O for `.miran/` JSON (link graph, path index, folder catalog, relationship index).
/// Used by ``VaultIndexActor`` and tests; separated for clearer failure boundaries.
enum VaultIndexSubsystem {
    static func loadLinkGraph(vaultURL: URL, decoder: JSONDecoder) throws -> LinkGraph {
        let url = VaultPaths.linkGraphURL(vaultURL: vaultURL)
        guard let data = try? Data(contentsOf: url),
              let graph = try? decoder.decode(LinkGraph.self, from: data) else {
            return LinkGraph()
        }
        return graph
    }

    static func loadPathIndex(vaultURL: URL, decoder: JSONDecoder) throws -> PathIndex {
        let url = VaultPaths.pathIndexURL(vaultURL: vaultURL)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(PathIndex.self, from: data) else {
            return PathIndex()
        }
        return decoded
    }

    static func loadRelationshipIndex(vaultURL: URL, decoder: JSONDecoder) throws -> RelationshipIndex {
        let url = VaultPaths.relationshipIndexURL(vaultURL: vaultURL)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(RelationshipIndex.self, from: data) else {
            return RelationshipIndex()
        }
        return decoded
    }

    static func loadFolderCatalog(vaultURL: URL, decoder: JSONDecoder) throws -> FolderCatalog {
        let url = VaultPaths.folderCatalogURL(vaultURL: vaultURL)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(FolderCatalog.self, from: data) else {
            var fresh = FolderCatalog()
            fresh.isDirty = true
            return fresh
        }
        return decoded
    }

    static func loadDatabaseRegistry(vaultURL: URL, decoder: JSONDecoder) throws -> DatabaseRegistry {
        try DatabaseRegistry.loadFromVault(vaultURL: vaultURL, decoder: decoder)
    }
}

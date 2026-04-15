import Foundation

/// On-disk layout for vault-level databases (`_databases/`) and `database-registry.json` under `.miran/`.
/// Shared by the app index layer and any future vault-database persistence code.
public enum VaultDatabasePaths {
    public static let databasesDirName = "_databases"
    public static let databaseRegistryFileName = "database-registry.json"

    private static let miranDirName = ".miran"

    private static func miranDirectory(vaultURL: URL) -> URL {
        vaultURL.appendingPathComponent(miranDirName, isDirectory: true)
    }

    public static func databaseRegistryURL(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL)
            .appendingPathComponent(databaseRegistryFileName, isDirectory: false)
    }

    /// `{vault}/_databases/`
    public static func databasesRoot(vaultURL: URL) -> URL {
        vaultURL.appendingPathComponent(databasesDirName, isDirectory: true)
    }

    /// `{vault}/_databases/{databaseID-lower}/`
    public static func databaseDirectory(vaultURL: URL, databaseID: UUID) -> URL {
        databasesRoot(vaultURL: vaultURL)
            .appendingPathComponent(databaseID.uuidString.lowercased(), isDirectory: true)
    }

    /// `{vault}/_databases/{databaseID-lower}/schema.json`
    public static func databaseSchemaURL(vaultURL: URL, databaseID: UUID) -> URL {
        databaseDirectory(vaultURL: vaultURL, databaseID: databaseID)
            .appendingPathComponent("schema.json", isDirectory: false)
    }

    /// `{vault}/_databases/{databaseID-lower}/rows.jsonl`
    public static func databaseRowsURL(vaultURL: URL, databaseID: UUID) -> URL {
        databaseDirectory(vaultURL: vaultURL, databaseID: databaseID)
            .appendingPathComponent("rows.jsonl", isDirectory: false)
    }

    /// `{vault}/_databases/{databaseID-lower}/views/`
    public static func databaseViewsDirectory(vaultURL: URL, databaseID: UUID) -> URL {
        databaseDirectory(vaultURL: vaultURL, databaseID: databaseID)
            .appendingPathComponent("views", isDirectory: true)
    }

    /// `{vault}/_databases/{databaseID-lower}/views/{viewID-lower}.json`
    public static func databaseViewURL(vaultURL: URL, databaseID: UUID, viewID: UUID) -> URL {
        databaseViewsDirectory(vaultURL: vaultURL, databaseID: databaseID)
            .appendingPathComponent("\(viewID.uuidString.lowercased()).json", isDirectory: false)
    }
}

extension DatabaseRegistry {
    /// Loads `database-registry.json` under `.miran/`, or returns an empty registry when missing or undecodable.
    public static func loadFromVault(vaultURL: URL, decoder: JSONDecoder) throws -> DatabaseRegistry {
        let url = VaultDatabasePaths.databaseRegistryURL(vaultURL: vaultURL)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(DatabaseRegistry.self, from: data) else {
            return DatabaseRegistry()
        }
        return decoded
    }
}

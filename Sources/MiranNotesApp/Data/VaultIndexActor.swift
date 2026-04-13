import Foundation
import MiranNotesCore
import os.log

/// Manifest + `.miran/` JSON indexes and atomic commits. Used by ``NoteRepository``.
actor VaultIndexActor {
    private nonisolated(unsafe) static let commitParticipants: [VaultCommitParticipant] = [
        NoteFilesCommitParticipant(),
        ManifestCommitParticipant(),
        LinkGraphCommitParticipant(),
        RelationshipIndexCommitParticipant(),
        FolderCatalogCommitParticipant(),
        PathIndexCommitParticipant()
    ]

    nonisolated let vaultURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let commitCoordinator: VaultCommitCoordinator

    private var vaultEnsured = false
    private var cachedManifest: VaultManifest?
    private var cachedLinkGraph: LinkGraph?
    private var cachedRelationshipIndex: RelationshipIndex?
    private var cachedFolderCatalog: FolderCatalog?
    private var cachedPathIndex: PathIndex?

    init(vaultURL: URL, commitCoordinator: VaultCommitCoordinator = VaultCommitCoordinator()) {
        self.vaultURL = vaultURL
        self.commitCoordinator = commitCoordinator
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    private func ensureVault() throws {
        guard !vaultEnsured else { return }
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: VaultPaths.miranDirectory(vaultURL: vaultURL), withIntermediateDirectories: true)
        vaultEnsured = true
    }

    /// Clears in-memory index caches (e.g. after external vault changes or manifest reconciliation).
    func invalidateCaches() {
        cachedManifest = nil
        cachedLinkGraph = nil
        cachedRelationshipIndex = nil
        cachedFolderCatalog = nil
        cachedPathIndex = nil
    }

    private func storeCommittedState(
        manifest: VaultManifest,
        linkGraph: LinkGraph,
        relationshipIndex: RelationshipIndex,
        folderCatalog: FolderCatalog,
        pathIndex: PathIndex
    ) {
        var m = manifest
        m.isDirty = false
        cachedManifest = m
        var lg = linkGraph
        lg.isDirty = false
        cachedLinkGraph = lg
        var ri = relationshipIndex
        ri.isDirty = false
        cachedRelationshipIndex = ri
        var fc = folderCatalog
        fc.isDirty = false
        cachedFolderCatalog = fc
        var pi = pathIndex
        pi.isDirty = false
        cachedPathIndex = pi
    }

    private func manifestURL() -> URL {
        VaultPaths.manifestURL(vaultURL: vaultURL)
    }

    func loadManifestFromDiskOnly() -> VaultManifest? {
        if let cached = cachedManifest {
            return cached
        }
        let url = manifestURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(VaultManifest.self, from: data) else {
            return nil
        }
        cachedManifest = decoded
        return decoded
    }

    func encodeManifest(_ manifest: VaultManifest) throws -> Data {
        try encoder.encode(manifest)
    }

    func loadLinkGraph() throws -> LinkGraph {
        if let cached = cachedLinkGraph {
            return cached
        }
        let loaded = try VaultIndexSubsystem.loadLinkGraph(vaultURL: vaultURL, decoder: decoder)
        cachedLinkGraph = loaded
        return loaded
    }

    func loadRelationshipIndex() throws -> RelationshipIndex {
        if let cached = cachedRelationshipIndex {
            return cached
        }
        let loaded = try VaultIndexSubsystem.loadRelationshipIndex(vaultURL: vaultURL, decoder: decoder)
        cachedRelationshipIndex = loaded
        return loaded
    }

    func loadFolderCatalog() throws -> FolderCatalog {
        if let cached = cachedFolderCatalog {
            return cached
        }
        let loaded = try VaultIndexSubsystem.loadFolderCatalog(vaultURL: vaultURL, decoder: decoder)
        cachedFolderCatalog = loaded
        return loaded
    }

    func loadPathIndex() throws -> PathIndex {
        if let cached = cachedPathIndex {
            return cached
        }
        let loaded = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        cachedPathIndex = loaded
        return loaded
    }

    func logIfIntegrityIssues(_ result: VaultIntegrityResult) {
        guard !result.isClean else { return }
        for issue in result.issues {
            Logger.vault.error("Vault integrity: \(issue, privacy: .public)")
        }
    }

    func runIntegrityAfterCommit(
        relativePath: String?,
        includeNoteFiles: Bool,
        manifest: VaultManifest,
        linkGraph: LinkGraph,
        relationshipIndex: RelationshipIndex
    ) -> VaultIntegrityResult {
        VaultIntegrityChecker.check(
            vaultURL: vaultURL,
            manifest: manifest,
            linkGraph: linkGraph,
            relationshipIndex: relationshipIndex,
            savedNoteRelativePath: includeNoteFiles ? relativePath : nil,
            decoder: decoder
        )
    }

    func executeNoteCommit(
        label: String,
        relativePath: String,
        document: NoteDocument,
        textURL: URL,
        metaURL: URL,
        manifest: VaultManifest,
        linkGraph: LinkGraph,
        relationshipIndex: RelationshipIndex,
        folderCatalog: FolderCatalog,
        pathIndex: PathIndex,
        deletePathsAfterCommit: [URL]
    ) throws -> VaultIntegrityResult {
        try ensureVault()
        try FileManager.default.createDirectory(at: VaultPaths.pendingCommitsDirectory(vaultURL: vaultURL), withIntermediateDirectories: true)
        let commitTempDir = VaultPaths.pendingCommitsDirectory(vaultURL: vaultURL)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: commitTempDir, withIntermediateDirectories: true)
        var m = manifest
        m.ensureSchemaVersionIsCurrent()
        let context = VaultCommitContext(
            relativePath: relativePath,
            includeNoteFiles: true,
            document: document,
            textURL: textURL,
            metaURL: metaURL,
            manifestURL: manifestURL(),
            linkGraphURL: VaultPaths.linkGraphURL(vaultURL: vaultURL),
            relationshipIndexURL: VaultPaths.relationshipIndexURL(vaultURL: vaultURL),
            folderCatalogURL: VaultPaths.folderCatalogURL(vaultURL: vaultURL),
            pathIndexURL: VaultPaths.pathIndexURL(vaultURL: vaultURL),
            encoder: encoder,
            manifest: m,
            linkGraph: linkGraph,
            relationshipIndex: relationshipIndex,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex,
            tempDirectory: commitTempDir
        )

        var operations: [VaultCommitOperation] = []
        for participant in Self.commitParticipants {
            operations.append(contentsOf: try participant.operations(for: context))
        }
        try commitCoordinator.execute(
            VaultCommitPlan(
                label: label,
                operations: operations,
                deletePathsAfterCommit: deletePathsAfterCommit
            ),
            vaultRoot: vaultURL,
            stagingDirectory: commitTempDir
        )
        storeCommittedState(
            manifest: m,
            linkGraph: linkGraph,
            relationshipIndex: relationshipIndex,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        )
        return runIntegrityAfterCommit(
            relativePath: relativePath,
            includeNoteFiles: true,
            manifest: m,
            linkGraph: linkGraph,
            relationshipIndex: relationshipIndex
        )
    }

    func commitIndexOnly(
        manifest: VaultManifest,
        linkGraph: LinkGraph,
        relationshipIndex: RelationshipIndex,
        folderCatalog: FolderCatalog,
        pathIndex: PathIndex,
        deletePathsAfterCommit: [URL] = []
    ) throws -> VaultIntegrityResult {
        try ensureVault()
        try FileManager.default.createDirectory(at: VaultPaths.pendingCommitsDirectory(vaultURL: vaultURL), withIntermediateDirectories: true)
        let commitTempDir = VaultPaths.pendingCommitsDirectory(vaultURL: vaultURL)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: commitTempDir, withIntermediateDirectories: true)
        var m = manifest
        m.ensureSchemaVersionIsCurrent()
        let context = VaultCommitContext(
            relativePath: "indexes",
            includeNoteFiles: false,
            document: nil,
            textURL: nil,
            metaURL: nil,
            manifestURL: manifestURL(),
            linkGraphURL: VaultPaths.linkGraphURL(vaultURL: vaultURL),
            relationshipIndexURL: VaultPaths.relationshipIndexURL(vaultURL: vaultURL),
            folderCatalogURL: VaultPaths.folderCatalogURL(vaultURL: vaultURL),
            pathIndexURL: VaultPaths.pathIndexURL(vaultURL: vaultURL),
            encoder: encoder,
            manifest: m,
            linkGraph: linkGraph,
            relationshipIndex: relationshipIndex,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex,
            tempDirectory: commitTempDir
        )
        var operations: [VaultCommitOperation] = []
        for participant in Self.commitParticipants {
            operations.append(contentsOf: try participant.operations(for: context))
        }
        try commitCoordinator.execute(
            VaultCommitPlan(label: "indexes", operations: operations, deletePathsAfterCommit: deletePathsAfterCommit),
            vaultRoot: vaultURL,
            stagingDirectory: commitTempDir
        )
        storeCommittedState(
            manifest: m,
            linkGraph: linkGraph,
            relationshipIndex: relationshipIndex,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        )
        return runIntegrityAfterCommit(
            relativePath: nil,
            includeNoteFiles: false,
            manifest: m,
            linkGraph: linkGraph,
            relationshipIndex: relationshipIndex
        )
    }
}

// MARK: - Commit participants

private struct NoteFilesCommitParticipant: VaultCommitParticipant {
    let participantID = "noteFiles"

    func operations(for context: VaultCommitContext) throws -> [VaultCommitOperation] {
        guard context.includeNoteFiles,
              let document = context.document,
              let textURL = context.textURL,
              let metaURL = context.metaURL
        else { return [] }
        let metadataData = try context.encoder.encode(document.metadata)
        let textData = document.text.data(using: .utf8) ?? Data()
        let tempText = context.tempDirectory.appendingPathComponent("note.txt")
        let tempMeta = context.tempDirectory.appendingPathComponent("note.meta.json")
        return [
            VaultCommitOperation(participantID: participantID, operationID: "text") {
                try textData.write(to: tempText, options: .atomic)
                return (tempText, textURL)
            },
            VaultCommitOperation(participantID: participantID, operationID: "metadata") {
                try metadataData.write(to: tempMeta, options: .atomic)
                return (tempMeta, metaURL)
            }
        ]
    }
}

private struct ManifestCommitParticipant: VaultCommitParticipant {
    let participantID = "manifest"

    func operations(for context: VaultCommitContext) throws -> [VaultCommitOperation] {
        guard context.manifest.isDirty else { return [] }
        let data = try context.encoder.encode(context.manifest)
        let tempURL = context.tempDirectory.appendingPathComponent("manifest.json")
        return [
            VaultCommitOperation(participantID: participantID, operationID: "manifest") {
                try data.write(to: tempURL, options: .atomic)
                return (tempURL, context.manifestURL)
            }
        ]
    }
}

private struct LinkGraphCommitParticipant: VaultCommitParticipant {
    let participantID = "linkGraph"

    func operations(for context: VaultCommitContext) throws -> [VaultCommitOperation] {
        guard context.linkGraph.isDirty else { return [] }
        let data = try context.encoder.encode(context.linkGraph)
        let tempURL = context.tempDirectory.appendingPathComponent("link-graph.json")
        return [
            VaultCommitOperation(participantID: participantID, operationID: "linkGraph") {
                try data.write(to: tempURL, options: .atomic)
                return (tempURL, context.linkGraphURL)
            }
        ]
    }
}

private struct RelationshipIndexCommitParticipant: VaultCommitParticipant {
    let participantID = "relationshipIndex"

    func operations(for context: VaultCommitContext) throws -> [VaultCommitOperation] {
        guard context.relationshipIndex.isDirty else { return [] }
        let data = try context.encoder.encode(context.relationshipIndex)
        let tempURL = context.tempDirectory.appendingPathComponent("relationship-index.json")
        return [
            VaultCommitOperation(participantID: participantID, operationID: "relationshipIndex") {
                try data.write(to: tempURL, options: .atomic)
                return (tempURL, context.relationshipIndexURL)
            }
        ]
    }
}

private struct FolderCatalogCommitParticipant: VaultCommitParticipant {
    let participantID = "folderCatalog"

    func operations(for context: VaultCommitContext) throws -> [VaultCommitOperation] {
        guard context.folderCatalog.isDirty else { return [] }
        let data = try context.encoder.encode(context.folderCatalog)
        let tempURL = context.tempDirectory.appendingPathComponent("folder-catalog.json")
        return [
            VaultCommitOperation(participantID: participantID, operationID: "folderCatalog") {
                try data.write(to: tempURL, options: .atomic)
                return (tempURL, context.folderCatalogURL)
            }
        ]
    }
}

private struct PathIndexCommitParticipant: VaultCommitParticipant {
    let participantID = "pathIndex"

    func operations(for context: VaultCommitContext) throws -> [VaultCommitOperation] {
        guard context.pathIndex.isDirty else { return [] }
        let data = try context.encoder.encode(context.pathIndex)
        let tempURL = context.tempDirectory.appendingPathComponent("path-index.json")
        return [
            VaultCommitOperation(participantID: participantID, operationID: "pathIndex") {
                try data.write(to: tempURL, options: .atomic)
                return (tempURL, context.pathIndexURL)
            }
        ]
    }
}

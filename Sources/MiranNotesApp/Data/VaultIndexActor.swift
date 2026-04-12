import Foundation
import MiranNotesCore
import os.log

/// Manifest + `.miran/` JSON indexes and atomic commits. Used by ``NoteRepository``.
actor VaultIndexActor {
    nonisolated let vaultURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let commitCoordinator: VaultCommitCoordinator

    init(vaultURL: URL, commitCoordinator: VaultCommitCoordinator = VaultCommitCoordinator()) {
        self.vaultURL = vaultURL
        self.commitCoordinator = commitCoordinator
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    private func ensureVault() throws {
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: VaultPaths.miranDirectory(vaultURL: vaultURL), withIntermediateDirectories: true)
    }

    private func manifestURL() -> URL {
        VaultPaths.manifestURL(vaultURL: vaultURL)
    }

    func loadManifestFromDiskOnly() -> VaultManifest? {
        let url = manifestURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(VaultManifest.self, from: data) else {
            return nil
        }
        return decoded
    }

    func encodeManifest(_ manifest: VaultManifest) throws -> Data {
        try encoder.encode(manifest)
    }

    func loadLinkGraph() throws -> LinkGraph {
        try VaultIndexSubsystem.loadLinkGraph(vaultURL: vaultURL, decoder: decoder)
    }

    func loadRelationshipIndex() throws -> RelationshipIndex {
        try VaultIndexSubsystem.loadRelationshipIndex(vaultURL: vaultURL, decoder: decoder)
    }

    func loadFolderCatalog() throws -> FolderCatalog {
        try VaultIndexSubsystem.loadFolderCatalog(vaultURL: vaultURL, decoder: decoder)
    }

    func loadPathIndex() throws -> PathIndex {
        try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
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
        m.schemaVersion = VaultManifest.currentSchemaVersion
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

        let participants: [VaultCommitParticipant] = [
            NoteFilesCommitParticipant(),
            ManifestCommitParticipant(),
            LinkGraphCommitParticipant(),
            RelationshipIndexCommitParticipant(),
            FolderCatalogCommitParticipant(),
            PathIndexCommitParticipant()
        ]
        var operations: [VaultCommitOperation] = []
        for participant in participants {
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
        let emptyDoc = NoteDocument(text: "", metadata: NoteMetadata.empty)
        var m = manifest
        m.schemaVersion = VaultManifest.currentSchemaVersion
        let dummyText = vaultURL.appendingPathComponent(".miran/.dummy.txt")
        let dummyMeta = vaultURL.appendingPathComponent(".miran/.dummy.meta.json")
        let context = VaultCommitContext(
            relativePath: "indexes",
            includeNoteFiles: false,
            document: emptyDoc,
            textURL: dummyText,
            metaURL: dummyMeta,
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
        let participants: [VaultCommitParticipant] = [
            NoteFilesCommitParticipant(),
            ManifestCommitParticipant(),
            LinkGraphCommitParticipant(),
            RelationshipIndexCommitParticipant(),
            FolderCatalogCommitParticipant(),
            PathIndexCommitParticipant()
        ]
        var operations: [VaultCommitOperation] = []
        for participant in participants {
            operations.append(contentsOf: try participant.operations(for: context))
        }
        try commitCoordinator.execute(
            VaultCommitPlan(label: "indexes", operations: operations, deletePathsAfterCommit: deletePathsAfterCommit),
            vaultRoot: vaultURL,
            stagingDirectory: commitTempDir
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
        guard context.includeNoteFiles else { return [] }
        let metadataData = try context.encoder.encode(context.document.metadata)
        let textData = context.document.text.data(using: .utf8) ?? Data()
        let tempText = context.tempDirectory.appendingPathComponent("note.txt")
        let tempMeta = context.tempDirectory.appendingPathComponent("note.meta.json")
        return [
            VaultCommitOperation(participantID: participantID, operationID: "text") {
                try textData.write(to: tempText, options: .atomic)
                return (tempText, context.textURL)
            },
            VaultCommitOperation(participantID: participantID, operationID: "metadata") {
                try metadataData.write(to: tempMeta, options: .atomic)
                return (tempMeta, context.metaURL)
            }
        ]
    }
}

private struct ManifestCommitParticipant: VaultCommitParticipant {
    let participantID = "manifest"

    func operations(for context: VaultCommitContext) throws -> [VaultCommitOperation] {
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

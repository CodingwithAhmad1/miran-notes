import Foundation
import MiranNotesCore
import os.log

/// Result of loading a note from disk, including any structural repair warnings.
struct NoteLoadResult: Sendable {
    var document: NoteDocument
    var repairWarnings: [String]

    var wasRepaired: Bool { !repairWarnings.isEmpty }
}

enum NoteRepositoryError: LocalizedError, Equatable {
    case invalidBaseName(String)
    case invalidRelativePath(String)
    case tooManyFilenameCollisions
    case noteNotFound(String)
    case noteNotFoundByID(UUID)
    case folderNotFound(UUID)
    case invalidFolderName(String)
    case invalidFolderMove
    case folderNotEmpty(UUID)
    case unresolvedNoteIdentity(String)
    /// The vault root path is missing or is not a directory (the app does not create the vault folder itself).
    case vaultRootNotDirectory(path: String)

    var errorDescription: String? {
        switch self {
        case let .invalidBaseName(name):
            return "Invalid note name: \(name)"
        case let .invalidRelativePath(path):
            return "Invalid path: \(path)"
        case .tooManyFilenameCollisions:
            return "Could not allocate a unique note file name."
        case let .noteNotFound(base):
            return "Note not found: \(base)"
        case let .noteNotFoundByID(id):
            return "Note not found: \(id.uuidString)"
        case let .folderNotFound(id):
            return "Folder not found: \(id.uuidString)"
        case let .invalidFolderName(name):
            return "Invalid folder name: \(name)"
        case .invalidFolderMove:
            return "That folder cannot be moved there."
        case let .folderNotEmpty(id):
            return "Folder is not empty (contains notes or folders): \(id.uuidString)"
        case let .unresolvedNoteIdentity(path):
            return "Could not resolve note identity for path: \(path)"
        case let .vaultRootNotDirectory(path):
            return "Vault folder does not exist or is not a directory: \(path)"
        }
    }
}

struct NoteSummary: Identifiable, Hashable, Sendable {
    var id: UUID { noteID }
    var noteID: UUID
    var title: String
    /// Path under the vault root without extension, e.g. `work/a` or `note`.
    var relativePath: String
    /// Folder that owns this note in `FolderCatalog` (vault root uses `FolderCatalog.rootFolderID`).
    var folderID: UUID
}

/// One incoming link from a source note (backlink row in the UI).
struct BacklinkItem: Identifiable, Sendable {
    var id: UUID { sourceNoteID }
    var sourceNoteID: UUID
    var title: String
    var relativePath: String
    var snippet: String
    /// UTF-16 range of the link in the **source** note’s body (for scroll-to-link).
    var linkRange: MiranNotesCore.TextRange
}

/// Coordinates ``NoteFileActor`` (per-note `.txt` / `.meta.json`) and ``VaultIndexActor`` (manifest + `.miran/` JSON + commits).
actor NoteRepository {
    private func updateRelationshipIndex(
        _ relationshipIndex: inout RelationshipIndex,
        for document: NoteDocument
    ) {
        let noteID = document.metadata.noteID
        let linkRels = document.metadata.links.map { link in
            LinkRelationship(
                sourceNoteID: noteID,
                target: .note(noteID: link.targetNoteID),
                relationshipKind: "noteLink"
            )
        }
        let artifactRels = document.metadata.artifacts.map { artifact in
            LinkRelationship(
                sourceNoteID: noteID,
                target: .artifact(noteID: noteID, artifactID: artifact.id, kind: artifact.kind),
                relationshipKind: "artifactLink"
            )
        }
        relationshipIndex.replaceLinks(from: noteID, with: linkRels + artifactRels)
    }

    /// Rewrites a relative path when a folder prefix changes; returns `nil` if the path is outside `oldPrefix`.
    /// Maps `folder/title` notes to the folder catalog’s top-level folder; single-segment paths use vault root.
    private static func inferFolderID(forNotePath relativePath: String, folderCatalog: FolderCatalog) -> UUID {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard parts.count > 1, let first = parts.first else {
            return FolderCatalog.rootFolderID
        }
        for folder in folderCatalog.childFolders(of: FolderCatalog.rootFolderID) {
            if folder.storageSegment == first {
                return folder.id
            }
        }
        return FolderCatalog.rootFolderID
    }

    /// When the manifest `noteID` for `relativePath` is repaired to match a sidecar, secondary indexes may still reference the stale id; remap them before commit.
    private struct ManifestNoteIDRepair {
        let relativePath: String
        let oldNoteID: UUID
        let newNoteID: UUID
    }

    private func persistIndexes(manifest: VaultManifest, manifestNoteIDRepair: ManifestNoteIDRepair? = nil) async throws {
        var graph = try await index.loadLinkGraph()
        var rel = try await index.loadRelationshipIndex()
        let folderCatalog = try await index.loadFolderCatalog()
        var pathIndex = try await index.loadPathIndex()
        if let repair = manifestNoteIDRepair {
            pathIndex.replaceNoteID(forRelativePath: repair.relativePath, newNoteID: repair.newNoteID)
            graph.remapNoteIDEverywhere(from: repair.oldNoteID, to: repair.newNoteID)
            rel.remapNoteID(from: repair.oldNoteID, to: repair.newNoteID)
        }
        let integrity = try await index.commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        )
        await index.logIfIntegrityIssues(integrity)
    }

    private static func rewritePath(_ path: String, oldPrefix: String, newPrefix: String) -> String? {
        let oldRoot = oldPrefix.isEmpty ? "" : oldPrefix + "/"
        guard path.hasPrefix(oldRoot) || path == oldPrefix else { return nil }
        let suffix: String
        if path.hasPrefix(oldRoot) {
            suffix = String(path.dropFirst(oldRoot.count))
        } else {
            suffix = (path as NSString).lastPathComponent
        }
        if newPrefix.isEmpty {
            return suffix
        }
        if suffix.isEmpty {
            return newPrefix
        }
        return "\(newPrefix)/\(suffix)"
    }

    nonisolated let vaultURL: URL
    private let files: NoteFileActor
    private let index: VaultIndexActor

    init(vaultURL: URL, commitCoordinator: VaultCommitCoordinator = VaultCommitCoordinator()) {
        self.vaultURL = vaultURL
        self.files = NoteFileActor(vaultURL: vaultURL)
        self.index = VaultIndexActor(vaultURL: vaultURL, commitCoordinator: commitCoordinator)
    }

    /// Resume interrupted commits from a previous run. Call early when opening a vault.
    func performStartupRecovery() async throws -> VaultRecoverySummary {
        try await files.ensureVault()
        let summary = try VaultCommitCoordinator.recoverPendingCommits(vaultRoot: vaultURL)
        await index.invalidateCaches()
        return summary
    }

    /// Drops in-memory `.miran/` index caches (e.g. after external filesystem changes).
    func invalidateIndexCaches() async {
        await index.invalidateCaches()
    }

    /// Legacy single-segment validation (flat notes only).
    nonisolated static func validateBaseName(_ baseName: String) throws {
        try VaultPath.validateSingleSegment(baseName)
    }

    func ensureVault() async throws {
        try await files.ensureVault()
    }

    /// Scans the vault, reconciles manifest entries with on-disk notes, and commits indexes if the manifest JSON would change.
    func reconcileManifest() async throws {
        try await files.ensureVault()
        let manifest = try await loadOrRebuildManifest()
        var m = manifest
        m.ensureSchemaVersionIsCurrent()
        let encodedManifest = try await index.encodeManifest(m)
        let diskManifest = try? Data(contentsOf: VaultPaths.manifestURL(vaultURL: vaultURL))
        guard encodedManifest != diskManifest else { return }
        let graph = try await index.loadLinkGraph()
        let rel = try await index.loadRelationshipIndex()
        let folderCatalog = try await index.loadFolderCatalog()
        let pathIndex = try await index.loadPathIndex()
        let integrity = try await index.commitIndexOnly(
            manifest: m,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        )
        await index.logIfIntegrityIssues(integrity)
    }

    func listNotes() async throws -> [NoteSummary] {
        try await files.ensureVault()
        guard let manifest = await index.loadManifestFromDiskOnly() else {
            return []
        }

        let pathIndex = try await index.loadPathIndex()
        let folderByNote = Dictionary(uniqueKeysWithValues: pathIndex.entries.map { ($0.noteID, $0.folderID) })

        let summaries = manifest.entries
            .sorted { $0.relativePath.lowercased() < $1.relativePath.lowercased() }
            .map { entry -> NoteSummary in
                let displayTitle = entry.title ?? VaultPath.displayTitle(forRelativePath: entry.relativePath)
                return NoteSummary(
                    noteID: entry.noteID,
                    title: displayTitle,
                    relativePath: entry.relativePath,
                    folderID: folderByNote[entry.noteID] ?? FolderCatalog.rootFolderID
                )
            }
        let titleBuckets = Dictionary(grouping: summaries, by: { $0.title.lowercased() })
        return summaries.map { summary in
            guard titleBuckets[summary.title.lowercased()]?.count ?? 0 > 1 else { return summary }
            return NoteSummary(
                noteID: summary.noteID,
                title: VaultPath.disambiguatedListTitle(relativePath: summary.relativePath),
                relativePath: summary.relativePath,
                folderID: summary.folderID
            )
        }
    }

    func loadManifest() async throws -> VaultManifest {
        try await loadOrRebuildManifest()
    }

    func linkResolver() async throws -> LinkResolver {
        LinkResolver(manifest: try await loadOrRebuildManifest())
    }

    func loadLinkGraph() async throws -> LinkGraph {
        try await index.loadLinkGraph()
    }

    func saveLinkGraph(_ graph: LinkGraph) async throws {
        try await files.ensureVault()
        var g = graph
        g.isDirty = true
        let manifest = try await loadOrRebuildManifest()
        let rel = try await index.loadRelationshipIndex()
        let folderCatalog = try await index.loadFolderCatalog()
        let pathIndex = try await index.loadPathIndex()
        let integrity = try await index.commitIndexOnly(
            manifest: manifest,
            linkGraph: g,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        )
        await index.logIfIntegrityIssues(integrity)
    }

    func updateLinkGraph(sourceNoteID: UUID, targets: [UUID]) async throws {
        var graph = try await index.loadLinkGraph()
        graph.setOutgoing(from: sourceNoteID, to: targets)
        try await saveLinkGraph(graph)
    }

    func rebuildLinkGraphFull() async throws -> VaultIntegrityResult {
        let manifest = try await loadOrRebuildManifest()
        var graph = LinkGraph()
        for entry in manifest.entries {
            let doc = try await files.loadNote(relativePath: entry.relativePath, fallbackNoteID: entry.noteID).document
            graph.setOutgoing(from: entry.noteID, to: doc.metadata.links.map(\.targetNoteID))
        }
        let rel = try await index.loadRelationshipIndex()
        let folderCatalog = try await index.loadFolderCatalog()
        let pathIndex = try await index.loadPathIndex()
        let integrity = try await index.commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        )
        Logger.vault.info("Rebuilt link graph for \(manifest.entries.count, privacy: .public) notes")
        return integrity
    }

    /// Synchronizes `LinkGraph` from persisted note-link relationships without scanning note files.
    ///
    /// This is the canonical startup/external-change path: relationship metadata is already persisted in
    /// `RelationshipIndex`, so we derive an exact note-link adjacency map and commit only if the graph differs.
    func synchronizeLinkGraphFromRelationships() async throws -> VaultIntegrityResult {
        let manifest = try await loadOrRebuildManifest()
        let noteIDs = Set(manifest.entries.map(\.noteID))
        let relationshipIndex = try await index.loadRelationshipIndex()
        var derivedTargetsBySource: [UUID: [UUID]] = [:]

        for relationship in relationshipIndex.relationships {
            guard relationship.relationshipKind == "noteLink" else { continue }
            guard noteIDs.contains(relationship.sourceNoteID) else { continue }
            guard case let .note(targetID) = relationship.target, noteIDs.contains(targetID) else { continue }
            derivedTargetsBySource[relationship.sourceNoteID, default: []].append(targetID)
        }

        var derived = LinkGraph()
        for (sourceID, targets) in derivedTargetsBySource {
            derived.setOutgoing(from: sourceID, to: targets)
        }
        // `isDirty` is an in-memory optimization only; equality must compare persisted shape.
        derived.isDirty = false

        let current = try await index.loadLinkGraph()
        if current.outgoing == derived.outgoing {
            return .clean
        }

        var graphToCommit = derived
        graphToCommit.isDirty = true
        let folderCatalog = try await index.loadFolderCatalog()
        let pathIndex = try await index.loadPathIndex()
        let integrity = try await index.commitIndexOnly(
            manifest: manifest,
            linkGraph: graphToCommit,
            relationshipIndex: relationshipIndex,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        )
        await index.logIfIntegrityIssues(integrity)
        return integrity
    }

    func createNote(named name: String) async throws -> (NoteDocument, String) {
        try await createNote(named: name, folderID: FolderCatalog.rootFolderID)
    }

    func loadNote(noteID: UUID) async throws -> NoteLoadResult {
        let manifest = try await loadOrRebuildManifest()
        guard let entry = manifest.entry(noteID: noteID) else {
            throw NoteRepositoryError.noteNotFoundByID(noteID)
        }
        return try await loadNote(relativePath: entry.relativePath)
    }

    func loadNote(relativePath: String) async throws -> NoteLoadResult {
        try await files.ensureVault()
        let manifest = try await loadOrRebuildManifest()
        let decoder = JSONDecoder()
        if let meta = try NoteIdentityResolution.decodeSidecarMetadata(
            vaultRoot: vaultURL,
            relativePath: relativePath,
            decoder: decoder
        ) {
            var synced = manifest
            let title = VaultPath.displayTitle(forRelativePath: relativePath)
            let preAlignNoteID = synced.entries.first(where: { $0.relativePath == relativePath })?.noteID
            if NoteIdentityResolution.alignManifestWithSidecarIfNeeded(
                manifest: &synced,
                relativePath: relativePath,
                sidecarNoteID: meta.noteID,
                title: title
            ), let oldID = preAlignNoteID, oldID != meta.noteID {
                try await persistIndexes(
                    manifest: synced,
                    manifestNoteIDRepair: ManifestNoteIDRepair(
                        relativePath: relativePath,
                        oldNoteID: oldID,
                        newNoteID: meta.noteID
                    )
                )
            }
            return try await files.loadNote(relativePath: relativePath, fallbackNoteID: nil)
        }
        guard let entry = manifest.entry(relativePath: relativePath) else {
            throw NoteRepositoryError.noteNotFound(relativePath)
        }
        return try await files.loadNote(relativePath: relativePath, fallbackNoteID: entry.noteID)
    }

    /// Legacy API for tests and callers still using a single path segment.
    func loadNote(baseName: String) async throws -> NoteLoadResult {
        try await loadNote(relativePath: baseName)
    }

    func noteTextFileSHA256(relativePath: String) async throws -> String {
        try await files.noteTextFileSHA256(relativePath: relativePath)
    }

    func readRawNoteText(relativePath: String) async throws -> String {
        try await files.readRawNoteText(relativePath: relativePath)
    }

    func buildBodySearchIndex() async throws -> [UUID: String] {
        let manifest = try await loadOrRebuildManifest()
        var result: [UUID: String] = [:]
        result.reserveCapacity(manifest.entries.count)
        for entry in manifest.entries {
            let raw: String
            do {
                raw = try await files.readRawNoteText(relativePath: entry.relativePath)
            } catch {
                Logger.vault.debug(
                    "buildBodySearchIndex skip path=\(entry.relativePath, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                continue
            }
            result[entry.noteID] = raw
        }
        return result
    }

    func noteModifiedDate(relativePath: String) async throws -> Date? {
        try await files.noteModifiedDate(relativePath: relativePath)
    }

    func noteRevisionToken(relativePath: String) async throws -> DocumentRevisionToken? {
        try await files.noteRevisionToken(relativePath: relativePath)
    }

    @discardableResult
    func save(_ note: NoteDocument, asRelativePath relativePath: String, folderID: UUID = FolderCatalog.rootFolderID) async throws -> VaultIntegrityResult {
        try VaultPath.validateRelativePath(relativePath)
        try VaultPath.ensureParentDirectories(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath)
        try await files.ensureVault()

        let normalized = RangeNormalizer.normalize(metadata: note.metadata, for: note.text)
        let documentToPersist = NoteDocument(
            text: note.text,
            metadata: normalized.normalizedMetadata
        )
        NoteIntegrity.logIfInvalid(document: documentToPersist)

        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "txt")
        let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "meta.json")

        var manifest = await index.loadManifestFromDiskOnly() ?? VaultManifest()
        manifest.ensureSchemaVersionIsCurrent()
        let title = VaultPath.displayTitle(forRelativePath: relativePath)
        manifest.upsert(noteID: documentToPersist.metadata.noteID, relativePath: relativePath, title: title)

        var graph = try await index.loadLinkGraph()
        let targets = documentToPersist.metadata.links.map(\.targetNoteID)
        graph.setOutgoing(from: documentToPersist.metadata.noteID, to: targets)

        var relationshipIndex = try await index.loadRelationshipIndex()
        updateRelationshipIndex(&relationshipIndex, for: documentToPersist)

        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        var pathIndex = try await index.loadPathIndex()
        pathIndex.upsert(
            noteID: documentToPersist.metadata.noteID,
            folderID: folderID,
            relativePath: relativePath
        )

        return try await index.executeNoteCommit(
            label: "save:\(relativePath)",
            relativePath: relativePath,
            document: documentToPersist,
            textURL: textURL,
            metaURL: metaURL,
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: relationshipIndex,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex,
            deletePathsAfterCommit: []
        )
    }

    /// Persists a note addressed by its manifest-relative path (single segment at vault root, or nested `folder/note-stem`).
    @discardableResult
    func save(_ note: NoteDocument, asBaseName baseName: String) async throws -> VaultIntegrityResult {
        if baseName.contains("/") {
            try VaultPath.validateRelativePath(baseName)
            let pathIndex = try await index.loadPathIndex()
            let folderID =
                pathIndex.entries.first { $0.relativePath == baseName }?.folderID ?? FolderCatalog.rootFolderID
            return try await save(note, asRelativePath: baseName, folderID: folderID)
        }
        try Self.validateBaseName(baseName)
        return try await save(note, asRelativePath: baseName, folderID: FolderCatalog.rootFolderID)
    }

    func renameNote(from oldRelativePath: String, to newTitle: String) async throws -> String {
        try VaultPath.validateRelativePath(oldRelativePath)
        try await files.ensureVault()
        let oldTxt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: oldRelativePath, extension: "txt")
        guard FileManager.default.fileExists(atPath: oldTxt.path) else {
            throw NoteRepositoryError.noteNotFound(oldRelativePath)
        }

        let doc = try await loadNote(relativePath: oldRelativePath).document
        let folderID = (try await index.loadPathIndex()).entries.first { $0.noteID == doc.metadata.noteID }?.folderID ?? FolderCatalog.rootFolderID

        let parentDir = (oldRelativePath as NSString).deletingLastPathComponent
        let stemSlug: String
        if newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stemSlug = (oldRelativePath as NSString).lastPathComponent
        } else {
            stemSlug = await files.slugify(newTitle)
        }
        if stemSlug.isEmpty {
            throw NoteRepositoryError.invalidRelativePath(newTitle)
        }

        let newRelativePath: String = parentDir.isEmpty ? stemSlug : "\(parentDir)/\(stemSlug)"

        if newRelativePath == oldRelativePath {
            var manifest = await index.loadManifestFromDiskOnly() ?? VaultManifest()
            manifest.ensureSchemaVersionIsCurrent()
            manifest.upsert(noteID: doc.metadata.noteID, relativePath: oldRelativePath, title: newTitle)
            let graph = try await index.loadLinkGraph()
            let relationshipIndex = try await index.loadRelationshipIndex()
            let folderCatalog = try await index.loadFolderCatalog()
            let pathIndex = try await index.loadPathIndex()
            let integrity = try await index.commitIndexOnly(
                manifest: manifest,
                linkGraph: graph,
                relationshipIndex: relationshipIndex,
                folderCatalog: folderCatalog,
                pathIndex: pathIndex
            )
            await index.logIfIntegrityIssues(integrity)
            return oldRelativePath
        }

        let uniqueNew = try await files.uniqueAvailableRelativePath(inDirectoryPrefix: parentDir.isEmpty ? nil : parentDir, slugStem: stemSlug)

        let oldMeta = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: oldRelativePath, extension: "meta.json")
        let newTxt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: uniqueNew, extension: "txt")
        let newMeta = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: uniqueNew, extension: "meta.json")

        try VaultPath.ensureParentDirectories(vaultRoot: vaultURL, relativePathWithoutExtension: uniqueNew)

        var manifest = await index.loadManifestFromDiskOnly() ?? VaultManifest()
        manifest.ensureSchemaVersionIsCurrent()
        manifest.upsert(noteID: doc.metadata.noteID, relativePath: uniqueNew, title: newTitle)

        var graph = try await index.loadLinkGraph()
        graph.setOutgoing(from: doc.metadata.noteID, to: doc.metadata.links.map(\.targetNoteID))
        var relationshipIndex = try await index.loadRelationshipIndex()
        updateRelationshipIndex(&relationshipIndex, for: doc)

        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        var pathIndex = try await index.loadPathIndex()
        pathIndex.upsert(noteID: doc.metadata.noteID, folderID: folderID, relativePath: uniqueNew)

        let normalized = RangeNormalizer.normalize(metadata: doc.metadata, for: doc.text)
        let documentToPersist = NoteDocument(text: doc.text, metadata: normalized.normalizedMetadata)

        let renameIntegrity = try await index.executeNoteCommit(
            label: "rename:\(oldRelativePath)->\(uniqueNew)",
            relativePath: uniqueNew,
            document: documentToPersist,
            textURL: newTxt,
            metaURL: newMeta,
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: relationshipIndex,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex,
            deletePathsAfterCommit: [oldTxt, oldMeta].filter { FileManager.default.fileExists(atPath: $0.path) }
        )
        await index.logIfIntegrityIssues(renameIntegrity)

        return uniqueNew
    }

    func loadRelationshipIndex() async throws -> RelationshipIndex {
        try await index.loadRelationshipIndex()
    }

    /// Returns persisted note-link relationship count (source of truth for graph derivation work size).
    func noteLinkRelationshipCount() async throws -> Int {
        let relationshipIndex = try await index.loadRelationshipIndex()
        return relationshipIndex.relationships.reduce(into: 0) { count, relationship in
            guard relationship.relationshipKind == "noteLink" else { return }
            guard case .note = relationship.target else { return }
            count += 1
        }
    }

    func loadFolderCatalog() async throws -> FolderCatalog {
        try await index.loadFolderCatalog()
    }

    /// Read-only consistency report (manifest, path index, `.txt` / `.meta.json` pairing).
    func validateVaultDrift() async throws -> VaultDriftReport {
        try await files.ensureVault()
        let manifest = try await loadOrRebuildManifest()
        let pathIndex = try await index.loadPathIndex()
        let txts = try await files.listRelativePathsOnDisk()
        return VaultDriftValidator.validate(
            vaultURL: vaultURL,
            manifest: manifest,
            pathIndex: pathIndex,
            txtPathsOnDisk: txts
        )
    }

    func createNote(named name: String, folderID: UUID) async throws -> (NoteDocument, String) {
        try await files.ensureVault()
        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        guard folderID == FolderCatalog.rootFolderID || folderCatalog.folder(id: folderID) != nil else {
            throw NoteRepositoryError.folderNotFound(folderID)
        }

        let dirPrefix = folderCatalog.relativeDirectoryPath(for: folderID)
        var stem = await files.slugify(name.isEmpty ? "untitled-note" : name)
        if stem.isEmpty { stem = "untitled-note" }
        let relativePath = try await files.uniqueAvailableRelativePath(inDirectoryPrefix: dirPrefix.isEmpty ? nil : dirPrefix, slugStem: stem)

        let text = ""
        let noteID = UUID()
        let metadata = NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
            noteID: noteID,
            blocks: [
                Block(
                    id: UUID().uuidString,
                    type: .heading,
                    range: TextRange(start: 0, length: 0),
                    level: 1,
                    icon: nil
                )
            ],
            spans: []
        )

        let document = NoteDocument(text: text, metadata: metadata)

        try VaultPath.validateRelativePath(relativePath)
        try VaultPath.ensureParentDirectories(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath)

        let normalized = RangeNormalizer.normalize(metadata: document.metadata, for: document.text)
        let documentToPersist = NoteDocument(text: document.text, metadata: normalized.normalizedMetadata)
        NoteIntegrity.logIfInvalid(document: documentToPersist)

        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "txt")
        let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "meta.json")

        var manifest = await index.loadManifestFromDiskOnly() ?? VaultManifest()
        manifest.ensureSchemaVersionIsCurrent()
        let title = VaultPath.displayTitle(forRelativePath: relativePath)
        manifest.upsert(noteID: documentToPersist.metadata.noteID, relativePath: relativePath, title: title)

        var graph = try await index.loadLinkGraph()
        graph.setOutgoing(from: documentToPersist.metadata.noteID, to: [])

        var relationshipIndex = try await index.loadRelationshipIndex()
        updateRelationshipIndex(&relationshipIndex, for: documentToPersist)

        var pathIndex = try await index.loadPathIndex()
        pathIndex.upsert(
            noteID: documentToPersist.metadata.noteID,
            folderID: folderID,
            relativePath: relativePath
        )

        _ = try await index.executeNoteCommit(
            label: "create:\(relativePath)",
            relativePath: relativePath,
            document: documentToPersist,
            textURL: textURL,
            metaURL: metaURL,
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: relationshipIndex,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex,
            deletePathsAfterCommit: []
        )
        return (documentToPersist, relativePath)
    }

    private func loadOrRebuildManifest() async throws -> VaultManifest {
        let manifest: VaultManifest
        if let decoded = await index.loadManifestFromDiskOnly() {
            manifest = try await reconcileManifestWithDisk(decoded)
        } else {
            manifest = try await rebuildManifestFromDisk()
        }
        try await materializeMissingSidecars(for: manifest)
        return manifest
    }

    /// Writes `.meta.json` for manifest entries whose sidecar is missing or undecodable. Non-fatal per note.
    private func materializeMissingSidecars(for manifest: VaultManifest) async throws {
        let pathIndex = try await index.loadPathIndex()
        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        let folderByNote = Dictionary(uniqueKeysWithValues: pathIndex.entries.map { ($0.noteID, $0.folderID) })
        let decoder = JSONDecoder()

        for entry in manifest.entries {
            let txtURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: entry.relativePath, extension: "txt")
            let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: entry.relativePath, extension: "meta.json")
            guard FileManager.default.fileExists(atPath: txtURL.path) else { continue }
            var needsWrite = !FileManager.default.fileExists(atPath: metaURL.path)
            if !needsWrite, let data = try? Data(contentsOf: metaURL) {
                needsWrite = (try? decoder.decode(NoteMetadata.self, from: data)) == nil
            }
            guard needsWrite else { continue }
            let folderID = folderByNote[entry.noteID] ?? Self.inferFolderID(forNotePath: entry.relativePath, folderCatalog: folderCatalog)
            do {
                let doc = try await files.loadNote(relativePath: entry.relativePath, fallbackNoteID: entry.noteID).document
                _ = try await save(doc, asRelativePath: entry.relativePath, folderID: folderID)
            } catch {
                Logger.vault.error("materializeMissingSidecars failed path=\(entry.relativePath, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func reconcileManifestWithDisk(_ manifest: VaultManifest) async throws -> VaultManifest {
        var next = manifest
        next.ensureSchemaVersionIsCurrent()
        let originalCount = next.entries.count
        next.entries.removeAll { entry in
            let txt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: entry.relativePath, extension: "txt")
            return !FileManager.default.fileExists(atPath: txt.path)
        }
        if next.entries.count != originalCount {
            next.isDirty = true
        }
        let removed = max(0, originalCount - next.entries.count)

        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()

        let onDisk = try await files.listRelativePathsOnDisk()
        let known = Set(next.entries.map(\.relativePath))
        var added = 0
        let metaDecoder = JSONDecoder()
        for rel in onDisk where !known.contains(rel) {
            let allocatedID: UUID
            if let meta = try NoteIdentityResolution.decodeSidecarMetadata(
                vaultRoot: vaultURL,
                relativePath: rel,
                decoder: metaDecoder
            ) {
                allocatedID = meta.noteID
            } else {
                allocatedID = UUID()
            }
            let title = VaultPath.displayTitle(forRelativePath: rel)
            next.upsert(noteID: allocatedID, relativePath: rel, title: title)
            added += 1
            let folderID = Self.inferFolderID(forNotePath: rel, folderCatalog: folderCatalog)
            let doc = try await files.loadNote(relativePath: rel, fallbackNoteID: allocatedID).document
            let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: rel, extension: "meta.json")
            if !FileManager.default.fileExists(atPath: metaURL.path) {
                try await save(doc, asRelativePath: rel, folderID: folderID)
            }
        }
        VaultTelemetry.logManifestReconcile(removed: removed, added: added)
        if next.isDirty || removed > 0 || added > 0 {
            await index.invalidateCaches()
        }
        return next
    }

    private func rebuildManifestFromDisk() async throws -> VaultManifest {
        try await files.ensureVault()
        var manifest = VaultManifest()
        manifest.ensureSchemaVersionIsCurrent()
        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        let paths = try await files.listRelativePathsOnDisk()
        let metaDecoder = JSONDecoder()
        for rel in paths {
            let allocatedID: UUID
            if let meta = try NoteIdentityResolution.decodeSidecarMetadata(
                vaultRoot: vaultURL,
                relativePath: rel,
                decoder: metaDecoder
            ) {
                allocatedID = meta.noteID
            } else {
                allocatedID = UUID()
            }
            let title = VaultPath.displayTitle(forRelativePath: rel)
            manifest.upsert(noteID: allocatedID, relativePath: rel, title: title)
            let folderID = Self.inferFolderID(forNotePath: rel, folderCatalog: folderCatalog)
            let doc = try await files.loadNote(relativePath: rel, fallbackNoteID: allocatedID).document
            let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: rel, extension: "meta.json")
            if !FileManager.default.fileExists(atPath: metaURL.path) {
                try await save(doc, asRelativePath: rel, folderID: folderID)
            }
        }
        let graph = try await index.loadLinkGraph()
        let rel = try await index.loadRelationshipIndex()
        folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        let pathIndex = try await index.loadPathIndex()
        let integrity = try await index.commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        )
        await index.logIfIntegrityIssues(integrity)
        return manifest
    }

    private func applyRelativePathPrefixRewrite(
        from oldPrefix: String,
        to newPrefix: String,
        manifest: inout VaultManifest,
        pathIndex: inout PathIndex
    ) {
        var manifestTouched = false
        for i in manifest.entries.indices {
            let path = manifest.entries[i].relativePath
            if let updated = Self.rewritePath(path, oldPrefix: oldPrefix, newPrefix: newPrefix) {
                manifest.entries[i].relativePath = updated
                manifestTouched = true
            }
        }
        if manifestTouched {
            manifest.isDirty = true
        }
        var pathTouched = false
        for i in pathIndex.entries.indices {
            let path = pathIndex.entries[i].relativePath
            if let updated = Self.rewritePath(path, oldPrefix: oldPrefix, newPrefix: newPrefix) {
                pathIndex.entries[i].relativePath = updated
                pathTouched = true
            }
        }
        if pathTouched {
            pathIndex.isDirty = true
        }
    }

    func createFolder(parentID: UUID, name: String) async throws -> UUID {
        try await files.ensureVault()
        guard parentID == FolderCatalog.rootFolderID else {
            throw NoteRepositoryError.invalidFolderMove
        }
        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        let id = try folderCatalog.addFolder(parentID: parentID, name: name)
        let dir = folderCatalog.directoryURL(vaultRoot: vaultURL, folderID: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = try await loadOrRebuildManifest()
        let graph = try await index.loadLinkGraph()
        let rel = try await index.loadRelationshipIndex()
        let pathIndex = try await index.loadPathIndex()
        await index.logIfIntegrityIssues(try await index.commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        ))
        return id
    }

    func deleteFolder(id: UUID) async throws {
        try await files.ensureVault()
        guard id != FolderCatalog.rootFolderID else {
            throw NoteRepositoryError.invalidFolderMove
        }
        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        guard folderCatalog.folder(id: id) != nil else {
            throw NoteRepositoryError.folderNotFound(id)
        }

        var folderIDsToDelete = [id]
        var cursor = 0
        while cursor < folderIDsToDelete.count {
            let parentID = folderIDsToDelete[cursor]
            let children = folderCatalog.childFolders(of: parentID).map(\.id)
            folderIDsToDelete.append(contentsOf: children)
            cursor += 1
        }

        var pathIndex = try await index.loadPathIndex()
        let folderIDSet = Set(folderIDsToDelete)
        let entriesToDelete = pathIndex.entries.filter { folderIDSet.contains($0.folderID) }
        let noteIDsToDelete = Set(entriesToDelete.map(\.noteID))
        let noteRelativePathsByID = Dictionary(uniqueKeysWithValues: entriesToDelete.map { ($0.noteID, $0.relativePath) })

        let manifest = try await loadOrRebuildManifest()
        var updatedManifest = manifest
        for noteID in noteIDsToDelete {
            updatedManifest.remove(noteID: noteID)
        }

        pathIndex.entries.removeAll { folderIDSet.contains($0.folderID) }
        if !entriesToDelete.isEmpty {
            pathIndex.isDirty = true
        }

        var graph = try await index.loadLinkGraph()
        for noteID in noteIDsToDelete {
            graph.removeNote(noteID)
        }

        var rel = try await index.loadRelationshipIndex()
        for noteID in noteIDsToDelete {
            rel.removeAllInvolvingNote(noteID)
        }

        var toDelete: [URL] = []
        for noteID in noteIDsToDelete {
            if let relPath = noteRelativePathsByID[noteID] {
                let txt = VaultPath.fileURL(
                    vaultRoot: vaultURL,
                    relativePathWithoutExtension: relPath,
                    extension: "txt"
                )
                let meta = VaultPath.fileURL(
                    vaultRoot: vaultURL,
                    relativePathWithoutExtension: relPath,
                    extension: "meta.json"
                )
                if FileManager.default.fileExists(atPath: txt.path) {
                    toDelete.append(txt)
                }
                if FileManager.default.fileExists(atPath: meta.path) {
                    toDelete.append(meta)
                }
            }
            let aux = VaultPaths.auxDirectory(vaultURL: vaultURL, noteID: noteID)
            if FileManager.default.fileExists(atPath: aux.path) {
                toDelete.append(aux)
            }
        }

        let folderDepthByID = Dictionary(
            uniqueKeysWithValues: folderIDsToDelete.map { folderID in
                let depth = folderCatalog.relativeDirectoryPath(for: folderID).split(separator: "/").count
                return (folderID, depth)
            }
        )
        let sortedFolderIDsForRemoval = folderIDsToDelete.sorted {
            folderDepthByID[$0, default: 0] > folderDepthByID[$1, default: 0]
        }
        for folderID in sortedFolderIDsForRemoval {
            let dir = folderCatalog.directoryURL(vaultRoot: vaultURL, folderID: folderID)
            if FileManager.default.fileExists(atPath: dir.path) {
                toDelete.append(dir)
            }
            try folderCatalog.removeFolderEntry(id: folderID)
        }

        // Keep deletion list stable and avoid duplicate file-system operations.
        var uniqueToDelete: [URL] = []
        var seenDeletePaths = Set<String>()
        for url in toDelete where seenDeletePaths.insert(url.path).inserted {
            uniqueToDelete.append(url)
        }

        await index.logIfIntegrityIssues(try await index.commitIndexOnly(
            manifest: updatedManifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex,
            deletePathsAfterCommit: uniqueToDelete
        ))
    }

    func renameFolder(id: UUID, newName: String) async throws {
        try await files.ensureVault()
        guard id != FolderCatalog.rootFolderID else {
            throw NoteRepositoryError.invalidFolderName("root")
        }
        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        try folderCatalog.renameFolder(id: id, newName: newName)
        let manifest = try await loadOrRebuildManifest()
        let pathIndex = try await index.loadPathIndex()
        let graph = try await index.loadLinkGraph()
        let rel = try await index.loadRelationshipIndex()
        await index.logIfIntegrityIssues(try await index.commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        ))
    }

    func moveFolder(id: UUID, newParentID: UUID) async throws {
        try await files.ensureVault()
        guard newParentID == FolderCatalog.rootFolderID else {
            throw NoteRepositoryError.invalidFolderMove
        }
        guard id != FolderCatalog.rootFolderID else {
            throw NoteRepositoryError.invalidFolderMove
        }
        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        let oldPrefix = folderCatalog.relativeDirectoryPath(for: id)
        let oldURL = folderCatalog.directoryURL(vaultRoot: vaultURL, folderID: id)
        try folderCatalog.moveFolder(id: id, newParentID: newParentID)
        let newPrefix = folderCatalog.relativeDirectoryPath(for: id)
        let newURL = folderCatalog.directoryURL(vaultRoot: vaultURL, folderID: id)

        if oldPrefix != newPrefix {
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: newURL.path) {
                    throw NoteRepositoryError.invalidFolderMove
                }
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            } else if !FileManager.default.fileExists(atPath: newURL.path) {
                try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
            }
        }

        var manifest = try await loadOrRebuildManifest()
        var pathIndex = try await index.loadPathIndex()
        if oldPrefix != newPrefix {
            applyRelativePathPrefixRewrite(from: oldPrefix, to: newPrefix, manifest: &manifest, pathIndex: &pathIndex)
        }
        let graph = try await index.loadLinkGraph()
        let rel = try await index.loadRelationshipIndex()
        await index.logIfIntegrityIssues(try await index.commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        ))
    }

    func moveNote(noteID: UUID, toFolderID: UUID) async throws {
        try await files.ensureVault()
        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        guard toFolderID == FolderCatalog.rootFolderID || folderCatalog.folder(id: toFolderID) != nil else {
            throw NoteRepositoryError.folderNotFound(toFolderID)
        }

        let doc = try await loadNote(noteID: noteID).document
        let manifestSnapshot = try await loadOrRebuildManifest()
        guard let manifestEntry = manifestSnapshot.entry(noteID: noteID) else {
            throw NoteRepositoryError.noteNotFoundByID(noteID)
        }
        let oldPath = manifestEntry.relativePath

        let folderID = (try await index.loadPathIndex()).entries.first { $0.noteID == noteID }?.folderID ?? FolderCatalog.rootFolderID
        guard folderID != toFolderID else { return }

        let dirPrefix = folderCatalog.relativeDirectoryPath(for: toFolderID)
        let stem = (oldPath as NSString).lastPathComponent
        let uniqueNew = try await files.uniqueAvailableRelativePath(inDirectoryPrefix: dirPrefix.isEmpty ? nil : dirPrefix, slugStem: stem)

        if uniqueNew == oldPath {
            var pathIndex = try await index.loadPathIndex()
            pathIndex.upsert(noteID: noteID, folderID: toFolderID, relativePath: oldPath)
            let manifest = try await loadOrRebuildManifest()
            let graph = try await index.loadLinkGraph()
            let rel = try await index.loadRelationshipIndex()
            await index.logIfIntegrityIssues(try await index.commitIndexOnly(
                manifest: manifest,
                linkGraph: graph,
                relationshipIndex: rel,
                folderCatalog: folderCatalog,
                pathIndex: pathIndex
            ))
            return
        }

        let oldTxt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: oldPath, extension: "txt")
        let oldMeta = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: oldPath, extension: "meta.json")
        let newTxt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: uniqueNew, extension: "txt")
        let newMeta = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: uniqueNew, extension: "meta.json")
        try VaultPath.ensureParentDirectories(vaultRoot: vaultURL, relativePathWithoutExtension: uniqueNew)

        var manifest = await index.loadManifestFromDiskOnly() ?? VaultManifest()
        manifest.ensureSchemaVersionIsCurrent()
        let title = manifestEntry.title ?? VaultPath.displayTitle(forRelativePath: uniqueNew)
        manifest.upsert(noteID: noteID, relativePath: uniqueNew, title: title)

        var graph = try await index.loadLinkGraph()
        graph.setOutgoing(from: noteID, to: doc.metadata.links.map(\.targetNoteID))
        var relationshipIndex = try await index.loadRelationshipIndex()
        updateRelationshipIndex(&relationshipIndex, for: doc)

        var pathIndex = try await index.loadPathIndex()
        pathIndex.upsert(noteID: noteID, folderID: toFolderID, relativePath: uniqueNew)

        let normalized = RangeNormalizer.normalize(metadata: doc.metadata, for: doc.text)
        let documentToPersist = NoteDocument(text: doc.text, metadata: normalized.normalizedMetadata)

        let oldPaths: [URL] = [oldTxt, oldMeta]
        await index.logIfIntegrityIssues(try await index.executeNoteCommit(
            label: "moveNote:\(oldPath)->\(uniqueNew)",
            relativePath: uniqueNew,
            document: documentToPersist,
            textURL: newTxt,
            metaURL: newMeta,
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: relationshipIndex,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex,
            deletePathsAfterCommit: oldPaths.filter { FileManager.default.fileExists(atPath: $0.path) }
        ))
    }

    func deleteNote(noteID: UUID) async throws {
        try await files.ensureVault()
        var manifest = try await loadOrRebuildManifest()
        guard let entry = manifest.entry(noteID: noteID) else {
            throw NoteRepositoryError.noteNotFoundByID(noteID)
        }
        let relPath = entry.relativePath
        manifest.remove(noteID: noteID)

        var pathIndex = try await index.loadPathIndex()
        pathIndex.remove(noteID: noteID)

        var graph = try await index.loadLinkGraph()
        graph.removeNote(noteID)

        var relationshipIndex = try await index.loadRelationshipIndex()
        relationshipIndex.removeAllInvolvingNote(noteID)

        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()

        let txt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relPath, extension: "txt")
        let meta = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relPath, extension: "meta.json")
        let aux = VaultPaths.auxDirectory(vaultURL: vaultURL, noteID: noteID)
        var toDelete: [URL] = [txt, meta].filter { FileManager.default.fileExists(atPath: $0.path) }
        if FileManager.default.fileExists(atPath: aux.path) {
            toDelete.append(aux)
        }

        await index.logIfIntegrityIssues(try await index.commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: relationshipIndex,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex,
            deletePathsAfterCommit: toDelete
        ))
    }
}

import CryptoKit
import Foundation
import MiranNotesCore
import os.log

/// Result of loading a note from disk, including any structural repair warnings.
struct NoteLoadResult {
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
    case duplicateFolderName(String)
    case invalidFolderMove
    case folderNotEmpty(UUID)

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
        case let .duplicateFolderName(name):
            return "A folder with this name already exists: \(name)"
        case .invalidFolderMove:
            return "That folder cannot be moved there."
        case let .folderNotEmpty(id):
            return "Folder is not empty (contains notes or folders): \(id.uuidString)"
        }
    }
}

struct NoteSummary: Identifiable, Hashable {
    var id: UUID { noteID }
    var noteID: UUID
    var title: String
    /// Path under the vault root without extension, e.g. `work/a` or `note`.
    var relativePath: String
    /// Folder that owns this note in `FolderCatalog` (vault root uses `FolderCatalog.rootFolderID`).
    var folderID: UUID
}

/// One incoming link from a source note (backlink row in the UI).
struct BacklinkItem: Identifiable {
    var id: UUID { sourceNoteID }
    var sourceNoteID: UUID
    var title: String
    var relativePath: String
    var snippet: String
    /// UTF-16 range of the link in the **source** note’s body (for scroll-to-link).
    var linkRange: MiranNotesCore.TextRange
}

actor NoteRepository {
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

    /// Resume interrupted commits from a previous run. Call early when opening a vault.
    func performStartupRecovery() throws -> VaultRecoverySummary {
        try ensureVault()
        return try VaultCommitCoordinator.recoverPendingCommits(vaultRoot: vaultURL)
    }

    /// Legacy single-segment validation (flat notes only).
    nonisolated static func validateBaseName(_ baseName: String) throws {
        try VaultPath.validateSingleSegment(baseName)
    }

    func ensureVault() throws {
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: VaultPaths.miranDirectory(vaultURL: vaultURL), withIntermediateDirectories: true)
    }

    func listNotes() throws -> [NoteSummary] {
        try ensureVault()
        var manifest = try loadOrRebuildManifest()
        manifest.schemaVersion = max(manifest.schemaVersion, VaultManifest.currentSchemaVersion)
        let encodedManifest = try encoder.encode(manifest)
        let diskManifest = try? Data(contentsOf: manifestURL())
        let manifestChanged = encodedManifest != diskManifest

        let pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        let folderByNote = Dictionary(uniqueKeysWithValues: pathIndex.entries.map { ($0.noteID, $0.folderID) })

        if manifestChanged {
            let graph = try loadLinkGraph()
            let rel = try loadRelationshipIndex()
            let folderCatalog = try loadFolderCatalog()
            let integrity = try commitIndexOnly(
                manifest: manifest,
                linkGraph: graph,
                relationshipIndex: rel,
                folderCatalog: folderCatalog,
                pathIndex: pathIndex
            )
            logIfIntegrityIssues(integrity)
        }

        return manifest.entries
            .sorted { $0.relativePath.lowercased() < $1.relativePath.lowercased() }
            .map { entry in
                let title = entry.title ?? entry.relativePath.split(separator: "/").last.map(String.init) ?? entry.relativePath
                let displayTitle = title.replacingOccurrences(of: "-", with: " ").capitalized
                return NoteSummary(
                    noteID: entry.noteID,
                    title: displayTitle,
                    relativePath: entry.relativePath,
                    folderID: folderByNote[entry.noteID] ?? FolderCatalog.rootFolderID
                )
            }
    }

    func loadManifest() throws -> VaultManifest {
        try loadOrRebuildManifest()
    }

    func linkResolver() throws -> LinkResolver {
        LinkResolver(manifest: try loadOrRebuildManifest())
    }

    func loadLinkGraph() throws -> LinkGraph {
        try VaultIndexSubsystem.loadLinkGraph(vaultURL: vaultURL, decoder: decoder)
    }

    func saveLinkGraph(_ graph: LinkGraph) throws {
        try ensureVault()
        var g = graph
        g.isDirty = true
        let manifest = try loadOrRebuildManifest()
        let rel = try loadRelationshipIndex()
        let folderCatalog = try loadFolderCatalog()
        let pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        let integrity = try commitIndexOnly(
            manifest: manifest,
            linkGraph: g,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        )
        logIfIntegrityIssues(integrity)
    }

    func updateLinkGraph(sourceNoteID: UUID, targets: [UUID]) throws {
        var graph = try loadLinkGraph()
        graph.setOutgoing(from: sourceNoteID, to: targets)
        try saveLinkGraph(graph)
    }

    func rebuildLinkGraphFull() throws -> VaultIntegrityResult {
        let manifest = try loadOrRebuildManifest()
        var graph = LinkGraph()
        for entry in manifest.entries {
            let doc = try loadNote(relativePath: entry.relativePath).document
            graph.setOutgoing(from: entry.noteID, to: doc.metadata.links.map(\.targetNoteID))
        }
        let rel = try loadRelationshipIndex()
        let folderCatalog = try loadFolderCatalog()
        let pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        let integrity = try commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        )
        Logger.vault.info("Rebuilt link graph for \(manifest.entries.count, privacy: .public) notes")
        return integrity
    }

    /// Creates a note at vault root (folder = root).
    func createNote(named name: String) throws -> (NoteDocument, String) {
        try createNote(named: name, folderID: FolderCatalog.rootFolderID)
    }

    func loadNote(noteID: UUID) throws -> NoteLoadResult {
        let manifest = try loadOrRebuildManifest()
        guard let entry = manifest.entry(noteID: noteID) else {
            throw NoteRepositoryError.noteNotFoundByID(noteID)
        }
        return try loadNote(relativePath: entry.relativePath)
    }

    func loadNote(relativePath: String) throws -> NoteLoadResult {
        try VaultPath.validateRelativePath(relativePath)
        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "txt")
        let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "meta.json")

        guard FileManager.default.fileExists(atPath: textURL.path) else {
            throw NoteRepositoryError.noteNotFound(relativePath)
        }

        let text = (try? String(contentsOf: textURL, encoding: .utf8)) ?? ""
        let metadata: NoteMetadata

        if let data = try? Data(contentsOf: metaURL),
           let decoded = try? decoder.decode(NoteMetadata.self, from: data) {
            metadata = MetadataSchema.migrate(decoded)
        } else {
            metadata = NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: UUID(),
                blocks: [
                    Block(
                        id: UUID().uuidString,
                        type: .paragraph,
                        range: TextRange(start: 0, length: text.utf16.count),
                        level: nil,
                        icon: nil
                    )
                ],
                spans: []
            )
        }

        let (repaired, repairWarnings) = Self.documentAfterLoadRepair(text: text, metadata: metadata)
        let withId = NoteDocument(text: repaired.text, metadata: repaired.metadata)
        if !repairWarnings.isEmpty {
            VaultTelemetry.logRepairWarnings(count: repairWarnings.count)
        }
        NoteIntegrity.logIfInvalid(document: withId)
        return NoteLoadResult(document: withId, repairWarnings: repairWarnings)
    }

    /// Legacy API for tests and callers still using a single path segment.
    func loadNote(baseName: String) throws -> NoteLoadResult {
        try loadNote(relativePath: baseName)
    }

    /// Raw UTF-8 text from the note `.txt` file only (no metadata load or structural repair). Used for search indexing.
    func readRawNoteText(relativePath: String) throws -> String {
        try VaultPath.validateRelativePath(relativePath)
        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "txt")
        guard FileManager.default.fileExists(atPath: textURL.path) else {
            throw NoteRepositoryError.noteNotFound(relativePath)
        }
        return (try? String(contentsOf: textURL, encoding: .utf8)) ?? ""
    }

    /// In-memory search index: `noteID` → raw body text (UTF-8) for every manifest entry. Match with `text.lowercased().contains(query)`.
    func buildBodySearchIndex() throws -> [UUID: String] {
        let manifest = try loadOrRebuildManifest()
        var result: [UUID: String] = [:]
        result.reserveCapacity(manifest.entries.count)
        for entry in manifest.entries {
            let raw: String
            do {
                raw = try readRawNoteText(relativePath: entry.relativePath)
            } catch {
                continue
            }
            result[entry.noteID] = raw
        }
        return result
    }

    func noteModifiedDate(relativePath: String) throws -> Date? {
        try VaultPath.validateRelativePath(relativePath)
        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "txt")
        let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "meta.json")
        let fm = FileManager.default

        let textDate = (try? fm.attributesOfItem(atPath: textURL.path))?[.modificationDate] as? Date
        let metaDate = (try? fm.attributesOfItem(atPath: metaURL.path))?[.modificationDate] as? Date

        switch (textDate, metaDate) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    func noteRevisionToken(relativePath: String) throws -> DocumentRevisionToken? {
        try VaultPath.validateRelativePath(relativePath)
        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "txt")
        let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "meta.json")
        guard FileManager.default.fileExists(atPath: textURL.path) else {
            return nil
        }

        let textData = (try? Data(contentsOf: textURL)) ?? Data()
        let metaData = (try? Data(contentsOf: metaURL)) ?? Data()
        var hasher = SHA256()
        hasher.update(data: textData)
        hasher.update(data: Data([0]))
        hasher.update(data: metaData)
        let digest = hasher.finalize().hexString
        return DocumentRevisionToken(rawValue: digest)
    }

    @discardableResult
    func save(_ note: NoteDocument, asRelativePath relativePath: String, folderID: UUID = FolderCatalog.rootFolderID) throws -> VaultIntegrityResult {
        try VaultPath.validateRelativePath(relativePath)
        try VaultPath.ensureParentDirectories(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath)
        try ensureVault()

        let normalized = RangeNormalizer.normalize(metadata: note.metadata, for: note.text)
        let documentToPersist = NoteDocument(
            text: note.text,
            metadata: normalized.normalizedMetadata
        )
        NoteIntegrity.logIfInvalid(document: documentToPersist)

        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "txt")
        let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: "meta.json")

        var manifest = loadManifestFromDiskOnly() ?? VaultManifest()
        manifest.schemaVersion = VaultManifest.currentSchemaVersion
        let lastSegment = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        let title = lastSegment.replacingOccurrences(of: "-", with: " ").capitalized
        manifest.upsert(noteID: documentToPersist.metadata.noteID, relativePath: relativePath, title: title)

        var graph = try loadLinkGraph()
        let targets = documentToPersist.metadata.links.map(\.targetNoteID)
        graph.setOutgoing(from: documentToPersist.metadata.noteID, to: targets)

        var relationshipIndex = try loadRelationshipIndex()
        let linkRelationships = documentToPersist.metadata.links.map { link in
            LinkRelationship(
                sourceNoteID: documentToPersist.metadata.noteID,
                target: .note(noteID: link.targetNoteID),
                relationshipKind: "noteLink"
            )
        }
        let artifactRelationships = documentToPersist.metadata.artifacts.map { artifact in
            LinkRelationship(
                sourceNoteID: documentToPersist.metadata.noteID,
                target: .artifact(noteID: documentToPersist.metadata.noteID, artifactID: artifact.id, kind: artifact.kind),
                relationshipKind: "artifactLink"
            )
        }
        relationshipIndex.replaceLinks(
            from: documentToPersist.metadata.noteID,
            with: linkRelationships + artifactRelationships
        )

        var folderCatalog = try loadFolderCatalog()
        folderCatalog.ensureRoot()
        var pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        pathIndex.upsert(
            noteID: documentToPersist.metadata.noteID,
            folderID: folderID,
            relativePath: relativePath
        )

        return try executeNoteCommit(
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

    /// Flat save at vault root (single segment).
    @discardableResult
    func save(_ note: NoteDocument, asBaseName baseName: String) throws -> VaultIntegrityResult {
        try Self.validateBaseName(baseName)
        return try save(note, asRelativePath: baseName, folderID: FolderCatalog.rootFolderID)
    }

    func renameNote(from oldRelativePath: String, to newTitle: String) throws -> String {
        try VaultPath.validateRelativePath(oldRelativePath)
        try ensureVault()
        let oldTxt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: oldRelativePath, extension: "txt")
        guard FileManager.default.fileExists(atPath: oldTxt.path) else {
            throw NoteRepositoryError.noteNotFound(oldRelativePath)
        }

        let doc = try loadNote(relativePath: oldRelativePath).document
        let folderID = (try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)).entries.first { $0.noteID == doc.metadata.noteID }?.folderID ?? FolderCatalog.rootFolderID

        let parentDir = (oldRelativePath as NSString).deletingLastPathComponent
        let stemSlug: String
        if newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stemSlug = (oldRelativePath as NSString).lastPathComponent
        } else {
            stemSlug = slugify(newTitle)
        }
        if stemSlug.isEmpty {
            throw NoteRepositoryError.invalidRelativePath(newTitle)
        }

        let newRelativePath: String = parentDir.isEmpty ? stemSlug : "\(parentDir)/\(stemSlug)"

        if newRelativePath == oldRelativePath {
            var manifest = loadManifestFromDiskOnly() ?? VaultManifest()
            manifest.schemaVersion = VaultManifest.currentSchemaVersion
            manifest.upsert(noteID: doc.metadata.noteID, relativePath: oldRelativePath, title: newTitle)
            let graph = try loadLinkGraph()
            let relationshipIndex = try loadRelationshipIndex()
            let folderCatalog = try loadFolderCatalog()
            let pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
            let integrity = try commitIndexOnly(
                manifest: manifest,
                linkGraph: graph,
                relationshipIndex: relationshipIndex,
                folderCatalog: folderCatalog,
                pathIndex: pathIndex
            )
            logIfIntegrityIssues(integrity)
            return oldRelativePath
        }

        let uniqueNew = try uniqueAvailableRelativePath(inDirectoryPrefix: parentDir.isEmpty ? nil : parentDir, slugStem: stemSlug)

        let oldMeta = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: oldRelativePath, extension: "meta.json")
        let newTxt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: uniqueNew, extension: "txt")
        let newMeta = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: uniqueNew, extension: "meta.json")

        try VaultPath.ensureParentDirectories(vaultRoot: vaultURL, relativePathWithoutExtension: uniqueNew)

        var manifest = loadManifestFromDiskOnly() ?? VaultManifest()
        manifest.schemaVersion = VaultManifest.currentSchemaVersion
        manifest.upsert(noteID: doc.metadata.noteID, relativePath: uniqueNew, title: newTitle)

        var graph = try loadLinkGraph()
        graph.setOutgoing(from: doc.metadata.noteID, to: doc.metadata.links.map(\.targetNoteID))
        var relationshipIndex = try loadRelationshipIndex()
        let linkRelationships = doc.metadata.links.map { link in
            LinkRelationship(
                sourceNoteID: doc.metadata.noteID,
                target: .note(noteID: link.targetNoteID),
                relationshipKind: "noteLink"
            )
        }
        let artifactRelationships = doc.metadata.artifacts.map { artifact in
            LinkRelationship(
                sourceNoteID: doc.metadata.noteID,
                target: .artifact(noteID: doc.metadata.noteID, artifactID: artifact.id, kind: artifact.kind),
                relationshipKind: "artifactLink"
            )
        }
        relationshipIndex.replaceLinks(from: doc.metadata.noteID, with: linkRelationships + artifactRelationships)

        var folderCatalog = try loadFolderCatalog()
        folderCatalog.ensureRoot()
        var pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        pathIndex.upsert(noteID: doc.metadata.noteID, folderID: folderID, relativePath: uniqueNew)

        let normalized = RangeNormalizer.normalize(metadata: doc.metadata, for: doc.text)
        let documentToPersist = NoteDocument(text: doc.text, metadata: normalized.normalizedMetadata)

        logIfIntegrityIssues(try executeNoteCommit(
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
        ))

        return uniqueNew
    }

    // MARK: - Manifest

    private func manifestURL() -> URL {
        VaultPaths.manifestURL(vaultURL: vaultURL)
    }

    private func loadOrRebuildManifest() throws -> VaultManifest {
        let url = manifestURL()
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(VaultManifest.self, from: data) {
            return try reconcileManifestWithDisk(decoded)
        }
        return try rebuildManifestFromDisk()
    }

    private func reconcileManifestWithDisk(_ manifest: VaultManifest) throws -> VaultManifest {
        var next = manifest
        if next.schemaVersion < VaultManifest.currentSchemaVersion {
            next.schemaVersion = VaultManifest.currentSchemaVersion
        }
        let originalCount = next.entries.count
        next.entries.removeAll { entry in
            let txt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: entry.relativePath, extension: "txt")
            return !FileManager.default.fileExists(atPath: txt.path)
        }
        let removed = max(0, originalCount - next.entries.count)

        let onDisk = try listRelativePathsOnDisk()
        let known = Set(next.entries.map(\.relativePath))
        var added = 0
        for rel in onDisk where !known.contains(rel) {
            let doc = try loadNote(relativePath: rel).document
            let last = rel.split(separator: "/").last.map(String.init) ?? rel
            let title = last.replacingOccurrences(of: "-", with: " ").capitalized
            next.upsert(noteID: doc.metadata.noteID, relativePath: rel, title: title)
            added += 1
            let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: rel, extension: "meta.json")
            if !FileManager.default.fileExists(atPath: metaURL.path) {
                try save(doc, asRelativePath: rel, folderID: FolderCatalog.rootFolderID)
            }
        }
        VaultTelemetry.logManifestReconcile(removed: removed, added: added)
        return next
    }

    private func rebuildManifestFromDisk() throws -> VaultManifest {
        try ensureVault()
        var manifest = VaultManifest()
        manifest.schemaVersion = VaultManifest.currentSchemaVersion
        let paths = try listRelativePathsOnDisk()
        for rel in paths {
            let doc = try loadNote(relativePath: rel).document
            let metaURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: rel, extension: "meta.json")
            if !FileManager.default.fileExists(atPath: metaURL.path) {
                try save(doc, asRelativePath: rel, folderID: FolderCatalog.rootFolderID)
            }
            let last = rel.split(separator: "/").last.map(String.init) ?? rel
            let title = last.replacingOccurrences(of: "-", with: " ").capitalized
            manifest.upsert(noteID: doc.metadata.noteID, relativePath: rel, title: title)
        }
        let graph = try loadLinkGraph()
        let rel = try loadRelationshipIndex()
        let folderCatalog = try loadFolderCatalog()
        let pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        let integrity = try commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        )
        logIfIntegrityIssues(integrity)
        return manifest
    }

    private func listRelativePathsOnDisk() throws -> [String] {
        try ensureVault()
        var results: [String] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        for case let item as URL in enumerator {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            guard item.pathExtension.lowercased() == "txt" else { continue }
            guard let rel = relativePathFromVaultNoteTextURL(item) else { continue }
            results.append(rel)
        }
        return results.sorted { $0.lowercased() < $1.lowercased() }
    }

    /// Returns `relativePath` without extension for a `.txt` file under the vault.
    private func relativePathFromVaultNoteTextURL(_ file: URL) -> String? {
        let vaultPath = vaultURL.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(vaultPath) else { return nil }
        var sub = String(filePath.dropFirst(vaultPath.count))
        if sub.hasPrefix("/") { sub.removeFirst() }
        guard sub.lowercased().hasSuffix(".txt") else { return nil }
        sub = String(sub.dropLast(4))
        let parts = sub.split(separator: "/").map(String.init)
        if parts.contains(".miran") || parts.contains("_aux") { return nil }
        if let first = parts.first, VaultPath.reservedTopLevel.contains(first) { return nil }
        return sub
    }

    private func loadManifestFromDiskOnly() -> VaultManifest? {
        let url = manifestURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(VaultManifest.self, from: data) else {
            return nil
        }
        return decoded
    }

    func loadRelationshipIndex() throws -> RelationshipIndex {
        try VaultIndexSubsystem.loadRelationshipIndex(vaultURL: vaultURL, decoder: decoder)
    }

    func loadFolderCatalog() throws -> FolderCatalog {
        try VaultIndexSubsystem.loadFolderCatalog(vaultURL: vaultURL, decoder: decoder)
    }

    private func loadFolderCatalogPrivate() throws -> FolderCatalog {
        try VaultIndexSubsystem.loadFolderCatalog(vaultURL: vaultURL, decoder: decoder)
    }

    func createNote(named name: String, folderID: UUID) throws -> (NoteDocument, String) {
        try ensureVault()
        var folderCatalog = try loadFolderCatalogPrivate()
        folderCatalog.ensureRoot()
        guard folderID == FolderCatalog.rootFolderID || folderCatalog.folder(id: folderID) != nil else {
            throw NoteRepositoryError.folderNotFound(folderID)
        }

        let dirPrefix = folderCatalog.relativeDirectoryPath(for: folderID)
        var stem = slugify(name.isEmpty ? "untitled-note" : name)
        if stem.isEmpty { stem = "untitled-note" }
        let relativePath = try uniqueAvailableRelativePath(inDirectoryPrefix: dirPrefix.isEmpty ? nil : dirPrefix, slugStem: stem)

        let text = ""
        let noteID = UUID()
        let metadata = NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
            noteID: noteID,
            blocks: [
                Block(
                    id: UUID().uuidString,
                    type: .paragraph,
                    range: TextRange(start: 0, length: 0),
                    level: nil,
                    icon: nil
                )
            ],
            spans: []
        )

        let document = NoteDocument(text: text, metadata: metadata)
        try save(document, asRelativePath: relativePath, folderID: folderID)
        return (document, relativePath)
    }

    private func logIfIntegrityIssues(_ result: VaultIntegrityResult) {
        guard !result.isClean else { return }
        for issue in result.issues {
            Logger.vault.error("Vault integrity: \(issue, privacy: .public)")
        }
    }

    private func runIntegrityAfterCommit(
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

    private func uniqueAvailableRelativePath(inDirectoryPrefix dirPrefix: String?, slugStem: String) throws -> String {
        var collision = 0
        var stem = slugStem
        while true {
            let rel: String
            if let p = dirPrefix, !p.isEmpty {
                rel = "\(p)/\(stem)"
            } else {
                rel = stem
            }
            try VaultPath.validateRelativePath(rel)
            let path = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: rel, extension: "txt")
            if !FileManager.default.fileExists(atPath: path.path) {
                return rel
            }
            collision += 1
            guard collision < 10_000 else {
                throw NoteRepositoryError.tooManyFilenameCollisions
            }
            stem = collision == 1 ? "\(slugStem)-2" : "\(slugStem)-\(collision + 1)"
        }
    }

    private func executeNoteCommit(
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

    // MARK: - Vault structure (folders / moves / delete)

    private func applyRelativePathPrefixRewrite(
        from oldPrefix: String,
        to newPrefix: String,
        manifest: inout VaultManifest,
        pathIndex: inout PathIndex
    ) {
        let oldRoot = oldPrefix.isEmpty ? "" : oldPrefix + "/"
        for i in manifest.entries.indices {
            let path = manifest.entries[i].relativePath
            guard path.hasPrefix(oldRoot) || path == oldPrefix else { continue }
            let suffix: String
            if path.hasPrefix(oldRoot) {
                suffix = String(path.dropFirst(oldRoot.count))
            } else {
                suffix = (path as NSString).lastPathComponent
            }
            let updated: String
            if newPrefix.isEmpty {
                updated = suffix
            } else if suffix.isEmpty {
                updated = newPrefix
            } else {
                updated = "\(newPrefix)/\(suffix)"
            }
            manifest.entries[i].relativePath = updated
        }
        for i in pathIndex.entries.indices {
            let path = pathIndex.entries[i].relativePath
            guard path.hasPrefix(oldRoot) || path == oldPrefix else { continue }
            let suffix: String
            if path.hasPrefix(oldRoot) {
                suffix = String(path.dropFirst(oldRoot.count))
            } else {
                suffix = (path as NSString).lastPathComponent
            }
            let updated: String
            if newPrefix.isEmpty {
                updated = suffix
            } else if suffix.isEmpty {
                updated = newPrefix
            } else {
                updated = "\(newPrefix)/\(suffix)"
            }
            pathIndex.entries[i].relativePath = updated
        }
        pathIndex.isDirty = true
    }

    func createFolder(parentID: UUID, name: String) throws -> UUID {
        try ensureVault()
        var folderCatalog = try loadFolderCatalog()
        folderCatalog.ensureRoot()
        let id = try folderCatalog.addFolder(parentID: parentID, name: name)
        let dir = folderCatalog.directoryURL(vaultRoot: vaultURL, folderID: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = try loadOrRebuildManifest()
        let graph = try loadLinkGraph()
        let rel = try loadRelationshipIndex()
        let pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        logIfIntegrityIssues(try commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        ))
        return id
    }

    func deleteFolder(id: UUID) throws {
        try ensureVault()
        guard id != FolderCatalog.rootFolderID else {
            throw NoteRepositoryError.invalidFolderMove
        }
        var folderCatalog = try loadFolderCatalog()
        folderCatalog.ensureRoot()
        let pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        if !folderCatalog.childFolders(of: id).isEmpty {
            throw NoteRepositoryError.folderNotEmpty(id)
        }
        if pathIndex.entries.contains(where: { $0.folderID == id }) {
            throw NoteRepositoryError.folderNotEmpty(id)
        }
        let dir = folderCatalog.directoryURL(vaultRoot: vaultURL, folderID: id)
        try folderCatalog.removeFolderEntry(id: id)
        let manifest = try loadOrRebuildManifest()
        let graph = try loadLinkGraph()
        let rel = try loadRelationshipIndex()
        var toDelete: [URL] = []
        if FileManager.default.fileExists(atPath: dir.path) {
            toDelete.append(dir)
        }
        logIfIntegrityIssues(try commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex,
            deletePathsAfterCommit: toDelete
        ))
    }

    func renameFolder(id: UUID, newName: String) throws {
        try ensureVault()
        guard id != FolderCatalog.rootFolderID else {
            throw NoteRepositoryError.invalidFolderName("root")
        }
        var folderCatalog = try loadFolderCatalog()
        folderCatalog.ensureRoot()
        let oldPrefix = folderCatalog.relativeDirectoryPath(for: id)
        let oldURL = folderCatalog.directoryURL(vaultRoot: vaultURL, folderID: id)
        try folderCatalog.renameFolder(id: id, newName: newName)
        let newPrefix = folderCatalog.relativeDirectoryPath(for: id)
        let newURL = folderCatalog.directoryURL(vaultRoot: vaultURL, folderID: id)

        if oldPrefix != newPrefix {
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: newURL.path) {
                    throw NoteRepositoryError.duplicateFolderName(newName)
                }
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            } else if !FileManager.default.fileExists(atPath: newURL.path) {
                try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
            }
        }

        var manifest = try loadOrRebuildManifest()
        var pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        if oldPrefix != newPrefix {
            applyRelativePathPrefixRewrite(from: oldPrefix, to: newPrefix, manifest: &manifest, pathIndex: &pathIndex)
        }
        let graph = try loadLinkGraph()
        let rel = try loadRelationshipIndex()
        logIfIntegrityIssues(try commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        ))
    }

    func moveFolder(id: UUID, newParentID: UUID) throws {
        try ensureVault()
        guard id != FolderCatalog.rootFolderID else {
            throw NoteRepositoryError.invalidFolderMove
        }
        var folderCatalog = try loadFolderCatalog()
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

        var manifest = try loadOrRebuildManifest()
        var pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        if oldPrefix != newPrefix {
            applyRelativePathPrefixRewrite(from: oldPrefix, to: newPrefix, manifest: &manifest, pathIndex: &pathIndex)
        }
        let graph = try loadLinkGraph()
        let rel = try loadRelationshipIndex()
        logIfIntegrityIssues(try commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: rel,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex
        ))
    }

    func moveNote(noteID: UUID, toFolderID: UUID) throws {
        try ensureVault()
        var folderCatalog = try loadFolderCatalog()
        folderCatalog.ensureRoot()
        guard toFolderID == FolderCatalog.rootFolderID || folderCatalog.folder(id: toFolderID) != nil else {
            throw NoteRepositoryError.folderNotFound(toFolderID)
        }

        let doc = try loadNote(noteID: noteID).document
        let manifestSnapshot = try loadOrRebuildManifest()
        guard let manifestEntry = manifestSnapshot.entry(noteID: noteID) else {
            throw NoteRepositoryError.noteNotFoundByID(noteID)
        }
        let oldPath = manifestEntry.relativePath

        let folderID = (try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)).entries.first { $0.noteID == noteID }?.folderID ?? FolderCatalog.rootFolderID
        guard folderID != toFolderID else { return }

        let dirPrefix = folderCatalog.relativeDirectoryPath(for: toFolderID)
        let stem = (oldPath as NSString).lastPathComponent
        let uniqueNew = try uniqueAvailableRelativePath(inDirectoryPrefix: dirPrefix.isEmpty ? nil : dirPrefix, slugStem: stem)

        if uniqueNew == oldPath {
            var pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
            pathIndex.upsert(noteID: noteID, folderID: toFolderID, relativePath: oldPath)
            let manifest = try loadOrRebuildManifest()
            let graph = try loadLinkGraph()
            let rel = try loadRelationshipIndex()
            logIfIntegrityIssues(try commitIndexOnly(
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

        var manifest = loadManifestFromDiskOnly() ?? VaultManifest()
        manifest.schemaVersion = VaultManifest.currentSchemaVersion
        let lastSegment = uniqueNew.split(separator: "/").last.map(String.init) ?? uniqueNew
        let title = manifestEntry.title ?? lastSegment.replacingOccurrences(of: "-", with: " ").capitalized
        manifest.upsert(noteID: noteID, relativePath: uniqueNew, title: title)

        var graph = try loadLinkGraph()
        graph.setOutgoing(from: noteID, to: doc.metadata.links.map(\.targetNoteID))
        var relationshipIndex = try loadRelationshipIndex()
        let linkRelationships = doc.metadata.links.map { link in
            LinkRelationship(
                sourceNoteID: noteID,
                target: .note(noteID: link.targetNoteID),
                relationshipKind: "noteLink"
            )
        }
        let artifactRelationships = doc.metadata.artifacts.map { artifact in
            LinkRelationship(
                sourceNoteID: noteID,
                target: .artifact(noteID: noteID, artifactID: artifact.id, kind: artifact.kind),
                relationshipKind: "artifactLink"
            )
        }
        relationshipIndex.replaceLinks(from: noteID, with: linkRelationships + artifactRelationships)

        var pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        pathIndex.upsert(noteID: noteID, folderID: toFolderID, relativePath: uniqueNew)

        let normalized = RangeNormalizer.normalize(metadata: doc.metadata, for: doc.text)
        let documentToPersist = NoteDocument(text: doc.text, metadata: normalized.normalizedMetadata)

        let oldPaths: [URL] = [oldTxt, oldMeta]
        logIfIntegrityIssues(try executeNoteCommit(
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

    func deleteNote(noteID: UUID) throws {
        try ensureVault()
        var manifest = try loadOrRebuildManifest()
        guard let entry = manifest.entry(noteID: noteID) else {
            throw NoteRepositoryError.noteNotFoundByID(noteID)
        }
        let relPath = entry.relativePath
        manifest.remove(noteID: noteID)

        var pathIndex = try VaultIndexSubsystem.loadPathIndex(vaultURL: vaultURL, decoder: decoder)
        pathIndex.remove(noteID: noteID)

        var graph = try loadLinkGraph()
        graph.removeNote(noteID)

        var relationshipIndex = try loadRelationshipIndex()
        relationshipIndex.removeAllInvolvingNote(noteID)

        var folderCatalog = try loadFolderCatalog()
        folderCatalog.ensureRoot()

        let txt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relPath, extension: "txt")
        let meta = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relPath, extension: "meta.json")
        let aux = VaultPaths.auxDirectory(vaultURL: vaultURL, noteID: noteID)
        var toDelete: [URL] = [txt, meta].filter { FileManager.default.fileExists(atPath: $0.path) }
        if FileManager.default.fileExists(atPath: aux.path) {
            toDelete.append(aux)
        }

        logIfIntegrityIssues(try commitIndexOnly(
            manifest: manifest,
            linkGraph: graph,
            relationshipIndex: relationshipIndex,
            folderCatalog: folderCatalog,
            pathIndex: pathIndex,
            deletePathsAfterCommit: toDelete
        ))
    }

    private func slugify(_ value: String) -> String {
        let slug = value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard slug.utf8.count > 200 else { return slug.isEmpty ? "untitled-note" : slug }
        var byteCount = 0
        var truncated = ""
        for scalar in slug.unicodeScalars {
            let scalarBytes = UTF8.width(scalar)
            guard byteCount + scalarBytes <= 200 else { break }
            truncated.unicodeScalars.append(scalar)
            byteCount += scalarBytes
        }
        let t = truncated.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return t.isEmpty ? "untitled-note" : t
    }

    private nonisolated static func documentAfterLoadRepair(text: String, metadata: NoteMetadata) -> (NoteDocument, [String]) {
        var allWarnings: [String] = []

        let pass1 = RangeNormalizer.normalize(metadata: metadata, for: text)
        allWarnings.append(contentsOf: pass1.warnings)
        var document = NoteDocument(
            text: text,
            metadata: pass1.normalizedMetadata
        )

        if !NoteIntegrity.check(document: document).isValid {
            let pass2 = RangeNormalizer.normalize(metadata: document.metadata, for: document.text)
            allWarnings.append(contentsOf: pass2.warnings)
            document = NoteDocument(text: text, metadata: pass2.normalizedMetadata)
        }

        if !NoteIntegrity.check(document: document).isValid {
            let total = RangeNormalizer.utf16Length(of: text)
            let noteID = document.metadata.noteID
            let fallback = NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: noteID,
                blocks: [
                    Block(
                        id: UUID().uuidString,
                        type: .paragraph,
                        range: TextRange(start: 0, length: total),
                        level: nil,
                        icon: nil
                    )
                ],
                spans: []
            )
            let pass3 = RangeNormalizer.normalize(metadata: fallback, for: text)
            allWarnings.append(contentsOf: pass3.warnings)
            allWarnings.append("Metadata was too corrupt to repair incrementally; rebuilt as single paragraph block.")
            document = NoteDocument(text: text, metadata: pass3.normalizedMetadata)
        }

        return (document, allWarnings)
    }
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

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

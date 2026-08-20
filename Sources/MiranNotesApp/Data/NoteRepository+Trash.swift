import Foundation
import MiranNotesCore

/// On-disk record beside a trashed note's files (`.miran/trash/<noteID>/trash-record.json`).
struct NoteTrashRecord: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var noteID: UUID
    var title: String
    var relativePath: String
    var folderID: UUID
    var bodyFileExtension: String
    var deletedAt: Date
}

/// Row model for the Trash page.
struct TrashedNoteSummary: Identifiable, Equatable, Sendable {
    var id: UUID { noteID }
    var noteID: UUID
    var title: String
    var originalRelativePath: String
    var deletedAt: Date
}

extension VaultPaths {
    static func trashDirectory(vaultURL: URL) -> URL {
        miranDirectory(vaultURL: vaultURL).appendingPathComponent("trash", isDirectory: true)
    }

    static func trashNoteDirectory(vaultURL: URL, noteID: UUID) -> URL {
        trashDirectory(vaultURL: vaultURL)
            .appendingPathComponent(noteID.uuidString.lowercased(), isDirectory: true)
    }
}

/// Trash: user-facing delete moves a note's files under `.miran/trash/<noteID>/` **before** running
/// the exact index commit `deleteNote` uses. A crash between the copy and the commit leaves only a
/// harmless duplicate in trash. Restore preserves `noteID`, so incoming links resolve again as the
/// linking notes re-save (link-graph edges to the note rebuild via the normal save/reconcile path).
extension NoteRepository {
    func trashNote(noteID: UUID) async throws {
        try await files.ensureVault()
        var manifest = try await loadOrRebuildManifest()
        guard let entry = manifest.entry(noteID: noteID) else {
            throw NoteRepositoryError.noteNotFoundByID(noteID)
        }
        let relPath = entry.relativePath
        let title = entry.title ?? VaultPath.displayTitle(forRelativePath: relPath)

        var pathIndex = try await index.loadPathIndex()
        let pathEntry = pathIndex.entries.first { $0.noteID == noteID }
        let bodyExt = pathEntry?.bodyFileExtension ?? "txt"
        let folderID = pathEntry?.folderID ?? FolderCatalog.rootFolderID

        // Phase 1: copy files into the trash directory (idempotent; replaces any older copy).
        let trashDir = VaultPaths.trashNoteDirectory(vaultURL: vaultURL, noteID: noteID)
        let fm = FileManager.default
        if fm.fileExists(atPath: trashDir.path) {
            try fm.removeItem(at: trashDir)
        }
        try fm.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let txt = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relPath, extension: bodyExt)
        let meta = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relPath, extension: "meta.json")
        let aux = VaultPaths.auxDirectory(vaultURL: vaultURL, noteID: noteID)
        if fm.fileExists(atPath: txt.path) {
            try fm.copyItem(at: txt, to: trashDir.appendingPathComponent("body.\(bodyExt)", isDirectory: false))
        }
        if fm.fileExists(atPath: meta.path) {
            try fm.copyItem(at: meta, to: trashDir.appendingPathComponent("meta.json", isDirectory: false))
        }
        if fm.fileExists(atPath: aux.path) {
            try fm.copyItem(at: aux, to: trashDir.appendingPathComponent("_aux", isDirectory: true))
        }
        let record = NoteTrashRecord(
            noteID: noteID,
            title: title,
            relativePath: relPath,
            folderID: folderID,
            bodyFileExtension: bodyExt,
            deletedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(
            to: trashDir.appendingPathComponent("trash-record.json", isDirectory: false),
            options: .atomic
        )

        // Phase 2: the same index commit + file deletion `deleteNote` performs.
        manifest.remove(noteID: noteID)
        pathIndex.remove(noteID: noteID)
        var graph = try await index.loadLinkGraph()
        graph.removeNote(noteID)
        var relationshipIndex = try await index.loadRelationshipIndex()
        relationshipIndex.removeAllInvolvingNote(noteID)
        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()

        var toDelete: [URL] = [txt, meta].filter { fm.fileExists(atPath: $0.path) }
        if fm.fileExists(atPath: aux.path) {
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

    func listTrashedNotes() -> [TrashedNoteSummary] {
        let trashRoot = VaultPaths.trashDirectory(vaultURL: vaultURL)
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: trashRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return children
            .compactMap { dir -> TrashedNoteSummary? in
                let recordURL = dir.appendingPathComponent("trash-record.json", isDirectory: false)
                guard let data = try? Data(contentsOf: recordURL),
                      let record = try? decoder.decode(NoteTrashRecord.self, from: data) else { return nil }
                return TrashedNoteSummary(
                    noteID: record.noteID,
                    title: record.title,
                    originalRelativePath: record.relativePath,
                    deletedAt: record.deletedAt
                )
            }
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Restores a trashed note (original `noteID` preserved) and returns its new relative path.
    /// Destination: the original folder when it still accepts notes; else the vault root when it
    /// does; else the first repository folder; else a newly created "Recovered" repository folder.
    @discardableResult
    func restoreTrashedNote(noteID: UUID) async throws -> String {
        let trashDir = VaultPaths.trashNoteDirectory(vaultURL: vaultURL, noteID: noteID)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let recordData = try Data(contentsOf: trashDir.appendingPathComponent("trash-record.json", isDirectory: false))
        let record = try decoder.decode(NoteTrashRecord.self, from: recordData)

        let bodyURL = trashDir.appendingPathComponent("body.\(record.bodyFileExtension)", isDirectory: false)
        let metaURL = trashDir.appendingPathComponent("meta.json", isDirectory: false)
        let text = (try? String(contentsOf: bodyURL, encoding: .utf8)) ?? ""
        let metadata: NoteMetadata
        if let metaData = try? Data(contentsOf: metaURL),
           let decoded = try? JSONDecoder().decode(NoteMetadata.self, from: metaData) {
            metadata = decoded
        } else {
            var fresh = NoteMetadata.empty
            fresh.blocks = [
                Block(id: UUID().uuidString, type: .paragraph, range: TextRange(start: 0, length: text.utf16.count), level: nil, icon: nil)
            ]
            metadata = fresh
        }
        var folderCatalog = try await index.loadFolderCatalog()
        folderCatalog.ensureRoot()
        let destinationFolderID = try await resolveRestoreDestination(record: record, folderCatalog: &folderCatalog)

        let dirPrefix = folderCatalog.relativeDirectoryPath(for: destinationFolderID)
        var stem = await files.slugify(record.title.isEmpty ? "recovered-note" : record.title)
        if stem.isEmpty { stem = "recovered-note" }
        let relativePath = try await files.uniqueAvailableRelativePath(
            inDirectoryPrefix: dirPrefix.isEmpty ? nil : dirPrefix,
            slugStem: stem
        )

        let document = NoteDocument(text: text, metadata: metadata)
        _ = try await save(
            document,
            asRelativePath: relativePath,
            folderID: destinationFolderID,
            bodyFileExtension: record.bodyFileExtension
        )

        // Restore the aux directory (attachments) if one was trashed with the note.
        let trashedAux = trashDir.appendingPathComponent("_aux", isDirectory: true)
        let auxDestination = VaultPaths.auxDirectory(vaultURL: vaultURL, noteID: record.noteID)
        let fm = FileManager.default
        if fm.fileExists(atPath: trashedAux.path), !fm.fileExists(atPath: auxDestination.path) {
            try? fm.createDirectory(
                at: auxDestination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fm.copyItem(at: trashedAux, to: auxDestination)
        }

        try? fm.removeItem(at: trashDir)
        return relativePath
    }

    func deleteTrashedNotePermanently(noteID: UUID) {
        try? FileManager.default.removeItem(
            at: VaultPaths.trashNoteDirectory(vaultURL: vaultURL, noteID: noteID)
        )
    }

    func emptyTrash() {
        try? FileManager.default.removeItem(at: VaultPaths.trashDirectory(vaultURL: vaultURL))
    }

    private func resolveRestoreDestination(
        record: NoteTrashRecord,
        folderCatalog: inout FolderCatalog
    ) async throws -> UUID {
        if folderCatalog.folder(id: record.folderID) != nil || record.folderID == FolderCatalog.rootFolderID {
            if folderCatalog.allowsNotes(in: record.folderID) {
                return record.folderID
            }
        }
        if folderCatalog.allowsNotes(in: FolderCatalog.rootFolderID) {
            return FolderCatalog.rootFolderID
        }
        if let repositoryFolder = folderCatalog.folders.first(where: {
            $0.id != FolderCatalog.rootFolderID && folderCatalog.allowsNotes(in: $0.id)
        }) {
            return repositoryFolder.id
        }
        let recoveredID = try await createFolder(parentID: FolderCatalog.rootFolderID, name: "Recovered")
        try await setFolderRole(.repository, folderID: recoveredID)
        return recoveredID
    }
}

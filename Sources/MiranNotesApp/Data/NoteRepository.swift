import Foundation
import MiranNotesCore
import os.log

/// Result of loading a note from disk, including any structural repair warnings.
struct NoteLoadResult {
    var document: NoteDocument
    /// Non-empty when `RangeNormalizer` had to repair block ranges or spans on load.
    /// Surfaced to the user as a non-blocking advisory so they know metadata may not perfectly
    /// reflect the original block structure.
    var repairWarnings: [String]

    var wasRepaired: Bool { !repairWarnings.isEmpty }
}

enum NoteRepositoryError: LocalizedError, Equatable {
    case invalidBaseName(String)
    case tooManyFilenameCollisions
    case noteNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .invalidBaseName(name):
            return "Invalid note name: \(name)"
        case .tooManyFilenameCollisions:
            return "Could not allocate a unique note file name."
        case let .noteNotFound(base):
            return "Note not found: \(base)"
        }
    }
}

struct NoteSummary: Identifiable, Hashable {
    var id: UUID { noteID }
    var noteID: UUID
    var title: String
    var baseName: String
}

actor NoteRepository {
    /// Exposed for vault-wide filesystem observation (`VaultDirectoryWatcher`) without crossing the actor boundary for reads.
    nonisolated let vaultURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(vaultURL: URL) {
        self.vaultURL = vaultURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    /// Rejects path segments and reserved names so `baseName` cannot escape the vault directory.
    nonisolated static func validateBaseName(_ baseName: String) throws {
        guard !baseName.isEmpty else {
            throw NoteRepositoryError.invalidBaseName(baseName)
        }
        guard baseName != "..", !baseName.hasPrefix(".") else {
            throw NoteRepositoryError.invalidBaseName(baseName)
        }
        if baseName.contains("/") || baseName.contains("\\") || baseName.contains(":") {
            throw NoteRepositoryError.invalidBaseName(baseName)
        }
        if baseName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            throw NoteRepositoryError.invalidBaseName(baseName)
        }
    }

    func ensureVault() throws {
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: VaultPaths.miranDirectory(vaultURL: vaultURL), withIntermediateDirectories: true)
    }

    func listNotes() throws -> [NoteSummary] {
        try ensureVault()
        let manifest = try loadOrRebuildManifest()
        try saveManifest(manifest)

        return manifest.entries
            .sorted { $0.baseName.lowercased() < $1.baseName.lowercased() }
            .map { entry in
                let title = entry.title ?? entry.baseName.replacingOccurrences(of: "-", with: " ").capitalized
                return NoteSummary(noteID: entry.noteID, title: title, baseName: entry.baseName)
            }
    }

    /// Current vault manifest (for link resolution, etc.).
    func loadManifest() throws -> VaultManifest {
        try loadOrRebuildManifest()
    }

    func linkResolver() throws -> LinkResolver {
        LinkResolver(manifest: try loadOrRebuildManifest())
    }

    func loadLinkGraph() throws -> LinkGraph {
        let url = VaultPaths.linkGraphURL(vaultURL: vaultURL)
        guard let data = try? Data(contentsOf: url),
              let graph = try? decoder.decode(LinkGraph.self, from: data) else {
            return LinkGraph()
        }
        return graph
    }

    func saveLinkGraph(_ graph: LinkGraph) throws {
        try ensureVault()
        let url = VaultPaths.linkGraphURL(vaultURL: vaultURL)
        let data = try encoder.encode(graph)
        try atomicWrite(data, to: url)
    }

    /// Updates forward edges for one note and persists the graph (call from debounced save path).
    func updateLinkGraph(sourceNoteID: UUID, targets: [UUID]) throws {
        var graph = try loadLinkGraph()
        graph.setOutgoing(from: sourceNoteID, to: targets)
        try saveLinkGraph(graph)
    }

    /// Full scan of vault notes to rebuild `link-graph.json` (cold start, external batch edits).
    func rebuildLinkGraphFull() throws {
        let manifest = try loadOrRebuildManifest()
        try saveManifest(manifest)
        var graph = LinkGraph()
        for entry in manifest.entries {
            let doc = try loadNote(baseName: entry.baseName).document
            graph.setOutgoing(from: entry.noteID, to: doc.metadata.links.map(\.targetNoteID))
        }
        try saveLinkGraph(graph)
        Logger.vault.info("Rebuilt link graph for \(manifest.entries.count, privacy: .public) notes")
    }

    func createNote(named name: String) throws -> (NoteDocument, String) {
        try ensureVault()
        var slug = slugify(name.isEmpty ? "untitled-note" : name)
        if slug.isEmpty {
            slug = "untitled-note"
        }
        let baseName = try uniqueAvailableBaseName(slug: slug)
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

        let document = NoteDocument(id: metadata.noteID, text: text, metadata: metadata)
        try save(document, asBaseName: baseName)
        return (document, baseName)
    }

    func loadNote(baseName: String) throws -> NoteLoadResult {
        try Self.validateBaseName(baseName)
        let textURL = vaultURL.appendingPathComponent("\(baseName).txt")
        let metaURL = vaultURL.appendingPathComponent("\(baseName).meta.json")

        guard FileManager.default.fileExists(atPath: textURL.path) else {
            throw NoteRepositoryError.noteNotFound(baseName)
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
        let withId = NoteDocument(id: repaired.metadata.noteID, text: repaired.text, metadata: repaired.metadata)
        NoteIntegrity.logIfInvalid(document: withId)
        return NoteLoadResult(document: withId, repairWarnings: repairWarnings)
    }

    func noteModifiedDate(baseName: String) throws -> Date? {
        try Self.validateBaseName(baseName)
        let textURL = vaultURL.appendingPathComponent("\(baseName).txt")
        let metaURL = vaultURL.appendingPathComponent("\(baseName).meta.json")
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

    func save(_ note: NoteDocument, asBaseName baseName: String) throws {
        try Self.validateBaseName(baseName)
        try ensureVault()
        let normalized = RangeNormalizer.normalize(metadata: note.metadata, for: note.text)
        let documentToPersist = NoteDocument(
            id: normalized.normalizedMetadata.noteID,
            text: note.text,
            metadata: normalized.normalizedMetadata
        )
        NoteIntegrity.logIfInvalid(document: documentToPersist)
        let textURL = vaultURL.appendingPathComponent("\(baseName).txt")
        let metaURL = vaultURL.appendingPathComponent("\(baseName).meta.json")

        try atomicWrite(note.text.data(using: .utf8) ?? Data(), to: textURL)
        let metadataData = try encoder.encode(normalized.normalizedMetadata)
        try atomicWrite(metadataData, to: metaURL)

        var manifest = loadManifestFromDiskOnly() ?? VaultManifest()
        let title = baseName.replacingOccurrences(of: "-", with: " ").capitalized
        manifest.upsert(noteID: documentToPersist.metadata.noteID, baseName: baseName, title: title)
        try saveManifest(manifest)

        let targets = documentToPersist.metadata.links.map(\.targetNoteID)
        try updateLinkGraph(sourceNoteID: documentToPersist.metadata.noteID, targets: targets)
    }

    /// Renames note files from `oldBaseName` to a new slug derived from `newTitle`. Returns the new `baseName`.
    func renameNote(from oldBaseName: String, to newTitle: String) throws -> String {
        try Self.validateBaseName(oldBaseName)
        try ensureVault()
        guard FileManager.default.fileExists(atPath: vaultURL.appendingPathComponent("\(oldBaseName).txt").path) else {
            throw NoteRepositoryError.noteNotFound(oldBaseName)
        }

        let doc = try loadNote(baseName: oldBaseName).document
        var slug = slugify(newTitle.isEmpty ? oldBaseName : newTitle)
        if slug.isEmpty {
            slug = "untitled-note"
        }

        let newBaseName: String
        if slug == oldBaseName {
            newBaseName = oldBaseName
        } else {
            newBaseName = try uniqueAvailableBaseName(slug: slug)
        }

        if newBaseName == oldBaseName {
            var manifest = loadManifestFromDiskOnly() ?? VaultManifest()
            manifest.upsert(noteID: doc.metadata.noteID, baseName: oldBaseName, title: newTitle)
            try saveManifest(manifest)
            return oldBaseName
        }

        let oldTxt = vaultURL.appendingPathComponent("\(oldBaseName).txt")
        let oldMeta = vaultURL.appendingPathComponent("\(oldBaseName).meta.json")
        try save(doc, asBaseName: newBaseName)

        if FileManager.default.fileExists(atPath: oldTxt.path) {
            try FileManager.default.removeItem(at: oldTxt)
        }
        if FileManager.default.fileExists(atPath: oldMeta.path) {
            try FileManager.default.removeItem(at: oldMeta)
        }

        var manifest = loadManifestFromDiskOnly() ?? VaultManifest()
        manifest.upsert(noteID: doc.metadata.noteID, baseName: newBaseName, title: newTitle)
        try saveManifest(manifest)

        return newBaseName
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

    /// Drops manifest entries whose `.txt` disappeared; adds missing notes on disk.
    private func reconcileManifestWithDisk(_ manifest: VaultManifest) throws -> VaultManifest {
        var next = manifest
        next.entries.removeAll { entry in
            !FileManager.default.fileExists(atPath: vaultURL.appendingPathComponent("\(entry.baseName).txt").path)
        }

        let onDisk = try listBaseNamesOnDisk()
        let knownBases = Set(next.entries.map(\.baseName))
        for base in onDisk where !knownBases.contains(base) {
            let doc = try loadNote(baseName: base).document
            let title = base.replacingOccurrences(of: "-", with: " ").capitalized
            next.upsert(noteID: doc.metadata.noteID, baseName: base, title: title)
            let metaPath = vaultURL.appendingPathComponent("\(base).meta.json")
            if !FileManager.default.fileExists(atPath: metaPath.path) {
                try save(doc, asBaseName: base)
            }
        }
        return next
    }

    private func rebuildManifestFromDisk() throws -> VaultManifest {
        try ensureVault()
        var manifest = VaultManifest()
        let bases = try listBaseNamesOnDisk()
        for base in bases {
            let doc = try loadNote(baseName: base).document
            let metaPath = vaultURL.appendingPathComponent("\(base).meta.json")
            if !FileManager.default.fileExists(atPath: metaPath.path) {
                try save(doc, asBaseName: base)
            }
            let title = base.replacingOccurrences(of: "-", with: " ").capitalized
            manifest.upsert(noteID: doc.metadata.noteID, baseName: base, title: title)
        }
        try saveManifest(manifest)
        return manifest
    }

    private func listBaseNamesOnDisk() throws -> [String] {
        let urls = try FileManager.default.contentsOfDirectory(at: vaultURL, includingPropertiesForKeys: nil)
        return urls
            .filter { $0.pathExtension.lowercased() == "txt" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.lowercased() < $1.lowercased() }
    }

    private func saveManifest(_ manifest: VaultManifest) throws {
        try ensureVault()
        let data = try encoder.encode(manifest)
        try atomicWrite(data, to: manifestURL())
    }

    private func loadManifestFromDiskOnly() -> VaultManifest? {
        let url = manifestURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(VaultManifest.self, from: data) else {
            return nil
        }
        return decoded
    }

    private func uniqueAvailableBaseName(slug: String) throws -> String {
        var collision = 0
        var candidate = slug
        while true {
            try Self.validateBaseName(candidate)
            let path = vaultURL.appendingPathComponent("\(candidate).txt").path
            if !FileManager.default.fileExists(atPath: path) {
                return candidate
            }
            collision += 1
            guard collision < 10_000 else {
                throw NoteRepositoryError.tooManyFilenameCollisions
            }
            candidate = collision == 1 ? "\(slug)-2" : "\(slug)-\(collision + 1)"
        }
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let tmpURL = url.appendingPathExtension("tmp")
        var committed = false
        defer {
            if !committed {
                try? FileManager.default.removeItem(at: tmpURL)
            }
        }
        try data.write(to: tmpURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } else {
            try FileManager.default.moveItem(at: tmpURL, to: url)
        }
        committed = true
    }

    private func slugify(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private nonisolated static func documentAfterLoadRepair(text: String, metadata: NoteMetadata) -> (NoteDocument, [String]) {
        var allWarnings: [String] = []

        let pass1 = RangeNormalizer.normalize(metadata: metadata, for: text)
        allWarnings.append(contentsOf: pass1.warnings)
        var document = NoteDocument(
            id: pass1.normalizedMetadata.noteID,
            text: text,
            metadata: pass1.normalizedMetadata
        )

        if !NoteIntegrity.check(document: document).isValid {
            let pass2 = RangeNormalizer.normalize(metadata: document.metadata, for: document.text)
            allWarnings.append(contentsOf: pass2.warnings)
            document = NoteDocument(id: pass2.normalizedMetadata.noteID, text: text, metadata: pass2.normalizedMetadata)
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
            document = NoteDocument(id: pass3.normalizedMetadata.noteID, text: text, metadata: pass3.normalizedMetadata)
        }

        return (document, allWarnings)
    }
}

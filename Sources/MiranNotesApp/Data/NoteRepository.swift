import Foundation
import MiranNotesCore

enum NoteRepositoryError: LocalizedError, Equatable {
    case invalidBaseName(String)
    case tooManyFilenameCollisions

    var errorDescription: String? {
        switch self {
        case let .invalidBaseName(name):
            return "Invalid note name: \(name)"
        case .tooManyFilenameCollisions:
            return "Could not allocate a unique note file name."
        }
    }
}

struct NoteSummary: Identifiable, Hashable {
    var id: String { baseName }
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
    }

    func listNotes() throws -> [NoteSummary] {
        try ensureVault()
        let urls = try FileManager.default.contentsOfDirectory(
            at: vaultURL,
            includingPropertiesForKeys: nil
        )

        return urls
            .filter { $0.pathExtension.lowercased() == "txt" }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
            .map { txtURL in
                let baseName = txtURL.deletingPathExtension().lastPathComponent
                let title = baseName.replacingOccurrences(of: "-", with: " ")
                return NoteSummary(title: title.capitalized, baseName: baseName)
            }
    }

    func createNote(named name: String) throws -> (NoteDocument, String) {
        try ensureVault()
        var slug = slugify(name.isEmpty ? "untitled-note" : name)
        if slug.isEmpty {
            slug = "untitled-note"
        }
        let baseName = try uniqueAvailableBaseName(slug: slug)
        let text = ""
        let metadata = NoteMetadata(
            schemaVersion: NoteMetadata.currentSchemaVersion,
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
        try save(document, asBaseName: baseName)
        return (document, baseName)
    }

    func loadNote(baseName: String) throws -> NoteDocument {
        try Self.validateBaseName(baseName)
        let textURL = vaultURL.appendingPathComponent("\(baseName).txt")
        let metaURL = vaultURL.appendingPathComponent("\(baseName).meta.json")

        let text = (try? String(contentsOf: textURL, encoding: .utf8)) ?? ""
        let metadata: NoteMetadata

        if let data = try? Data(contentsOf: metaURL),
           let decoded = try? decoder.decode(NoteMetadata.self, from: data) {
            metadata = MetadataSchema.migrate(decoded)
        } else {
            metadata = NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
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

        let document = Self.documentAfterLoadRepair(text: text, metadata: metadata)
        NoteIntegrity.logIfInvalid(document: document)
        return document
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
        let documentToPersist = NoteDocument(text: note.text, metadata: normalized.normalizedMetadata)
        NoteIntegrity.logIfInvalid(document: documentToPersist)
        let textURL = vaultURL.appendingPathComponent("\(baseName).txt")
        let metaURL = vaultURL.appendingPathComponent("\(baseName).meta.json")

        try atomicWrite(note.text.data(using: .utf8) ?? Data(), to: textURL)
        let metadataData = try encoder.encode(normalized.normalizedMetadata)
        try atomicWrite(metadataData, to: metaURL)
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

    private nonisolated static func documentAfterLoadRepair(text: String, metadata: NoteMetadata) -> NoteDocument {
        let normalized = RangeNormalizer.normalize(metadata: metadata, for: text)
        var document = NoteDocument(text: text, metadata: normalized.normalizedMetadata)

        if !NoteIntegrity.check(document: document).isValid {
            let again = RangeNormalizer.normalize(metadata: document.metadata, for: document.text)
            document = NoteDocument(text: text, metadata: again.normalizedMetadata)
        }

        if !NoteIntegrity.check(document: document).isValid {
            let total = RangeNormalizer.utf16Length(of: text)
            let fallback = NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
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
            let repaired = RangeNormalizer.normalize(metadata: fallback, for: text).normalizedMetadata
            document = NoteDocument(text: text, metadata: repaired)
        }

        return document
    }
}

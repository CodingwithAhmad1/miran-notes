import CryptoKit
import Foundation
import MiranNotesCore
import os.log

/// Per-note file I/O: `.txt` or `.md` bodies + `.meta.json` reads, hashes, and vault enumeration helpers. Used by ``NoteRepository``.
actor NoteFileActor {
    nonisolated let vaultURL: URL
    private let decoder: JSONDecoder
    private var vaultEnsured = false

    init(vaultURL: URL) {
        self.vaultURL = vaultURL
        self.decoder = JSONDecoder()
    }

    func ensureVault() throws {
        guard !vaultEnsured else { return }
        var isDir: ObjCBool = false
        let path = vaultURL.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw NoteRepositoryError.vaultRootNotDirectory(path: path)
        }
        try FileManager.default.createDirectory(at: VaultPaths.miranDirectory(vaultURL: vaultURL), withIntermediateDirectories: true)
        vaultEnsured = true
    }

    /// Loads note text + metadata. When `.meta.json` is missing or invalid, uses `fallbackNoteID` (from manifest / registration).
    /// When the sidecar decodes successfully, `fallbackNoteID` is ignored.
    /// - Parameter bodyFileExtension: Preferred body extension from path index (`txt` or `md`); when the file is missing, disk is probed.
    func loadNote(relativePath: String, fallbackNoteID: UUID?, bodyFileExtension: String? = nil) throws -> NoteLoadResult {
        try VaultPath.validateRelativePath(relativePath)
        let ext = try Self.resolveBodyExtension(
            vaultRoot: vaultURL,
            relativePath: relativePath,
            preferred: bodyFileExtension
        )
        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: ext)
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
            guard let fid = fallbackNoteID else {
                throw NoteRepositoryError.unresolvedNoteIdentity(relativePath)
            }
            metadata = NoteMetadata(
                schemaVersion: NoteMetadata.currentSchemaVersion,
                noteID: fid,
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

    func noteTextFileSHA256(relativePath: String, bodyFileExtension: String? = nil) throws -> String {
        try VaultPath.validateRelativePath(relativePath)
        let ext = try Self.resolveBodyExtension(vaultRoot: vaultURL, relativePath: relativePath, preferred: bodyFileExtension)
        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: ext)
        guard FileManager.default.fileExists(atPath: textURL.path) else {
            throw NoteRepositoryError.noteNotFound(relativePath)
        }
        let data = try Data(contentsOf: textURL)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func readRawNoteText(relativePath: String, bodyFileExtension: String? = nil) throws -> String {
        try VaultPath.validateRelativePath(relativePath)
        let ext = try Self.resolveBodyExtension(vaultRoot: vaultURL, relativePath: relativePath, preferred: bodyFileExtension)
        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: ext)
        guard FileManager.default.fileExists(atPath: textURL.path) else {
            throw NoteRepositoryError.noteNotFound(relativePath)
        }
        return (try? String(contentsOf: textURL, encoding: .utf8)) ?? ""
    }

    func noteModifiedDate(relativePath: String, bodyFileExtension: String? = nil) throws -> Date? {
        try VaultPath.validateRelativePath(relativePath)
        let ext = try Self.resolveBodyExtension(vaultRoot: vaultURL, relativePath: relativePath, preferred: bodyFileExtension)
        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: ext)
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

    func noteRevisionToken(relativePath: String, bodyFileExtension: String? = nil) throws -> DocumentRevisionToken? {
        try VaultPath.validateRelativePath(relativePath)
        let ext = try? Self.resolveBodyExtension(vaultRoot: vaultURL, relativePath: relativePath, preferred: bodyFileExtension)
        guard let ext else { return nil }
        let textURL = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: relativePath, extension: ext)
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

    func listRelativePathsOnDisk() throws -> [String] {
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
            let ext = item.pathExtension.lowercased()
            guard ext == "txt" || ext == "md" else { continue }
            guard let rel = relativePathFromVaultNoteBodyURL(item) else { continue }
            results.append(rel)
        }
        return Array(Set(results)).sorted { $0.lowercased() < $1.lowercased() }
    }

    /// Returns `relativePath` without extension for a `.txt` / `.md` file under the vault.
    func relativePathFromVaultNoteBodyURL(_ file: URL) -> String? {
        let vaultPath = vaultURL.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(vaultPath) else { return nil }
        var sub = String(filePath.dropFirst(vaultPath.count))
        if sub.hasPrefix("/") { sub.removeFirst() }
        let lower = sub.lowercased()
        if lower.hasSuffix(".txt") {
            sub = String(sub.dropLast(4))
        } else if lower.hasSuffix(".md") {
            sub = String(sub.dropLast(3))
        } else {
            return nil
        }
        let parts = sub.split(separator: "/").map(String.init)
        if parts.contains(".miran") || parts.contains("_aux") { return nil }
        if let first = parts.first, VaultPath.reservedTopLevel.contains(first) { return nil }
        return sub
    }

    /// Legacy alias for tests / older call sites.
    func relativePathFromVaultNoteTextURL(_ file: URL) -> String? {
        relativePathFromVaultNoteBodyURL(file)
    }

    func uniqueAvailableRelativePath(inDirectoryPrefix dirPrefix: String?, slugStem: String) throws -> String {
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
            let txtPath = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: rel, extension: "txt")
            let mdPath = VaultPath.fileURL(vaultRoot: vaultURL, relativePathWithoutExtension: rel, extension: "md")
            if !FileManager.default.fileExists(atPath: txtPath.path), !FileManager.default.fileExists(atPath: mdPath.path) {
                return rel
            }
            collision += 1
            guard collision < 10_000 else {
                throw NoteRepositoryError.tooManyFilenameCollisions
            }
            stem = collision == 1 ? "\(slugStem)-2" : "\(slugStem)-\(collision + 1)"
        }
    }

    nonisolated static func resolveBodyExtension(vaultRoot: URL, relativePath: String, preferred: String?) throws -> String {
        let mdURL = VaultPath.fileURL(vaultRoot: vaultRoot, relativePathWithoutExtension: relativePath, extension: "md")
        let txtURL = VaultPath.fileURL(vaultRoot: vaultRoot, relativePathWithoutExtension: relativePath, extension: "txt")
        let mdExists = FileManager.default.fileExists(atPath: mdURL.path)
        let txtExists = FileManager.default.fileExists(atPath: txtURL.path)

        if let preferred {
            let norm = PathIndexEntry.normalizeBodyFileExtension(preferred)
            if norm == "md", mdExists { return "md" }
            if norm == "txt", txtExists { return "txt" }
        }

        if mdExists, txtExists {
            throw NoteRepositoryError.ambiguousNoteBody(relativePath)
        }
        if mdExists { return "md" }
        if txtExists { return "txt" }
        throw NoteRepositoryError.noteNotFound(relativePath)
    }

    func slugify(_ value: String) -> String {
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
            var fallback = document.metadata
            fallback.schemaVersion = NoteMetadata.currentSchemaVersion
            fallback.blocks = [
                Block(
                    id: UUID().uuidString,
                    type: .paragraph,
                    range: TextRange(start: 0, length: total),
                    level: nil,
                    icon: nil
                )
            ]
            fallback.spans = []
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

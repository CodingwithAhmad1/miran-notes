import Foundation

/// Files attached to a note, stored under `vault/_aux/<noteID>/attachments/<filename>`.
/// The note body references them with plain-text tokens (`[attachment: filename.ext]`, see
/// ``AttachmentTokenScanner``) — human-readable, external-edit-proof, no sidecar schema change.
/// The `_aux` directory already rides along with delete (removed) and trash (copied+restored).
struct NoteAttachmentStore: Sendable {
    let vaultURL: URL

    func attachmentsDirectory(noteID: UUID) -> URL {
        VaultPaths.auxDirectory(vaultURL: vaultURL, noteID: noteID)
            .appendingPathComponent("attachments", isDirectory: true)
    }

    func fileURL(noteID: UUID, filename: String) -> URL {
        attachmentsDirectory(noteID: noteID).appendingPathComponent(filename, isDirectory: false)
    }

    /// Copies a file in, deduplicating the name (`report.pdf`, `report-2.pdf`, …).
    /// Returns the stored filename.
    func copyIn(fileAt sourceURL: URL, noteID: UUID) throws -> String {
        let dir = attachmentsDirectory(noteID: noteID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let sanitized = Self.sanitizedFilename(sourceURL.lastPathComponent)
        let stem = (sanitized as NSString).deletingPathExtension
        let ext = (sanitized as NSString).pathExtension
        var candidate = sanitized
        var counter = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            counter += 1
            if counter > 500 { throw CocoaError(.fileWriteFileExists) }
        }
        try FileManager.default.copyItem(at: sourceURL, to: dir.appendingPathComponent(candidate))
        return candidate
    }

    func listFilenames(noteID: UUID) -> [String] {
        let dir = attachmentsDirectory(noteID: noteID)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }

    func exists(noteID: UUID, filename: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(noteID: noteID, filename: filename).path)
    }

    func delete(noteID: UUID, filename: String) {
        try? FileManager.default.removeItem(at: fileURL(noteID: noteID, filename: filename))
    }

    /// Strips path separators and brackets so tokens stay parseable and paths stay contained.
    static func sanitizedFilename(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "attachment" : cleaned
    }
}

/// Finds `[attachment: filename.ext]` tokens in note text (UTF-16 ranges for editor overlays).
enum AttachmentTokenScanner {
    struct Token: Equatable {
        var range: NSRange
        var filename: String
    }

    nonisolated(unsafe) private static let regex = try! NSRegularExpression(
        pattern: #"\[attachment:\s*([^\[\]\n]+?)\s*\]"#
    )

    static func tokens(in text: String) -> [Token] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let filename = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard !filename.isEmpty else { return nil }
            return Token(range: match.range, filename: filename)
        }
    }

    static func tokenText(filename: String) -> String {
        "[attachment: \(filename)]"
    }
}

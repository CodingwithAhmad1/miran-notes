import Foundation

/// Canonical addressing for notes under a vault: POSIX-style path without file extension, e.g. `work/client/meeting-notes`.
enum VaultPath {
    static let reservedTopLevel = Set([".miran", "_aux", ".git", ".DS_Store"])

    /// Human-readable title from a note relative path (last segment, dashes to spaces, capitalized).
    static func displayTitle(forRelativePath relativePath: String) -> String {
        let last = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        return last.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// Sidebar / list label when several notes share the same ``displayTitle`` (e.g. `note.md` in different folders).
    static func disambiguatedListTitle(relativePath: String) -> String {
        let parts = relativePath.split(separator: "/").map(String.init)
        let base = displayTitle(forRelativePath: relativePath)
        guard parts.count > 1 else {
            return "\(base) · Root"
        }
        let prefix = parts.dropLast().map { displayTitle(forRelativePath: $0) }.joined(separator: " › ")
        return "\(prefix) › \(base)"
    }

    /// Slug for a single path segment (folder display name or note title stem).
    static func slugifySegment(_ value: String) -> String {
        let slug = value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard slug.utf8.count > 200 else {
            return slug.isEmpty ? "untitled" : slug
        }
        var byteCount = 0
        var truncated = ""
        for scalar in slug.unicodeScalars {
            let scalarBytes = UTF8.width(scalar)
            guard byteCount + scalarBytes <= 200 else { break }
            truncated.unicodeScalars.append(scalar)
            byteCount += scalarBytes
        }
        let t = truncated.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return t.isEmpty ? "untitled" : t
    }

    /// Validates a full relative path (no leading `/`, no `..`, no empty segments).
    static func validateRelativePath(_ relativePath: String) throws {
        guard !relativePath.isEmpty else {
            throw NoteRepositoryError.invalidRelativePath(relativePath)
        }
        guard !relativePath.hasPrefix("/"), !relativePath.hasPrefix("\\") else {
            throw NoteRepositoryError.invalidRelativePath(relativePath)
        }
        let segments = relativePath.split(separator: "/").map(String.init)
        guard !segments.isEmpty else {
            throw NoteRepositoryError.invalidRelativePath(relativePath)
        }
        for seg in segments {
            try validateSingleSegment(seg)
        }
    }

    static func validateSingleSegment(_ segment: String) throws {
        guard !segment.isEmpty else {
            throw NoteRepositoryError.invalidRelativePath(segment)
        }
        guard segment != ".", segment != ".." else {
            throw NoteRepositoryError.invalidRelativePath(segment)
        }
        guard !segment.contains("/"), !segment.contains("\\"), !segment.contains(":") else {
            throw NoteRepositoryError.invalidRelativePath(segment)
        }
        guard !segment.hasPrefix(".") else {
            throw NoteRepositoryError.invalidRelativePath(segment)
        }
        if segment.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            throw NoteRepositoryError.invalidRelativePath(segment)
        }
    }

    /// `vault/a/b/c` + `note` ext → `vault/a/b/c.note`
    static func fileURL(vaultRoot: URL, relativePathWithoutExtension: String, extension ext: String) -> URL {
        let parts = relativePathWithoutExtension.split(separator: "/").map(String.init)
        guard let last = parts.last else {
            return vaultRoot.appendingPathComponent("invalid.\(ext)")
        }
        var url = vaultRoot
        for p in parts.dropLast() {
            url = url.appendingPathComponent(p, isDirectory: true)
        }
        return url.appendingPathComponent("\(last).\(ext)", isDirectory: false)
    }

    /// Directory URL for the parent of a note path (creates no files; for mkdir).
    static func parentDirectoryURL(vaultRoot: URL, relativePathWithoutExtension: String) -> URL {
        let parts = relativePathWithoutExtension.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return vaultRoot }
        var url = vaultRoot
        for p in parts.dropLast() {
            url = url.appendingPathComponent(p, isDirectory: true)
        }
        return url
    }

    /// Ensures parent directories exist for a note relative path.
    static func ensureParentDirectories(vaultRoot: URL, relativePathWithoutExtension: String) throws {
        let parent = parentDirectoryURL(vaultRoot: vaultRoot, relativePathWithoutExtension: relativePathWithoutExtension)
        guard parent.path != vaultRoot.path else { return }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
}

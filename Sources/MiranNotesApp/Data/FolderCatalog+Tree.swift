import Foundation
import MiranNotesCore

extension FolderCatalog {
    func folder(id: UUID) -> FolderEntry? {
        folders.first { $0.id == id }
    }

    func childFolders(of parentID: UUID) -> [FolderEntry] {
        folders.filter { $0.parentFolderID == parentID && $0.id != Self.rootFolderID }
    }

    /// Slug directory path under the vault for this folder (no trailing slash). Empty for root.
    func relativeDirectoryPath(for folderID: UUID) -> String {
        guard folderID != Self.rootFolderID else { return "" }
        var parts: [String] = []
        var current: UUID? = folderID
        while let id = current, id != Self.rootFolderID {
            guard let entry = folders.first(where: { $0.id == id }) else { break }
            parts.append(VaultPath.slugifySegment(entry.name))
            current = entry.parentFolderID
        }
        return parts.reversed().joined(separator: "/")
    }

    /// On-disk directory URL for a folder (may not exist yet if empty).
    func directoryURL(vaultRoot: URL, folderID: UUID) -> URL {
        let rel = relativeDirectoryPath(for: folderID)
        guard !rel.isEmpty else { return vaultRoot }
        var url = vaultRoot
        for seg in rel.split(separator: "/") {
            url = url.appendingPathComponent(String(seg), isDirectory: true)
        }
        return url
    }

    mutating func addFolder(parentID: UUID, name: String) throws -> UUID {
        ensureRoot()
        guard folder(id: parentID) != nil else {
            throw NoteRepositoryError.folderNotFound(parentID)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NoteRepositoryError.invalidFolderName(name)
        }
        let slug = VaultPath.slugifySegment(trimmed)
        let siblings = childFolders(of: parentID)
        if siblings.contains(where: { VaultPath.slugifySegment($0.name) == slug }) {
            throw NoteRepositoryError.duplicateFolderName(trimmed)
        }
        let id = UUID()
        folders.append(FolderEntry(id: id, name: trimmed, parentFolderID: parentID))
        isDirty = true
        return id
    }

    mutating func renameFolder(id: UUID, newName: String) throws {
        ensureRoot()
        guard id != Self.rootFolderID else {
            throw NoteRepositoryError.invalidFolderName("root")
        }
        guard let idx = folders.firstIndex(where: { $0.id == id }) else {
            throw NoteRepositoryError.folderNotFound(id)
        }
        let parentID = folders[idx].parentFolderID ?? Self.rootFolderID
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NoteRepositoryError.invalidFolderName(newName)
        }
        let slug = VaultPath.slugifySegment(trimmed)
        let siblings = childFolders(of: parentID).filter { $0.id != id }
        if siblings.contains(where: { VaultPath.slugifySegment($0.name) == slug }) {
            throw NoteRepositoryError.duplicateFolderName(trimmed)
        }
        folders[idx].name = trimmed
        isDirty = true
    }

    mutating func moveFolder(id: UUID, newParentID: UUID) throws {
        ensureRoot()
        guard id != Self.rootFolderID else {
            throw NoteRepositoryError.invalidFolderMove
        }
        guard folder(id: newParentID) != nil else {
            throw NoteRepositoryError.folderNotFound(newParentID)
        }
        guard let idx = folders.firstIndex(where: { $0.id == id }) else {
            throw NoteRepositoryError.folderNotFound(id)
        }
        var walk: UUID? = newParentID
        while let w = walk {
            if w == id { throw NoteRepositoryError.invalidFolderMove }
            walk = folder(id: w)?.parentFolderID
        }
        let entry = folders[idx]
        let slug = VaultPath.slugifySegment(entry.name)
        let siblings = childFolders(of: newParentID).filter { $0.id != id }
        if siblings.contains(where: { VaultPath.slugifySegment($0.name) == slug }) {
            throw NoteRepositoryError.duplicateFolderName(entry.name)
        }
        folders[idx].parentFolderID = newParentID
        isDirty = true
    }

    mutating func removeFolderEntry(id: UUID) throws {
        ensureRoot()
        guard id != Self.rootFolderID else {
            throw NoteRepositoryError.invalidFolderMove
        }
        guard let idx = folders.firstIndex(where: { $0.id == id }) else {
            throw NoteRepositoryError.folderNotFound(id)
        }
        if !childFolders(of: id).isEmpty {
            throw NoteRepositoryError.folderNotEmpty(id)
        }
        folders.remove(at: idx)
        isDirty = true
    }
}

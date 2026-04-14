import Foundation
import MiranNotesCore

extension FolderCatalog {
    private static func makeUniqueStorageSegment(base: String, used: Set<String>) -> String {
        if !used.contains(base) {
            return base
        }
        var index = 2
        while true {
            let candidate = "\(base)-\(index)"
            if !used.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    mutating func ensureStorageSegments() {
        var changed = false
        if let rootIndex = folders.firstIndex(where: { $0.id == Self.rootFolderID }), folders[rootIndex].storageSegment != "" {
            folders[rootIndex].storageSegment = ""
            changed = true
        }

        var usedByParent: [UUID: Set<String>] = [:]
        let sortedIndices = folders.indices.sorted {
            folders[$0].parentFolderID?.uuidString ?? "" < folders[$1].parentFolderID?.uuidString ?? ""
        }
        for index in sortedIndices {
            if folders[index].id == Self.rootFolderID { continue }
            let parentID = folders[index].parentFolderID ?? Self.rootFolderID
            var base = folders[index].storageSegment.trimmingCharacters(in: .whitespacesAndNewlines)
            if base.isEmpty {
                base = VaultPath.slugifySegment(folders[index].name)
            }
            do {
                try VaultPath.validateSingleSegment(base)
            } catch {
                base = VaultPath.slugifySegment(folders[index].name)
            }

            let used = usedByParent[parentID, default: []]
            let unique = Self.makeUniqueStorageSegment(base: base, used: used)
            if folders[index].storageSegment != unique {
                folders[index].storageSegment = unique
                changed = true
            }
            usedByParent[parentID, default: []].insert(unique)
        }
        if changed {
            isDirty = true
        }
    }

    private func allocateStorageSegment(name: String, parentID: UUID, excludingID: UUID? = nil) -> String {
        let base = VaultPath.slugifySegment(name)
        let used = Set(
            childFolders(of: parentID)
                .filter { $0.id != excludingID }
                .map(\.storageSegment)
        )
        return Self.makeUniqueStorageSegment(base: base, used: used)
    }

    func folder(id: UUID) -> FolderEntry? {
        folders.first { $0.id == id }
    }

    func childFolders(of parentID: UUID) -> [FolderEntry] {
        folders.filter { $0.parentFolderID == parentID && $0.id != Self.rootFolderID }
    }

    /// Storage directory path under the vault for this folder (no trailing slash). Empty for root.
    func relativeDirectoryPath(for folderID: UUID) -> String {
        guard folderID != Self.rootFolderID else { return "" }
        var parts: [String] = []
        var current: UUID? = folderID
        while let id = current, id != Self.rootFolderID {
            guard let entry = folders.first(where: { $0.id == id }) else { break }
            let segment = entry.storageSegment.isEmpty ? VaultPath.slugifySegment(entry.name) : entry.storageSegment
            parts.append(segment)
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
        let id = UUID()
        let storageSegment = allocateStorageSegment(name: trimmed, parentID: parentID)
        folders.append(FolderEntry(id: id, name: trimmed, storageSegment: storageSegment, parentFolderID: parentID))
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
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NoteRepositoryError.invalidFolderName(newName)
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
        let segment = allocateStorageSegment(
            name: folders[idx].name,
            parentID: newParentID,
            excludingID: id
        )
        folders[idx].parentFolderID = newParentID
        folders[idx].storageSegment = segment
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

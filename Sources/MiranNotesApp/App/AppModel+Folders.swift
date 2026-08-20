// Folder roles, CRUD, hidden folders (split from AppModel.swift; mechanical move).
import AppKit
import Foundation
import MiranNotesCore
import Observation
import os.log
import SwiftUI

extension AppModel {
    func folderRole(for folderID: UUID) -> FolderRole? {
        guard folderID != FolderCatalog.rootFolderID else { return nil }
        return folderCatalog.folder(id: folderID)?.role
    }

    func setFolderRole(_ role: FolderRole, folderID: UUID) {
        Task { @MainActor in
            do {
                try await repository.setFolderRole(role, folderID: folderID)
                await refreshNotes()
            } catch {
                userAlert = .recoverable(
                    message: error.localizedDescription,
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    /// Moves a note into `toFolderID` after validating folder roles; violations alert without touching disk.
    func moveNote(noteID: UUID, toFolderID: UUID) {
        guard let summary = noteSummaries.first(where: { $0.noteID == noteID }) else { return }
        guard summary.folderID != toFolderID else { return }
        guard folderCatalog.allowsNotes(in: toFolderID) else {
            userAlert = .message(
                "Notes can’t be moved into a Dashboard folder — dashboards hold nested folders only."
            )
            return
        }
        Task { @MainActor in
            do {
                try await repository.moveNote(noteID: noteID, toFolderID: toFolderID)
                await refreshNotes()
            } catch {
                userAlert = .recoverable(
                    message: "Could not move the note: \(error.localizedDescription)",
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    /// Moves a folder under `newParentID` after validating that the destination accepts nested folders.
    func moveFolder(id: UUID, newParentID: UUID) {
        guard id != newParentID else { return }
        guard folderCatalog.allowsNestedFolders(in: newParentID) else {
            userAlert = .message(
                "Folders can only be nested inside Dashboard folders (or at the vault root)."
            )
            return
        }
        Task { @MainActor in
            do {
                try await repository.moveFolder(id: id, newParentID: newParentID)
                await refreshNotes()
            } catch {
                userAlert = .recoverable(
                    message: "Could not move the folder: \(error.localizedDescription)",
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    /// Repository folders that can receive a note via "Move to…" (all note-accepting folders except the current one).
    func moveDestinationFolders(excludingFolderID: UUID?) -> [FolderEntry] {
        folderCatalog.folders
            .filter { $0.id != excludingFolderID && $0.id != FolderCatalog.rootFolderID && folderCatalog.allowsNotes(in: $0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Parent for **New Folder** from the toolbar or shortcut: nested under the selected dashboard, otherwise vault root.
    func newFolderParentID(forPane pane: Int) -> UUID {
        guard let selected = workspacePanes[pane].selectedFolderID else {
            return FolderCatalog.rootFolderID
        }
        if folderCatalog.allowsNestedFolders(in: selected) {
            return selected
        }
        return FolderCatalog.rootFolderID
    }

    /// Menu / keyboard entry point for new folder; gates on workspace readiness, then delegates to ``createFolder()``.

    func reconcileHiddenFoldersWithCatalogIfNeeded() {
        let parent = scopeParentIDForTopLevelFolders
        let pruned = VaultHiddenFoldersStore.pruned(
            hiddenTopLevelFolderIDs,
            folderCatalog: folderCatalog,
            parentFolderID: parent
        )
        guard pruned != hiddenTopLevelFolderIDs else { return }
        hiddenTopLevelFolderIDs = pruned
        VaultHiddenFoldersStore.save(pruned, vaultURL: repository.vaultURL)
    }

    func persistHiddenTopLevelFolderIDs() {
        VaultHiddenFoldersStore.save(hiddenTopLevelFolderIDs, vaultURL: repository.vaultURL)
    }

    func hideTopLevelFolders(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        hiddenTopLevelFolderIDs.formUnion(ids)
        persistHiddenTopLevelFolderIDs()
        for i in workspacePanes.indices {
            if let selected = workspacePanes[i].selectedFolderID, ids.contains(selected) {
                workspacePanes[i].selectedFolderID = pickDefaultFolderID()
            }
        }
    }

    func unhideTopLevelFolders(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        hiddenTopLevelFolderIDs.subtract(ids)
        persistHiddenTopLevelFolderIDs()
    }


    func createFolder(parentID: UUID? = nil, name: String = "New Folder", pane: Int? = nil) {
        let targetPane = pane ?? activePaneIndex
        let resolvedParent = parentID ?? newFolderParentID(forPane: targetPane)
        Task { @MainActor in
            do {
                let id = try await repository.createFolder(parentID: resolvedParent, name: name)
                markVaultWelcomeDismissedIfNeeded()
                await refreshNotes()
                self.workspacePanes[targetPane].selectedFolderID = id
            } catch {
                userAlert = .recoverable(
                    message: error.localizedDescription,
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    func deleteFolder(id: UUID) {
        Task { @MainActor in
            do {
                try await repository.deleteFolder(id: id)
                hiddenTopLevelFolderIDs.remove(id)
                persistHiddenTopLevelFolderIDs()
                await refreshNotes()
            } catch {
                userAlert = .recoverable(
                    message: error.localizedDescription,
                    kind: .retryRefreshNotesAndFolderUI
                )
            }
        }
    }

    /// Deletes several folders in order; refreshes once after all succeed. On first failure, refreshes and sets ``userAlert``.
    func deleteTopLevelFolders(ids: Set<UUID>, onSuccess: @escaping @MainActor (_ deletedCount: Int) -> Void) {
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            var deleted = 0
            for id in ids {
                do {
                    try await repository.deleteFolder(id: id)
                    hiddenTopLevelFolderIDs.remove(id)
                    deleted += 1
                } catch {
                    persistHiddenTopLevelFolderIDs()
                    await refreshNotes()
                    userAlert = .recoverable(
                        message: error.localizedDescription,
                        kind: .retryRefreshNotesAndFolderUI
                    )
                    return
                }
            }
            persistHiddenTopLevelFolderIDs()
            await refreshNotes()
            onSuccess(deleted)
        }
    }


    func renameFolder(id: UUID, newName: String) {
        Task { @MainActor in
            _ = await renameFolderAndWait(id: id, newName: newName)
        }
    }

    /// Performs folder rename and refresh; on failure sets ``userAlert`` and returns `false`.
    @discardableResult
    func renameFolderAndWait(id: UUID, newName: String) async -> Bool {
        do {
            try await repository.renameFolder(id: id, newName: newName)
            await refreshNotes()
            return true
        } catch {
            userAlert = .recoverable(
                message: error.localizedDescription,
                kind: .retryRefreshNotesAndFolderUI
            )
            return false
        }
    }

}

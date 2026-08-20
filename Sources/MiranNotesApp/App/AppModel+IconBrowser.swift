// Finder-style icon browser state: per-folder icon positions and list/icons view mode.
import Foundation
import SwiftUI

/// How a folder page renders its contents.
enum FolderPageViewMode: String {
    case icons
    case list
}

extension AppModel {
    private func iconLayoutFileName(folderID: UUID) -> String {
        "icon-layout/\(folderID.uuidString.lowercased()).json"
    }

    /// Saved icon positions for a folder's browser (cached after first read).
    func iconPositions(folderID: UUID) -> [UUID: CGPoint] {
        if let cached = folderIconLayoutCache[folderID] { return cached }
        let state = uiStateStore.load(FolderIconLayoutState.self, name: iconLayoutFileName(folderID: folderID))
        var positions: [UUID: CGPoint] = [:]
        for (key, point) in state?.positions ?? [:] {
            if let id = UUID(uuidString: key) {
                positions[id] = CGPoint(x: point.x, y: point.y)
            }
        }
        folderIconLayoutCache[folderID] = positions
        return positions
    }

    /// Persists one icon's position, pruning entries for items no longer in the folder.
    func setIconPosition(_ point: CGPoint, itemID: UUID, folderID: UUID, validItemIDs: Set<UUID>) {
        var positions = iconPositions(folderID: folderID)
        positions[itemID] = point
        positions = positions.filter { validItemIDs.contains($0.key) }
        folderIconLayoutCache[folderID] = positions
        persistIconPositions(positions, folderID: folderID)
    }

    /// "Clean Up": drop all saved positions so icons re-flow into the default grid.
    func clearIconLayout(folderID: UUID) {
        folderIconLayoutCache[folderID] = [:]
        uiStateStore.remove(name: iconLayoutFileName(folderID: folderID))
    }

    func folderPageViewMode(folderID: UUID) -> FolderPageViewMode {
        if let raw = folderViewModes[folderID], let mode = FolderPageViewMode(rawValue: raw) {
            return mode
        }
        return .icons
    }

    func setFolderPageViewMode(_ mode: FolderPageViewMode, folderID: UUID) {
        folderViewModes[folderID] = mode.rawValue
        var state = FolderViewModesState()
        state.modes = Dictionary(uniqueKeysWithValues: folderViewModes.map { ($0.key.uuidString.lowercased(), $0.value) })
        try? uiStateStore.save(state, name: "folder-view-modes.json")
    }

    func loadFolderViewModes() {
        let state = uiStateStore.load(FolderViewModesState.self, name: "folder-view-modes.json")
        var modes: [UUID: String] = [:]
        for (key, value) in state?.modes ?? [:] {
            if let id = UUID(uuidString: key) {
                modes[id] = value
            }
        }
        folderViewModes = modes
        folderIconLayoutCache = [:]
    }

    private func persistIconPositions(_ positions: [UUID: CGPoint], folderID: UUID) {
        var state = FolderIconLayoutState()
        state.positions = Dictionary(uniqueKeysWithValues: positions.map {
            ($0.key.uuidString.lowercased(), FolderIconPoint(x: $0.value.x, y: $0.value.y))
        })
        try? uiStateStore.save(state, name: iconLayoutFileName(folderID: folderID))
    }
}

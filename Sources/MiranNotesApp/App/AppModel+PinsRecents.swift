// Pinned and recently opened notes (presentation state under `.miran/ui-state/`).
import Foundation

extension AppModel {
    var uiStateStore: VaultUIStateStore {
        VaultUIStateStore(vaultURL: repository.vaultURL)
    }

    /// Pinned notes that still exist, in pin order.
    var pinnedNoteSummaries: [NoteSummary] {
        pinnedNoteIDs.compactMap { id in noteSummaries.first(where: { $0.noteID == id }) }
    }

    /// Recent notes that still exist, most recent first, pinned ones excluded.
    var recentNoteSummaries: [NoteSummary] {
        recentNoteIDs
            .filter { !pinnedNoteIDs.contains($0) }
            .compactMap { id in noteSummaries.first(where: { $0.noteID == id }) }
    }

    func isNotePinned(_ noteID: UUID) -> Bool {
        pinnedNoteIDs.contains(noteID)
    }

    func togglePinned(noteID: UUID) {
        if let index = pinnedNoteIDs.firstIndex(of: noteID) {
            pinnedNoteIDs.remove(at: index)
        } else {
            pinnedNoteIDs.append(noteID)
        }
        persistPins()
    }

    func loadPinsAndRecents() {
        pinnedNoteIDs = uiStateStore.load(VaultPinnedNotesState.self, name: "pins.json")?.noteIDs ?? []
        recentNoteIDs = uiStateStore.load(VaultRecentNotesState.self, name: "recents.json")?.noteIDs ?? []
    }

    /// Moves `noteID` to the front of the recents list; persistence is debounced because this
    /// fires on every note navigation.
    func recordRecentNote(_ noteID: UUID) {
        var ids = recentNoteIDs
        ids.removeAll { $0 == noteID }
        ids.insert(noteID, at: 0)
        if ids.count > VaultRecentNotesState.maxCount {
            ids.removeLast(ids.count - VaultRecentNotesState.maxCount)
        }
        guard ids != recentNoteIDs else { return }
        recentNoteIDs = ids
        schedulePersistRecents()
    }

    private func persistPins() {
        do {
            try uiStateStore.save(VaultPinnedNotesState(noteIDs: pinnedNoteIDs), name: "pins.json")
        } catch {
            userAlert = .message("Could not save pinned notes: \(error.localizedDescription)")
        }
    }

    private func schedulePersistRecents() {
        recentsPersistTask?.cancel()
        let store = uiStateStore
        recentsPersistTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? store.save(VaultRecentNotesState(noteIDs: self.recentNoteIDs), name: "recents.json")
        }
    }
}

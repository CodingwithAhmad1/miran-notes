// Trash page state: list, restore, permanent delete (files under `.miran/trash/`).
import Foundation

extension AppModel {
    func refreshTrashedNotes() {
        Task { @MainActor in
            trashedNotes = await repository.listTrashedNotes()
        }
    }

    func restoreTrashedNote(noteID: UUID) {
        Task { @MainActor in
            do {
                try await repository.restoreTrashedNote(noteID: noteID)
                await refreshNotes()
                refreshTrashedNotes()
            } catch {
                userAlert = .message("Could not restore the note: \(error.localizedDescription)")
            }
        }
    }

    func deleteTrashedNotePermanently(noteID: UUID) {
        Task { @MainActor in
            await repository.deleteTrashedNotePermanently(noteID: noteID)
            refreshTrashedNotes()
        }
    }

    func emptyTrash() {
        Task { @MainActor in
            await repository.emptyTrash()
            refreshTrashedNotes()
        }
    }
}

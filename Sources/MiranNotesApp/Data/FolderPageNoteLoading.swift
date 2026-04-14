import Foundation
import MiranNotesCore

/// Loads folder-page note buffers from disk (parallel column editing).
enum FolderPageNoteLoading {
    @MainActor
    static func loadDocuments(
        folderID: UUID?,
        noteSummaries: [NoteSummary],
        repository: NoteRepository
    ) async -> (documents: [UUID: NoteDocument], lastPersisted: [UUID: NoteDocument], loadError: String?) {
        guard let fid = folderID else {
            return ([:], [:], nil)
        }
        var documents: [UUID: NoteDocument] = [:]
        var lastPersisted: [UUID: NoteDocument] = [:]
        var loadError: String?
        let notes = noteSummaries.filter { $0.folderID == fid }
        for n in notes {
            do {
                let result = try await repository.loadNote(noteID: n.noteID)
                let doc = result.document
                documents[n.noteID] = doc
                lastPersisted[n.noteID] = doc
            } catch {
                loadError = "Failed to load note: \(error.localizedDescription)"
            }
        }
        return (documents, lastPersisted, loadError)
    }
}

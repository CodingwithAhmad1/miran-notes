import Foundation
import MiranNotesCore

/// Per-tile workspace state: folder/note selection, editor buffer, undo, and vault search for that tile.
struct WorkspacePaneSession {
    var selectedFolderID: UUID?
    var selectedNoteID: UUID?
    var selectedBaseName: String?
    var activeDocument: NoteDocument?

    var vaultSearchQuery: String = ""
    var editorFindQuery: String = ""
    var editorCursorOffset: Int = 0
    var editorTextSelection: MiranNotesCore.TextRange = MiranNotesCore.TextRange(start: 0, length: 0)

    var lastPersistedDocument: NoteDocument?
    var lastKnownDiskDate: Date?
    var lastKnownDiskRevision: DocumentRevisionToken?
    var lastKnownNoteTextSHA256: String?

    var navigationGeneration: Int = 0

    var undoCheckpoints: [UndoCheckpoint] = []
    var undoActionNames: [String] = []
    var lastUndoRegistrationDate: Date?
    var lastRecordedUndoWasSingleReplaceText = false

    var backlinks: [BacklinkItem] = []
    var repairAdvisory: RepairAdvisory?
}

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Custom pasteboard type for dragging a note between Miran surfaces (icon browser, sidebar).
    static let miranNote = UTType(exportedAs: "com.miran.notes.note-reference")
}

/// Drag payload for a note (noteID + title for drop-target display).
struct NoteTransfer: Codable, Transferable, Sendable {
    var noteID: UUID
    var title: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .miranNote)
    }
}

import Foundation

/// Allowed on-disk note body extensions (sidecar remains `.meta.json`).
enum NoteBodyFileExtension: String, CaseIterable, Sendable {
    case txt
    case md

    static func normalize(_ raw: String) -> NoteBodyFileExtension {
        raw.lowercased() == "md" ? .md : .txt
    }

    var fileExtension: String { rawValue }
}

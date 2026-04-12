import Foundation
import MiranNotesCore

enum MetadataSchema {
    static let currentVersion = NoteMetadata.currentSchemaVersion

    static func migrate(_ metadata: NoteMetadata) -> NoteMetadata {
        var migrated = metadata
        if migrated.schemaVersion < currentVersion {
            migrated.schemaVersion = currentVersion
        }
        return migrated
    }
}

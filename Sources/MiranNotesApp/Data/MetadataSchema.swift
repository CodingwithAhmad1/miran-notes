import Foundation
import MiranNotesCore

enum MetadataSchema {
    static let currentVersion = NoteMetadata.currentSchemaVersion

    static func migrate(_ metadata: NoteMetadata) -> NoteMetadata {
        // MVP keeps a single schema version while preserving a migration seam.
        if metadata.schemaVersion >= currentVersion {
            return metadata
        }

        var migrated = metadata
        migrated.schemaVersion = currentVersion
        return migrated
    }
}

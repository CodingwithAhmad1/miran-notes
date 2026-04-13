import Foundation
import MiranNotesCore

struct RelationshipIndex: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var relationships: [LinkRelationship]
    var isDirty: Bool = false

    enum CodingKeys: String, CodingKey {
        case schemaVersion, relationships
    }

    init(schemaVersion: Int = currentSchemaVersion, relationships: [LinkRelationship] = []) {
        self.schemaVersion = schemaVersion
        self.relationships = relationships
    }

    mutating func replaceLinks(from sourceNoteID: UUID, with newRelationships: [LinkRelationship]) {
        let existing = relationships.filter { $0.sourceNoteID == sourceNoteID }
        guard existing != newRelationships else { return }
        relationships.removeAll { $0.sourceNoteID == sourceNoteID }
        relationships.append(contentsOf: newRelationships)
        isDirty = true
    }

    /// Drops every relationship involving `noteID` as source or as a note/artifact target.
    mutating func removeAllInvolvingNote(_ noteID: UUID) {
        let before = relationships.count
        relationships.removeAll { rel in
            if rel.sourceNoteID == noteID { return true }
            switch rel.target {
            case .note(let id):
                return id == noteID
            case .artifact(let nid, _, _):
                return nid == noteID
            case .folder, .externalFile, .externalFolder, .database, .databaseRow:
                return false
            }
        }
        if relationships.count != before {
            isDirty = true
        }
    }

    /// Drops every relationship targeting a specific database or its rows.
    mutating func removeAllInvolvingDatabase(_ databaseID: UUID) {
        let before = relationships.count
        relationships.removeAll { rel in
            switch rel.target {
            case .database(let id):
                return id == databaseID
            case .databaseRow(let dbID, _):
                return dbID == databaseID
            default:
                return false
            }
        }
        if relationships.count != before {
            isDirty = true
        }
    }
}

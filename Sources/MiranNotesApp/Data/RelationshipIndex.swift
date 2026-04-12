import Foundation
import MiranNotesCore

struct RelationshipIndex: Codable, Equatable {
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
            case .folder, .externalFile, .externalFolder:
                return false
            }
        }
        if relationships.count != before {
            isDirty = true
        }
    }
}

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

    /// Drops every relationship involving `noteID` as source or as a note target.
    mutating func removeAllInvolvingNote(_ noteID: UUID) {
        let before = relationships.count
        relationships.removeAll { rel in
            if rel.sourceNoteID == noteID { return true }
            switch rel.target {
            case .note(let id):
                return id == noteID
            case .folder, .externalFile, .externalFolder:
                return false
            }
        }
        if relationships.count != before {
            isDirty = true
        }
    }

    mutating func remapNoteID(from oldID: UUID, to newID: UUID) {
        guard oldID != newID else { return }
        for i in relationships.indices {
            if relationships[i].sourceNoteID == oldID {
                relationships[i].sourceNoteID = newID
                isDirty = true
            }
            switch relationships[i].target {
            case .note(let id) where id == oldID:
                relationships[i].target = .note(noteID: newID)
                isDirty = true
            default:
                break
            }
        }
    }
}

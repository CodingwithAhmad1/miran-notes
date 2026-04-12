import Foundation
import MiranNotesCore

struct RelationshipIndex: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var relationships: [LinkRelationship]

    init(schemaVersion: Int = currentSchemaVersion, relationships: [LinkRelationship] = []) {
        self.schemaVersion = schemaVersion
        self.relationships = relationships
    }

    mutating func replaceLinks(from sourceNoteID: UUID, with newRelationships: [LinkRelationship]) {
        relationships.removeAll { $0.sourceNoteID == sourceNoteID }
        relationships.append(contentsOf: newRelationships)
    }
}

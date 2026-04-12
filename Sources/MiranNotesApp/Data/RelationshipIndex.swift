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
}

import Foundation
import MiranNotesCore

/// Persisted forward link edges: source note ID → target note IDs (deduplicated).
struct LinkGraph: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    /// Source `noteID` → unique target `noteID`s linked from that note’s metadata.
    var outgoing: [UUID: [UUID]]

    init(schemaVersion: Int = currentSchemaVersion, outgoing: [UUID: [UUID]] = [:]) {
        self.schemaVersion = schemaVersion
        self.outgoing = outgoing
    }

    mutating func setOutgoing(from sourceNoteID: UUID, to targets: [UUID]) {
        let unique = Array(Set(targets))
        if unique.isEmpty {
            outgoing.removeValue(forKey: sourceNoteID)
        } else {
            outgoing[sourceNoteID] = unique.sorted { $0.uuidString < $1.uuidString }
        }
    }

    func backlinks(to targetNoteID: UUID) -> [UUID] {
        outgoing.compactMap { source, targets in
            targets.contains(targetNoteID) ? source : nil
        }.sorted { $0.uuidString < $1.uuidString }
    }
}

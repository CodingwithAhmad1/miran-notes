import Foundation
import MiranNotesCore

/// Persisted forward link edges: source note ID → target note IDs (deduplicated).
struct LinkGraph: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    /// Source `noteID` → unique target `noteID`s linked from that note's metadata.
    var outgoing: [UUID: [UUID]]
    /// True when in-memory outgoing has been modified since the last disk write.
    /// Not persisted — always `false` after a round-trip through Codable.
    var isDirty: Bool = false

    // Exclude `isDirty` from Codable so it is always false after decoding.
    enum CodingKeys: String, CodingKey {
        case schemaVersion, outgoing
    }

    init(schemaVersion: Int = currentSchemaVersion, outgoing: [UUID: [UUID]] = [:]) {
        self.schemaVersion = schemaVersion
        self.outgoing = outgoing
    }

    mutating func setOutgoing(from sourceNoteID: UUID, to targets: [UUID]) {
        let unique = targets.isEmpty ? [] : Array(Set(targets)).sorted { $0.uuidString < $1.uuidString }
        let current = outgoing[sourceNoteID] ?? []
        guard current != unique else { return }
        if unique.isEmpty {
            outgoing.removeValue(forKey: sourceNoteID)
        } else {
            outgoing[sourceNoteID] = unique
        }
        isDirty = true
    }

    func backlinks(to targetNoteID: UUID) -> [UUID] {
        outgoing.compactMap { source, targets in
            targets.contains(targetNoteID) ? source : nil
        }.sorted { $0.uuidString < $1.uuidString }
    }

    /// Removes a note as a link source and strips it from all outgoing target lists (e.g. when deleting the note).
    mutating func removeNote(_ noteID: UUID) {
        if outgoing.removeValue(forKey: noteID) != nil {
            isDirty = true
        }
        for key in Array(outgoing.keys) {
            guard let targets = outgoing[key] else { continue }
            let filtered = targets.filter { $0 != noteID }
            guard filtered.count != targets.count else { continue }
            if filtered.isEmpty {
                outgoing.removeValue(forKey: key)
            } else {
                outgoing[key] = filtered
            }
            isDirty = true
        }
    }
}

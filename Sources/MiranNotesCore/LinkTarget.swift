import Foundation

public enum LinkTarget: Codable, Equatable, Hashable, Sendable {
    case note(noteID: UUID)
    case folder(folderID: UUID)
    case externalFile(bookmarkID: UUID)
    case externalFolder(bookmarkID: UUID)
    case artifact(noteID: UUID, artifactID: UUID, kind: EmbeddedArtifactKind)
}

public struct LinkRelationship: Codable, Equatable, Hashable, Sendable {
    public var sourceNoteID: UUID
    public var target: LinkTarget
    public var relationshipKind: String

    public init(sourceNoteID: UUID, target: LinkTarget, relationshipKind: String) {
        self.sourceNoteID = sourceNoteID
        self.target = target
        self.relationshipKind = relationshipKind
    }
}
